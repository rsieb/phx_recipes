# Configuration Management in Phoenix

## Configuration Files

| File | When it runs | What goes here |
|------|--------------|----------------|
| `config/config.exs` | Compile time | Shared defaults, repo config, generators |
| `config/dev.exs` | Compile time | Local dev settings (hardcoded DB, watchers) |
| `config/test.exs` | Compile time | Test settings (sandbox pool, disabled services) |
| `config/prod.exs` | Compile time | Build-time production flags only |
| `config/runtime.exs` | App startup | **All dynamic config** — env vars, secrets |

**Key rule:** If the value changes between environments or contains secrets, it goes in `runtime.exs`.

## Basic Structure

```elixir
# config/config.exs - shared compile-time defaults
import Config

config :my_app,
  ecto_repos: [MyApp.Repo],
  generators: [binary_id: false]

config :my_app, MyAppWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON]],
  pubsub_server: MyApp.PubSub,
  live_view: [signing_salt: "YOUR_SIGNING_SALT"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs - local development
import Config

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-at-least-64-chars-long-for-dev",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:my_app, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:my_app, ~w(--watch)]}
  ]

config :my_app, dev_routes: true
config :logger, level: :debug
```

```elixir
# config/test.exs
import Config

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-at-least-64-chars-long-for-test",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

# Disable external services in tests
config :my_app, :external_api, mock: true
```

```elixir
# config/prod.exs - minimal, build-time only
import Config

config :my_app, MyAppWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info

# Everything else goes in runtime.exs
```

```elixir
# config/runtime.exs - all dynamic configuration
import Config

# Load .env files in dev/test (see environment_variables_secrets.md)
if config_env() in [:dev, :test] do
  Dotenvy.source([".env", ".env.#{config_env()}"])
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is missing"

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is missing"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end

# Configuration that applies to all environments
if api_key = System.get_env("STRIPE_API_KEY") do
  config :my_app, :stripe, api_key: api_key
end
```

## Accessing Configuration

```elixir
# In application code - always read from Application config
stripe_key = Application.get_env(:my_app, :stripe)[:api_key]

# Or use fetch for required values
{:ok, stripe_config} = Application.fetch_env(:my_app, :stripe)
```

**Never call `System.get_env/1` in application code** — always go through the config system. This makes testing easier and keeps configuration centralized.

## Required vs Optional Values

```elixir
# Required - fail fast if missing
database_url =
  System.get_env("DATABASE_URL") ||
    raise "DATABASE_URL is missing"

# Optional with default
pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

# Optional, nil if not set
sentry_dsn = System.get_env("SENTRY_DSN")
if sentry_dsn do
  config :sentry, dsn: sentry_dsn
end
```

## Feature Flags

```elixir
# config/runtime.exs
config :my_app, :features,
  new_ui: System.get_env("FEATURE_NEW_UI") == "true",
  beta_api: System.get_env("FEATURE_BETA_API") == "true"

# In code
if Application.get_env(:my_app, :features)[:new_ui] do
  # new UI code
end
```

## Anti-patterns

| Don't | Do instead |
|-------|------------|
| `System.get_env` in application code | `Application.get_env` |
| `System.get_env` in `config.exs` | Put in `runtime.exs` |
| Secrets in `dev.exs`/`prod.exs` | Put in `runtime.exs` reading from env |
| `Mix.env()` in application code | Config-based feature flags |
| Different config structure per env | Same keys, different values |
