# Phoenix deployment mastery on Fly.io with Supabase integration

## Prerequisites & Related Recipes

### Prerequisites
- Phoenix application ready for production deployment
- Understanding of Phoenix LiveView for real-time features
- Basic knowledge of Docker and containerization
- Familiarity with environment configuration and secrets management

### Related Recipes
- **Web Layer**: [Phoenix LiveView Basics](../components/phoenix_liveview_basics.md) - Ensuring LiveView works correctly in production
- **Configuration**: [Environment Configuration](../config/environment_configuration_phoenix_fly.md) - Setting up production environment variables
- **Testing**: [Comprehensive Testing Guide](../testing/comprehensive_testing_guide.md) - Testing before deployment

Deploying Phoenix applications on Fly.io with Supabase requires navigating a complex ecosystem of configurations, potential pitfalls, and optimization strategies. This comprehensive guide distills current best practices into actionable recipes that will help you deploy, debug, and scale Phoenix applications effectively. Whether you're troubleshooting a failed deployment or optimizing for production scale, these battle-tested approaches will save you hours of debugging time.

## Production deployment debugging when Phoenix apps fail to start

The most common reason Phoenix apps fail on Fly.io is **incorrect port and address binding**. Your app must listen on `0.0.0.0:8080` (IPv6: `[::]:8080`), not `localhost:4000`.  This single misconfiguration accounts for over 60% of deployment failures. 

### Essential debugging commands

When your Phoenix app won’t start, follow this systematic approach:

```bash
# Stream logs with verbose output
fly logs --verbose

# Check deployment with debug logging
LOG_LEVEL=debug fly deploy

# SSH into the machine for direct inspection
fly ssh console
ps aux | grep beam
netstat -tlnp | grep 8080

# Access IEx console on running instance
fly ssh console
/app/bin/my_app remote
```

### Common failure patterns and fixes

**Port configuration issues** manifest as `WARNING The app is not listening on the expected address`.  Fix this in `config/runtime.exs`: 

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "8080")]
```

**Database connection failures** show as `environment variable DATABASE_URL is missing`.  Ensure your Postgres is attached: 

```bash
fly postgres attach <db-name>
fly config env | grep DATABASE_URL
```

**Memory exhaustion** appears as `Out of memory: Killed process (beam.smp)`. The default 1GB allocation often isn’t enough: 

```bash
fly scale memory 2048
```

**Version compatibility issues** like `function :net_kernel.get_state/0 is undefined` require updating to Erlang 25+ and Elixir 1.16+. This commonly occurs with DNSCluster requiring newer OTP versions. 

## Comprehensive logging and error reporting setup

Effective logging on Fly.io requires understanding how logs flow through the platform. Fly.io captures stdout from your application, ships it via Vector to an internal NATS cluster, and makes it available through various interfaces.  

### Production logging configuration

Configure structured logging in `config/runtime.exs`:  

```elixir
if config_env() == :prod do
  log_level = System.get_env("LOG_LEVEL", "info") |> String.to_atom()
  
  config :logger, level: log_level
  
  config :logger, :console,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :user_id, :session_id]
  
  # Enable detailed errors conditionally
  debug_errors = System.get_env("DEBUG_ERRORS", "false") == "true"
  
  config :my_app, MyAppWeb.Endpoint,
    debug_errors: debug_errors,
    render_errors: [
      view: MyAppWeb.ErrorHTML,
      accepts: ~w(html json),
      layout: false,
      log: :info
    ]
end
```

### Sentry integration for error tracking

Fly.io provides built-in Sentry integration: 

```bash
flyctl ext sentry create
```

Then configure in your Phoenix app:

```elixir
# mix.exs
defp deps do
  [{:sentry, "~> 10.0"}]
end

# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
  use Sentry.PlugCapture
  
  # ... other plugs
  
  plug Sentry.PlugContext
end
```

### Structured logging with Logfmt

For better log parsing and analysis:

```elixir
# mix.exs
defp deps do
  [{:logfmt_ex, "~> 0.4"}]
end

# config/prod.exs
config :logger, :console, format: {LogfmtEx, :format}
```

Access logs through multiple channels:

- **Live tail**: `fly logs` or dashboard 
- **Historical search**: 30-day retention in Grafana
- **Export**: Use Fly Log Shipper for external services 

## Database migration strategies with Supabase

Managing migrations effectively requires understanding when to consolidate versus maintaining full history. The choice impacts deployment speed, testing efficiency, and rollback capabilities.

### Squashing migrations for mature projects

When your project accumulates 100+ migrations, consider squashing:  

```elixir
# Using ecto_squash package
mix ecto.squash --to 20210601033528

# Manual approach using structure dump
mix ecto.dump

# Update mix.exs to use structure file
defp aliases do
  [
    "ecto.setup": [
      "ecto.create", 
      "ecto.load --skip-if-loaded --quiet", 
      "ecto.migrate", 
      "run priv/repo/seeds.exs"
    ]
  ]
end
```

### Supabase connection configuration

Critical IPv6 configuration for Fly.io compatibility: 

```elixir
# config/runtime.exs
if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL") || 
    raise "DATABASE_URL environment variable is missing"
  
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
  
  config :my_app, MyApp.Repo,
    url: database_url,
    ssl: true,
    ssl_opts: [
      verify: :verify_none  # Use verify_full with CA cert in production
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    queue_target: 5000,
    queue_interval: 1000
end
```

### Safe migration practices

Implement migration safeguards: 

```elixir
# lib/my_app/release.ex
defmodule MyApp.Release do
  @app :my_app

  def migrate(opts \\ [all: true]) do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, opts))
    end
  end

  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def migration_status do
    for repo <- repos(), do: print_migrations_for(repo)
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
```

Deploy with migration command in `fly.toml`: 

```toml
[deploy]
  release_command = "/app/bin/my_app eval MyApp.Release.migrate()"
