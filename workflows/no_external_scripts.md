# No External Scripts Recipe

## Core Principle

**Never write standalone scripts or command-line utilities. Always implement functionality as tested, reusable modules within the codebase.**

## Why This Matters

1. **Testability**: Code in the codebase can be unit tested, integration tested, and continuously verified
2. **Reusability**: Functions can be called from multiple contexts (web UI, API, console, background jobs)
3. **Maintainability**: Code is versioned, documented, and evolves with the application
4. **Production Access**: Mix tasks aren't available in releases, but modules are always accessible
5. **Type Safety**: Dialyzer and compile-time checks catch errors early
6. **Observability**: Application code benefits from logging, telemetry, and error tracking

## Why Mix Tasks Don't Work in Production

**Mix is a build tool, not a runtime tool.** When you deploy an Elixir application to staging or production (especially on platforms like Fly.io), you deploy a **release** - a self-contained package that includes:
- The Erlang runtime (ERTS)
- Your compiled application code
- Required dependencies

**What's NOT included in releases:**
- Mix itself
- Source code (.ex files)
- Development dependencies
- Mix tasks

This means `mix leadpoise.score_personas` will work on your development machine but will fail with "command not found" in production. The ONLY way to run code in production is through:
- The running application's modules
- IEx remote console (`/app/bin/leadpoise remote`)
- Web interfaces you've built
- API endpoints you've exposed
- Scheduled Oban jobs

## Anti-Pattern Examples

### ❌ BAD: Bash Scripts
```bash
#!/bin/bash
# scripts/cleanup_old_records.sh

# Problems:
# - Can't be tested with ExUnit
# - Not version controlled with deployments
# - No access to application context or configs
# - Bypasses Ecto changesets and validations
# - No telemetry, logging, or error tracking
# - Requires database credentials in environment
# - Won't work in Docker/release containers

psql $DATABASE_URL -c "DELETE FROM contacts WHERE created_at < NOW() - INTERVAL '90 days'"
echo "Cleaned up old records"
```

### ❌ BAD: External Elixir Script
```bash
# scripts/update_persona_scores.exs
Mix.install([:ecto, :postgrex])

defmodule UpdatePersonaScores do
  def run do
    # Direct database manipulation
    # No tests, no reusability
    # Not available in production
    # Requires Mix (build tool) at runtime
  end
end

UpdatePersonaScores.run()
```

### ❌ BAD: Mix Task as Primary Implementation
```elixir
# lib/mix/tasks/process_data.ex
defmodule Mix.Tasks.ProcessData do
  def run(_args) do
    # All logic lives here
    # Can't be called from web UI
    # Not available in production
  end
end
```

## Correct Pattern Examples

### ✅ GOOD: Core Module + Multiple Interfaces

```elixir
# lib/leadpoise/persona_scorer.ex
defmodule Leadpoise.PersonaScorer do
  @moduledoc """
  Core persona scoring functionality.
  Can be called from anywhere in the application.
  """
  
  @doc """
  Scores all personas or a specific subset.
  
  ## Options
    * `:limit` - Maximum number to process
    * `:dry_run` - Preview without saving
    * `:rescore_all` - Rescore even if already scored
  
  ## Examples
      
      # From IEx console
      iex> Leadpoise.PersonaScorer.score_all(limit: 100)
      {:ok, %{scored: 100, errors: 0}}
      
      # From LiveView
      def handle_event("score_personas", _params, socket) do
        Task.start(fn -> 
          Leadpoise.PersonaScorer.score_all()
        end)
        {:noreply, socket}
      end
      
      # From API endpoint
      def score(conn, params) do
        case Leadpoise.PersonaScorer.score_all(params) do
          {:ok, result} -> json(conn, result)
          {:error, reason} -> json(conn, %{error: reason})
        end
      end
  """
  def score_all(opts \\ []) do
    # Implementation
  end
  
  def score_single(contact_id) do
    # Implementation  
  end
  
  def get_scoring_stats do
    # Implementation
  end
end
```

