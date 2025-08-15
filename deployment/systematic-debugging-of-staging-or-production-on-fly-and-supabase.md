# Production Error Resolution Playbook for Phoenix on Fly.io with Supabase

A systematic step-by-step guide for debugging and resolving errors in staging and production Phoenix applications deployed on Fly.io with Supabase backend.

## Prerequisites

This playbook assumes you have:
- Honeybadger or AppSignal configured for error tracking
- Access to Fly.io CLI and dashboard
- Access to Supabase dashboard
- Application logs accessible via `fly logs`

## When an Error Occurs: The Systematic Approach

### Step 1: Identify Scope & Impact (2 minutes)

First, determine the blast radius of the error.

```bash
# Check overall health of all instances
fly status

# See if errors are widespread or isolated
fly logs --grep "ERROR\|500" --since 5m | grep -c "instance"

# Identify affected endpoints
fly logs --grep "request_path" --since 5m | cut -d'"' -f4 | sort | uniq -c

# Check error rate
fly logs --since 5m | grep -c "ERROR" 
fly logs --since 5m | grep -c "request_id"  # Compare to total requests
```

**Decision Tree:**
- **Single instance failing?** → Jump to [Step 3](#step-3-instance-specific-debugging-5-minutes) (instance-specific)
- **Single endpoint failing?** → Jump to [Step 4](#step-4-trace-the-specific-error-10-minutes) (code-specific)  
- **Everything failing?** → Continue to Step 2 (systemic failure)

### Step 2: Check External Dependencies (3 minutes)

Since Supabase is your primary dependency, check it first.

```bash
# Test Supabase connectivity from Fly instance
fly ssh console
curl -I https://YOUR_PROJECT.supabase.co/rest/v1/
# Should return 200 OK

# Check if you can query the database
curl https://YOUR_PROJECT.supabase.co/rest/v1/health_check \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"

# Test database connection specifically
/app/bin/my_app remote
# In IEx:
MyApp.Repo.query("SELECT 1")
```

**Check Supabase Dashboard:**
1. Go to https://app.supabase.com/project/YOUR_PROJECT/database/pooler
2. Check connection pool usage
3. Check for any ongoing incidents at https://status.supabase.com

**Common Supabase issues:**
- **Connection pool exhausted**: Increase pool size in Supabase dashboard under Settings > Database
- **Rate limiting**: Check API usage in Supabase dashboard
- **SSL certificate**: Ensure `ssl: true` in your Ecto config

### Step 3: Instance-Specific Debugging (5 minutes)

When only one Fly instance is failing:

```bash
# List all instances and their status
fly status --all

# SSH into the specific failing instance
fly ssh console --select  # Interactive selection
# OR
fly ssh console --instance <instance-id>

# Check system resources
df -h  # Disk space
free -m  # Memory
top -n 1  # CPU and processes

# Check if BEAM VM is healthy
ps aux | grep beam
# Look for beam.smp process using >90% CPU or memory

# Check Erlang VM status
/app/bin/my_app remote
# In IEx:
:erlang.memory()
:erlang.statistics(:garbage_collection)
Process.list() |> length()  # Total process count

# Quick fix: Restart just that instance
exit  # Exit IEx first
exit  # Exit SSH
fly vm restart <instance-id>
```

**If instance keeps failing:**
- Memory leak likely - check for accumulating processes
- Corrupted ETS tables - restart clears these
- Hardware issue - Fly will usually auto-migrate

### Step 4: Trace the Specific Error (10 minutes)

Extract the exact error details:

```bash
# Get full error with stack trace
fly logs --since 10m | grep -A 30 "ERROR"

# Find specific error types
fly logs --since 10m | grep -A 20 "** (.*Error)"

# Get request ID from error tracking, then trace it
fly logs --grep "REQUEST_ID_FROM_HONEYBADGER"
```

#### Common Error Patterns and Solutions

**Database Connection Errors:**
```elixir
# Error: DBConnection.ConnectionError or Postgrex.Error
fly ssh console
/app/bin/my_app remote

# Check connection pool status
:ets.lookup(:telemetry_handler_table, {MyApp.Repo, :pool})
MyApp.Repo.query!("SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")

# Emergency fix - bump pool size
# In config/runtime.exs, increase:
pool_size: String.to_integer(System.get_env("POOL_SIZE") || "50")
```

**Nil Match Errors:**
```elixir
# Error: (MatchError) no match of right hand side value: nil

# Usually means unexpected nil from database or API
# Quick fix - add defensive coding:
case MyApp.Repo.get(User, id) do
  nil -> {:error, :not_found}
  user -> {:ok, user}
end
```

**Timeout Errors:**
```elixir
# Error: (Ecto.Query.TimeoutError)

# Find slow queries in Supabase dashboard
# Go to: Database > Query Performance

# Or from console:
fly ssh console
/app/bin/my_app remote

# Run explain on suspicious queries
MyApp.Repo.query!("""
  EXPLAIN ANALYZE 
  SELECT * FROM your_table WHERE complex_condition
""")
```

**JSON Decode Errors:**
```elixir
# Error: (Jason.DecodeError)

# Usually malformed response from API or webhook
# Add defensive parsing:
case Jason.decode(body) do
  {:ok, json} -> process(json)
  {:error, _} -> 
    Logger.error("Invalid JSON", body: body)
    {:error, :invalid_json}
end
```

### Step 5: Reproduce Locally (10 minutes)

Get the exact failing request from Honeybadger/AppSignal:
- Request method and path
- All parameters
- Headers (especially authentication)
- User context

```bash
# Set up Supabase tunnel for local testing
# Get connection string from Supabase dashboard
export DATABASE_URL="postgresql://postgres.YOUR_PROJECT:PASSWORD@aws-0-us-west-1.pooler.supabase.com:6543/postgres"

# Use production data (carefully!)
export MIX_ENV=dev
export PRODUCTION_DATA=true
mix phx.server

# Replay the exact request
curl -X POST http://localhost:4000/api/failing_endpoint \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer USER_TOKEN" \
  -d '{"exact": "params", "from": "error_tracking"}'
```

**Can't reproduce locally?**
- **Data-specific issue** → Continue to Step 6
- **Race condition** → Check Step 7  
- **Environment difference** → Compare all env vars:
  ```bash
  fly ssh console -C "env | sort" > prod_env.txt
  env | sort > local_env.txt
  diff local_env.txt prod_env.txt
  ```

### Step 6: Data-Specific Issues (10 minutes)

Connect to Supabase to investigate data:

```sql
-- Use Supabase SQL Editor (Dashboard > SQL Editor)
-- Find the problematic record from error logs

-- Example: User-related error
SELECT * FROM auth.users WHERE id = 'UUID_FROM_ERROR';
SELECT * FROM public.profiles WHERE user_id = 'UUID_FROM_ERROR';

-- Check for common data issues:
-- 1. NULLs in supposedly non-null fields
SELECT * FROM your_table WHERE important_field IS NULL;

-- 2. Orphaned records
SELECT * FROM child_table ct
LEFT JOIN parent_table pt ON ct.parent_id = pt.id
WHERE pt.id IS NULL;

-- 3. Duplicate records that should be unique
SELECT email, COUNT(*) 
FROM users 
GROUP BY email 
HAVING COUNT(*) > 1;

-- 4. Invalid JSON in JSONB columns
SELECT * FROM your_table 
WHERE jsonb_typeof(json_column) IS NULL;
```

**Quick data fixes:**
```sql
-- Add defensive defaults
UPDATE your_table 
SET field = COALESCE(field, 'default_value') 
WHERE field IS NULL;

-- Clean up orphaned records
DELETE FROM child_table 
WHERE parent_id NOT IN (SELECT id FROM parent_table);

-- Add constraint to prevent future issues
ALTER TABLE your_table 
ADD CONSTRAINT check_field_not_null CHECK (field IS NOT NULL);
```

### Step 7: Race Conditions & Timing Issues (15 minutes)

Identify concurrent request patterns:

```bash
# Find duplicate simultaneous requests
fly logs --since 30m | grep "user_id=PROBLEMATIC_USER_ID" | cut -d' ' -f1,2,8 | sort

# Look for rapid repeated calls
fly logs --since 10m | grep "POST /api/endpoint" | cut -d' ' -f1,2 | uniq -c | sort -rn
```

Check for lock contention in the application:

```elixir
fly ssh console
/app/bin/my_app remote

# Check ETS tables for unusual growth
:ets.all() |> Enum.map(fn table -> 
  {table, :ets.info(table, :size), :ets.info(table, :memory)}
end) |> Enum.sort_by(fn {_, _, mem} -> mem end, :desc)

# Check for backed up message queues
Process.list() 
|> Enum.map(fn pid -> 
  case Process.info(pid, [:message_queue_len, :registered_name]) do
    nil -> nil
    info -> {pid, info}
  end
end)
|> Enum.filter(& &1)
|> Enum.filter(fn {_, info} -> 
  Keyword.get(info, :message_queue_len, 0) > 100 
end)

# Check GenServer state for problematic ones
:sys.get_state(YourApp.ProblematicGenServer)
```

**Common race condition fixes:**
```elixir
# Use database constraints instead of application checks
# Bad:
if Repo.get_by(User, email: email), do: {:error, :exists}

# Good: Add unique constraint and handle error
create unique_index(:users, [:email])

# Use locks for critical sections
Repo.transaction(fn ->
  user = Repo.get!(User, id, lock: "FOR UPDATE")
  # Make changes
end)
```

### Step 8: Deploy the Fix

Choose deployment strategy based on severity:

#### Option A: Hot Fix (Critical - Users Impacted)
```bash
# Create minimal fix
git checkout -b hotfix/$(date +%Y%m%d)-error-description
# Make ONLY the necessary change
git add -p  # Add selectively
git commit -m "Hotfix: Handle nil case in user processor"

# Deploy immediately
fly deploy --strategy immediate  # Skip health checks
```

#### Option B: Rollback First, Then Fix
```bash
# View recent releases
fly releases

# Rollback to last known good
fly deploy --image registry.fly.io/my-app@sha256:LAST_GOOD_SHA

# Now fix properly without time pressure
git checkout main
git pull
git checkout -b fix/thorough-solution
```

#### Option C: Surgical Fix via Console (Emergency)
```elixir
# For immediate mitigation without deploy
fly ssh console
/app/bin/my_app remote

# Example: Disable problematic feature
Application.put_env(:my_app, :feature_flag, false)

# Example: Clear corrupted cache
MyApp.Cache.clear(:problematic_key)

# Example: Fix stuck job
Oban.cancel_job(job_id)
```

### Step 9: Verify Resolution

Confirm the fix is working:

```bash
# Monitor error rate (should drop to zero)
watch -n 5 'fly logs --since 1m | grep -c ERROR'

# Test the specific endpoint
for i in {1..20}; do
  curl -s -o /dev/null -w "%{http_code}\n" \
    https://your-app.fly.dev/problematic-endpoint
  sleep 0.5
done | sort | uniq -c
# Should see all 200s or expected status codes

# Check error tracking dashboard
# Honeybadger/AppSignal should show error resolved

# Verify from different regions (if multi-region)
fly logs --region ord --since 2m | grep ERROR
fly logs --region lax --since 2m | grep ERROR
```

### Step 10: Post-Mortem Documentation

Create incident report with:

```markdown
## Incident: [Brief Description]
**Date:** [YYYY-MM-DD HH:MM UTC]
**Duration:** [X minutes]
**Severity:** Critical|Major|Minor

### Impact
- Users affected: [number or percentage]
- Features impacted: [list]
- Data loss: Yes/No

### Timeline
- HH:MM - Error first occurred
- HH:MM - Alert received via [Honeybadger/AppSignal]
- HH:MM - Investigation started
- HH:MM - Root cause identified
- HH:MM - Fix deployed
- HH:MM - Resolution confirmed

### Root Cause
[Not just what broke, but WHY it broke]

### Resolution
[Exact fix applied]

### Lessons Learned
1. What went well
2. What could be improved
3. Action items to prevent recurrence

### Follow-up Tasks
- [ ] Add test for this case
- [ ] Update monitoring
- [ ] Document in runbook
```

## Quick Reference

### Emergency Commands

```bash
# Immediate rollback
fly deploy --image registry.fly.io/my-app@SHA

# Scale up urgently
fly scale count 5 --max-per-region 2

# Restart everything
fly apps restart

# Emergency console
fly ssh console --pty -C "/app/bin/my_app remote"

# Check recent changes
fly releases
git log --oneline -20 -- lib/

# View configuration
fly config show
fly secrets list
```

### Common Errors Quick Fixes

| Error | Check | Fix |
|-------|-------|-----|
| `Postgrex.Error` timeout | Supabase connection pool | Increase pool_size in runtime.exs |
| `DBConnection.ConnectionError` | `fly ssh console` → test DB connection | Check DATABASE_URL, SSL settings |
| `MatchError` with nil | Data integrity in Supabase | Add nil handling, fix data |
| `Phoenix.Router.NoRouteError` | Recent deploy changes | Check routes, rollback if needed |
| `TimeoutError` in query | Supabase Query Performance tab | Add index, optimize query |
| `Ecto.NoResultsError` | Record exists in DB? | Add existence check before get! |
| `Jason.DecodeError` | External API response | Add try/rescue for parsing |
| `FunctionClauseError` | Unexpected data shape | Add catch-all clause, log details |

### Supabase-Specific Debugging

```sql
-- Run in Supabase SQL Editor

-- Check connection pool usage
SELECT count(*) FROM pg_stat_activity;

-- Find slow queries
SELECT query, mean_exec_time, calls 
FROM pg_stat_statements 
ORDER BY mean_exec_time DESC 
LIMIT 10;

-- Check table sizes (for performance issues)
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Find lock contention
SELECT blocked_locks.pid AS blocked_pid,
       blocking_locks.pid AS blocking_pid,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
WHERE NOT blocked_locks.granted;
```

### Health Check Patterns

```elixir
# Add comprehensive health endpoint for debugging
defmodule MyAppWeb.HealthController do
  def detailed(conn, _params) do
    health = %{
      app: "ok",
      database: check_database(),
      memory_mb: :erlang.memory(:total) / 1_048_576,
      process_count: length(Process.list()),
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000),
      instance_id: System.get_env("FLY_ALLOC_ID"),
      region: System.get_env("FLY_REGION")
    }
    
    status = if health.database == "ok", do: 200, else: 503
    
    conn
    |> put_status(status)
    |> json(health)
  end
  
  defp check_database do
    case MyApp.Repo.query("SELECT 1") do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end
  rescue
    _ -> "error"
  end
end
```

## Prevention Checklist

After resolving an error, implement these preventive measures:

- [ ] Add test case covering the error scenario
- [ ] Add validation at the edge (changeset, controller, or LiveView)
- [ ] Add database constraint if data-related
- [ ] Add circuit breaker for external service failures
- [ ] Add rate limiting if load-related
- [ ] Add monitoring alert for early detection
- [ ] Document the issue in team knowledge base
- [ ] Consider adding retry logic with backoff
- [ ] Review similar code paths for the same issue

## Remember

1. **Don't panic** - Follow the steps systematically
2. **Communicate** - Update team/stakeholders about progress
3. **Document** - Write down what you're trying as you go
4. **Rollback first** - If users are impacted, rollback then debug
5. **One change at a time** - Don't deploy multiple fixes simultaneously
6. **Verify thoroughly** - Ensure the fix works before closing incident

This playbook is your systematic approach to resolving production errors. Follow the steps in order, using decision points to skip irrelevant sections. Most errors are resolved by Step 4 or 5.