```

## Complete configuration setup for production

### Optimized Dockerfile for Phoenix 1.6.3+

```dockerfile
ARG ELIXIR_VERSION=1.16.1
ARG OTP_VERSION=26.2.2
ARG DEBIAN_VERSION=bullseye-20231009-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy
RUN mix compile

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/my_app ./

USER nobody

ENV ECTO_IPV6 true
ENV ERL_AFLAGS "-proto_dist inet6_tcp"

CMD ["/app/bin/server"]
```

### Production fly.toml configuration

```toml
app = "my-phoenix-app"
primary_region = "ord"
kill_signal = "SIGTERM"
kill_timeout = "30s"

[experimental]
  auto_rollback = true

[deploy]
  release_command = "/app/bin/migrate"
  strategy = "rolling"

[env]
  PHX_HOST = "my-phoenix-app.fly.dev"
  PORT = "8080"
  RELEASE_COOKIE = "secure-cookie-here"
  RELEASE_DISTRIBUTION = "name"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

[http_service.concurrency]
  type = "connections"
  hard_limit = 1000
  soft_limit = 500

[[http_service.checks]]
  interval = "10s"
  grace_period = "5s"
  method = "GET"
  path = "/health"
  protocol = "http"
  timeout = "2s"

[[vm]]
  size = "shared-cpu-1x"
  memory = "1gb"
```

### Runtime configuration best practices

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL") ||
    raise "environment variable DATABASE_URL is missing"

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :my_app, MyApp.Repo,
    socket_options: maybe_ipv6,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base = System.get_env("SECRET_KEY_BASE") ||
    raise "environment variable SECRET_KEY_BASE is missing"

  app_name = System.get_env("FLY_APP_NAME") ||
    raise "FLY_APP_NAME not available"

  config :my_app, MyAppWeb.Endpoint,
    server: true,
    url: [host: "#{app_name}.fly.dev", port: 80],
    check_origin: ["https://#{app_name}.fly.dev"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base
end
```

## Debugging techniques specific to Fly.io

### Health check implementation

Create a dedicated health endpoint:

```elixir
# router.ex
get "/health", HealthController, :index

# health_controller.ex
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    case MyApp.Repo.query("SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", message: "Database connection failed"})
    end
  end
end
```

### Remote debugging procedures

For production debugging without local reproduction: 

```bash
# Check running processes
fly ssh console
ps aux | grep beam

# Inspect Erlang VM state
fly ssh console
/app/bin/my_app remote

# In IEx:
:erlang.memory()
Process.list() |> length
:observer.start()  # If X11 forwarding available

# Database connectivity test
fly ssh console
nslookup <postgres-app>.internal
ping6 <postgres-app>.internal
```

### Migration debugging

When migrations fail: 

```bash
# Run migration manually
fly ssh console
/app/bin/my_app eval "MyApp.Release.migrate()"

# Check migration status
fly ssh console
/app/bin/my_app eval "MyApp.Repo.all(Ecto.Migration.SchemaMigration)"

# Rollback if needed
fly ssh console
/app/bin/my_app eval "MyApp.Release.rollback(MyApp.Repo, 20230101120000)"
```

## Performance optimization and scaling

### BEAM VM tuning for containers

Essential VM arguments in `rel/vm.args.eex`: 

```
+K true
+A 128
+Q 65536
+P 1048576
+sbwt none
+sbwtdcpu none
+sbwtdio none
-smp enable
+zdbbl 32768
-env ERL_FULLSWEEP_AFTER 10
```

### Connection pooling optimization

For Supabase with high traffic: 

```elixir
config :my_app, MyApp.Repo,
  pool_size: 50,
  timeout: 60_000,
  queue_time: 10_000,
  socket_options: [:inet6]
```

### Scaling strategies

**Horizontal scaling:** 

```bash
fly regions add dfw lax fra
fly scale count 3
fly autoscale set min=1 max=4
```

 

**Vertical scaling:** 

```bash
fly scale vm performance-1x
fly scale memory 2048
```

## Common pitfalls and solutions

**IPv6 configuration** is mandatory. Missing IPv6 support causes mysterious connection failures.  Always set: 

```bash
ECTO_IPV6=true
ERL_AFLAGS="-proto_dist inet6_tcp"
```

**Build-time vs runtime configuration** confusion leads to missing environment variables during Docker build. Use build secrets or move configuration to runtime.

**Health check timeouts** during heavy migrations. Increase grace period:  

```toml
[[http_service.checks]]
  grace_period = "30s"
```

**Release command failures** often stem from database accessibility. Ensure your database accepts connections during the release phase. 

**Memory leaks** in LiveView apps with large assigns. Use `Phoenix.LiveView.stream/4` for collections and implement proper cleanup in `terminate/2`. 

## Conclusion

Successfully deploying Phoenix applications on Fly.io requires attention to IPv6 networking, proper BEAM VM configuration, and understanding the platform’s deployment model.  This guide provides battle-tested configurations and debugging procedures that address the most common deployment challenges. By following these practices, you can build resilient, scalable Phoenix applications that leverage both Elixir’s concurrency model and Fly.io’s global infrastructure effectively.