### ✅ GOOD: Mix Task as Thin Wrapper

```elixir
# lib/mix/tasks/leadpoise.score_personas.ex
defmodule Mix.Tasks.Leadpoise.ScorePersonas do
  @moduledoc """
  Convenience wrapper for development.
  Delegates to core module.
  """
  use Mix.Task
  
  def run(args) do
    Mix.Task.run("app.start")
    
    {opts, _} = OptionParser.parse!(args,
      strict: [limit: :integer, dry_run: :boolean]
    )
    
    # Just parse CLI args and delegate to core module
    case Leadpoise.PersonaScorer.score_all(opts) do
      {:ok, result} -> 
        IO.puts("Success: #{inspect(result)}")
      {:error, reason} -> 
        IO.puts("Error: #{reason}")
        exit(1)
    end
  end
end
```

### ✅ GOOD: Web Interface for Production

```elixir
# lib/leadpoise_web/live/admin/persona_scoring_live.ex
defmodule LeadpoiseWeb.Admin.PersonaScoringLive do
  use LeadpoiseWeb, :live_view
  
  def mount(_params, _session, socket) do
    stats = Leadpoise.PersonaScorer.get_scoring_stats()
    {:ok, assign(socket, stats: stats, running: false)}
  end
  
  def handle_event("start_scoring", params, socket) do
    Task.start(fn ->
      Leadpoise.PersonaScorer.score_all(params)
      send(self(), :scoring_complete)
    end)
    
    {:noreply, assign(socket, running: true)}
  end
  
  def handle_info(:scoring_complete, socket) do
    stats = Leadpoise.PersonaScorer.get_scoring_stats()
    {:noreply, assign(socket, stats: stats, running: false)}
  end
end
```

### ✅ GOOD: Oban Job for Background Processing

```elixir
# lib/leadpoise/workers/persona_scoring_worker.ex
defmodule Leadpoise.Workers.PersonaScoringWorker do
  use Oban.Worker, queue: :scoring
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Delegate to core module
    case Leadpoise.PersonaScorer.score_all(args) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

# Schedule from anywhere:
# %{limit: 100}
# |> Leadpoise.Workers.PersonaScoringWorker.new()
# |> Oban.insert()
```

## Implementation Checklist

When implementing new functionality:

- [ ] Create core module in `lib/leadpoise/` with pure business logic
- [ ] Write comprehensive tests in `test/leadpoise/`
- [ ] Add @moduledoc and @doc with examples
- [ ] Include typespecs for all public functions
- [ ] Create web interface if user-facing (LiveView or controller)
- [ ] Add Oban worker if background processing needed
- [ ] Create Mix task ONLY as convenience wrapper for development
- [ ] Document all interfaces in module documentation

## Production Access Patterns

### Via IEx Console (Fly.io)
```bash
fly ssh console
/app/bin/leadpoise remote

# Now you can call any module function
Leadpoise.PersonaScorer.score_all(limit: 10, dry_run: true)
Leadpoise.PipelineReprocessor.reprocess(stage: :parse)
```

### Via Web Admin Interface
- Build LiveView or Phoenix controller
- Add to admin routes with authentication
- Provides UI for non-technical users
- Can show real-time progress

### Via API Endpoint
```elixir
# routes.ex
scope "/api/admin" do
  pipe_through [:api, :require_admin]
  
  post "/score-personas", AdminApiController, :score_personas
end

# controller
def score_personas(conn, params) do
  case Leadpoise.PersonaScorer.score_all(params) do
    {:ok, result} -> json(conn, result)
    {:error, reason} -> 
      conn
      |> put_status(422)
      |> json(%{error: reason})
  end
end
```

### Via Scheduled Jobs
```elixir
# config/config.exs
config :leadpoise, Oban,
  crontab: [
    {"0 2 * * *", Leadpoise.Workers.PersonaScoringWorker}
  ]
```

## Testing Strategy

### Core Module Tests
```elixir
# test/leadpoise/persona_scorer_test.exs
defmodule Leadpoise.PersonaScorerTest do
  use Leadpoise.DataCase
  
  describe "score_all/1" do
    test "scores unscored personas" do
      # Setup
      contact = insert(:contact, type: :person, persona_score: nil)
      
      # Execute
      assert {:ok, result} = PersonaScorer.score_all()
      
      # Verify
      assert result.scored == 1
      updated = Repo.get!(Contact, contact.id)
      assert updated.persona_score > 0
    end
    
    test "respects limit option" do
      insert_list(10, :contact, type: :person)
      
      assert {:ok, result} = PersonaScorer.score_all(limit: 5)
      assert result.scored == 5
    end
    
    test "dry run doesn't persist changes" do
      contact = insert(:contact, type: :person)
      
      assert {:ok, _} = PersonaScorer.score_all(dry_run: true)
      
      unchanged = Repo.get!(Contact, contact.id)
      assert unchanged.persona_score == contact.persona_score
    end
  end
end
```

### Integration Tests
```elixir
# test/leadpoise_web/live/admin/persona_scoring_live_test.exs
defmodule LeadpoiseWeb.Admin.PersonaScoringLiveTest do
  use LeadpoiseWeb.ConnCase
  import Phoenix.LiveViewTest
  
  test "allows admin to trigger scoring", %{conn: conn} do
    admin = insert(:user, role: :admin)
    conn = log_in_user(conn, admin)
    
    {:ok, view, _html} = live(conn, "/admin/persona-scoring")
    
    assert view
           |> element("button", "Start Scoring")
           |> render_click()
    
    assert has_element?(view, ".alert-info", "Scoring in progress")
  end
end
```

## Common Pitfalls to Avoid

1. **Don't put business logic in Mix tasks** - They literally don't exist in production releases
2. **Don't write bash scripts for data operations** - They bypass your entire application layer
3. **Don't write one-off scripts** - Today's one-off is tomorrow's critical process
4. **Don't skip tests** - If it's worth writing, it's worth testing
5. **Don't access the database directly** - Use Ecto schemas and changesets
6. **Don't forget error handling** - Return `{:ok, result}` or `{:error, reason}`
7. **Don't block the web process** - Use Task, GenServer, or Oban for long operations
8. **Don't assume Mix is available** - In staging/production, there is no `mix` command
9. **Don't use external scripts for "quick fixes"** - They become permanent and unmaintainable

## Migration Path for Existing Scripts

If you have existing scripts, migrate them:

1. Extract core logic to a module under `lib/leadpoise/`
2. Add proper function signatures with opts
3. Write tests for the extracted module
4. Replace script with Mix task that delegates to module
5. Add web interface or API endpoint as needed
6. Schedule via Oban if periodic execution needed
7. Delete the original script

## Real-World Example: Persona Scoring

Instead of a script like `scripts/update_scores.exs`, we implemented:

1. `Leadpoise.Scoring.PersonaICP` - Core scoring logic
2. `Leadpoise.Workers.ScoringWorker` - Oban job for async processing  
3. `Mix.Tasks.Leadpoise.ScorePersonas` - Dev convenience
4. `LeadpoiseWeb.Admin.PeopleScoresController` - Web UI for monitoring
5. Tests for all of the above

This approach provides:
- Automatic scoring via pipeline
- Manual scoring via web UI
- Bulk scoring via Mix task (dev)
- API access for integrations
- Full test coverage
- Production accessibility

## Summary

**Every piece of functionality should be a first-class citizen in your codebase.** No orphaned scripts, no untested utilities, no production-inaccessible tools. Write it once, write it well, and make it accessible from everywhere it's needed.

Remember: If it's not in the codebase, it doesn't exist. If it's not tested, it's broken. If it's not reusable, it's technical debt.