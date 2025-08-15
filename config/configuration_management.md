# Configuration Management in Phoenix

## Introduction

Comprehensive configuration and secrets management are crucial for Phoenix applications. This guide covers structuring configuration files, managing environment-specific settings, handling secrets securely, and following best practices across development, staging, and production environments.

## 1. Phoenix Configuration Architecture

### Core Configuration Files

| File                  | Purpose                                                                 |
|-----------------------|-------------------------------------------------------------------------|
| `config/config.exs`   | Compile-time shared defaults. Avoid runtime values here.                |
| `config/dev.exs`      | Developer machine config (local-only). Static configuration.            |
| `config/test.exs`     | For CI and local testing. Hardcode safely.                              |
| `config/prod.exs`     | Minimal build-time production config. Use sparingly.                    |
| `config/runtime.exs`  | Primary config for staging/prod. All dynamic config goes here.          |

### Basic Configuration Structure

```elixir
# config/config.exs - Common configuration
import Config

config :my_app,
  ecto_repos: [MyApp.Repo],
  generators: [binary_id: true]

config :my_app, MyApp.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Configure Phoenix endpoint
config :my_app, MyAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MyApp.PubSub,
  live_view: [signing_salt: "YOUR_SIGNING_SALT"]

# Configure logging
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure Phoenix generators
config :phoenix, :json_library, Jason

# Import environment specific config
import_config "#{config_env()}.exs"
```

### Runtime Configuration (The Key File)

```elixir
# config/runtime.exs - Runtime configuration for production/staging
import Config

if config_env() in [:prod, :staging] do
  # Configure the database
  database_url = System.get_env("DATABASE_URL") ||
    raise """
    environment variable DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    """

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: System.get_env("DB_SSL") == "true",
    timeout: String.to_integer(System.get_env("DB_TIMEOUT") || "15000")

  # Configure the endpoint
  secret_key_base = System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

  config :my_app, MyAppWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"],
    secret_key_base: secret_key_base,
    server: true

  # Configure external services
  if System.get_env("REDIS_URL") do
    config :my_app, :redis,
      url: System.get_env("REDIS_URL"),
      pool_size: String.to_integer(System.get_env("REDIS_POOL_SIZE") || "10")
  end

  # Configure monitoring
  if System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: System.get_env("SENTRY_DSN"),
      environment_name: System.get_env("SENTRY_ENVIRONMENT") || config_env()
  end

  # Configure feature flags
  config :my_app, :feature_flags,
    new_ui: System.get_env("FEATURE_NEW_UI") == "true",
    analytics: System.get_env("FEATURE_ANALYTICS") == "true",
    rate_limiting: System.get_env("FEATURE_RATE_LIMITING") == "true"
end
```

## 2. Environment-Specific Configuration

### Development Configuration

```elixir
# config/dev.exs - Development configuration
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
  secret_key_base: "YOUR_DEV_SECRET_KEY_BASE",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Enable dev routes for dashboard and mailbox
config :my_app, dev_routes: true

# Configure mailer for development
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Local

# Set log level
config :logger, level: :debug

# Feature flags for development
config :my_app, :external_api_enabled, false
config :my_app, :enable_debug_logging, true
```

### Test Configuration

```elixir
# config/test.exs - Test configuration
import Config

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YOUR_TEST_SECRET_KEY_BASE",
  server: false

# Configure mailer for testing
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Test

# Disable logging in tests
config :logger, level: :warning

# Configure background job testing
config :my_app, Oban,
  testing: :inline

# Configure external services for testing
config :my_app, :external_api,
  base_url: "https://api.example.com",
  timeout: 5000,
  mock: true

config :my_app, :external_api_enabled, false
```

### Production Configuration

```elixir
# config/prod.exs - Minimal production configuration
import Config

# Production feature flags (build-time)
config :my_app, :external_api_enabled, true
config :my_app, :enable_debug_logging, false

# Configure mailer for production (can be overridden in runtime.exs)
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Mailgun

# Configure background jobs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    default: 10,
    high_priority: 5,
    low_priority: 2
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", MyApp.Workers.DailyCleanup},
      {"*/15 * * * *", MyApp.Workers.HealthCheck}
    ]}
  ]

# Reduce log level in production
config :logger, level: :info
```

### Setting Up Staging Environment

1. **Create staging environment on hosting platform**
2. **Set environment variables:**
   ```env
   MIX_ENV=staging
   DATABASE_URL=your-staging-db-url
   SECRET_KEY_BASE=generated-staging-secret
   PHX_HOST=staging.myapp.com
   POOL_SIZE=10
   ```
3. **Deploy with proper staging configuration**
4. **Ensure migrations run during deploys:**
   ```bash
   bin/my_app eval "MyApp.Release.migrate"
   ```

## 3. Secrets Management

### Core Principle: Everything Dynamic Goes in ENV Variables

Use environment variables for all secrets and environment-specific values:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `POOL_SIZE`
- `REDIS_URL`
- `SENTRY_DSN`

### Development Secrets Management

Use `.env` files with `direnv` or `dotenv`:

```env
# .env (never commit this file)
DATABASE_URL=postgresql://localhost/my_app_dev
SECRET_KEY_BASE=generated_secret_key
PHX_HOST=localhost
POOL_SIZE=10
REDIS_URL=redis://localhost:6379/0
SENTRY_DSN=https://key@sentry.io/project
```

### Production Secrets Management

```elixir
defmodule MyApp.Secrets do
  @moduledoc """
  Secure secrets management for the application.
  """

  @doc """
  Retrieves a secret from the configured secret store.
  """
  def get_secret(key) do
    case secret_store() do
      :env -> System.get_env(key)
      :aws_secrets_manager -> fetch_from_aws_secrets_manager(key)
      :vault -> fetch_from_vault(key)
      :file -> fetch_from_file(key)
    end
  end

  @doc """
  Retrieves a required secret, raising if not found.
  """
  def get_secret!(key) do
    case get_secret(key) do
      nil -> raise "Secret #{key} is required but not found"
      value -> value
    end
  end

  # Private functions for different secret stores
  defp secret_store do
    Application.get_env(:my_app, :secret_store, :env)
  end

  defp fetch_from_aws_secrets_manager(key) do
    case ExAws.SecretsManager.get_secret_value(key) |> ExAws.request() do
      {:ok, %{"SecretString" => secret}} -> Jason.decode!(secret)
      {:error, _} -> nil
    end
  end

  defp fetch_from_vault(key) do
    vault_path = Application.get_env(:my_app, :vault_path, "secret/")
    
    case Vault.read("#{vault_path}#{key}") do
      {:ok, %{"data" => data}} -> data["value"]
      {:error, _} -> nil
    end
  end

  defp fetch_from_file(key) do
    secrets_dir = Application.get_env(:my_app, :secrets_dir, "/run/secrets/")
    file_path = Path.join(secrets_dir, key)
    
    case File.read(file_path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end
end
```

## 4. Database Configuration

### Development Database

```elixir
# config/dev.exs
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

### Test Database

```elixir
# config/test.exs
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
```

### Production Database (in runtime.exs)

```elixir
# config/runtime.exs
if config_env() in [:prod, :staging] do
  config :my_app, MyApp.Repo,
    url: System.get_env("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [
      verify: :verify_peer,
      cacertfile: System.get_env("SSL_CERT_FILE"),
      server_name_indication: String.to_charlist(System.get_env("DB_HOSTNAME")),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
end
```

## 5. Production Configuration (Fly.io Specific)

### Standard Fly.io Setup

```toml
# fly.toml (generated by `fly launch`)
app = "my-app"
primary_region = "sjc"

[build]

[http_service]
  internal_port = 4000
  force_https = true

[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 256

[env]
  PHX_HOST = "my-app.fly.dev"
```

### Fly.io Environment Variables

Set secrets using Fly.io CLI:

```bash
# Set database URL
fly secrets set DATABASE_URL="postgresql://..."

# Set secret key base
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Set other environment variables
fly secrets set POOL_SIZE=10
fly secrets set REDIS_URL="redis://..."
```

### Release Tasks

```elixir
defmodule MyApp.Release do
  @app :my_app

  def migrate do
    Application.load(@app)
    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
```

Run migrations on deployment:
```bash
bin/my_app eval "MyApp.Release.migrate"
```

## 6. Configuration Validation and Testing

### Configuration Validation Module

```elixir
defmodule MyApp.ConfigValidator do
  @moduledoc """
  Validates application configuration at startup.
  """

  @required_env_vars [
    "DATABASE_URL",
    "SECRET_KEY_BASE"
  ]

  @required_config_keys [
    {MyApp.Repo, :url},
    {MyAppWeb.Endpoint, :secret_key_base}
  ]

  def validate! do
    validate_environment_variables!()
    validate_configuration_keys!()
    validate_database_connection!()
    validate_external_services!()
    
    :ok
  end

  defp validate_environment_variables! do
    missing_vars = 
      @required_env_vars
      |> Enum.filter(fn var -> System.get_env(var) == nil end)
    
    unless Enum.empty?(missing_vars) do
      raise """
      Missing required environment variables:
      #{Enum.join(missing_vars, "\n")}
      """
    end
  end

  defp validate_configuration_keys! do
    missing_configs = 
      @required_config_keys
      |> Enum.filter(fn {app, key} -> 
        Application.get_env(app, key) == nil
      end)
    
    unless Enum.empty?(missing_configs) do
      formatted_configs = 
        missing_configs
        |> Enum.map(fn {app, key} -> "#{app}.#{key}" end)
        |> Enum.join("\n")
      
      raise """
      Missing required configuration keys:
      #{formatted_configs}
      """
    end
  end

  defp validate_database_connection! do
    case MyApp.Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      {:error, reason} -> 
        raise "Database connection failed: #{inspect(reason)}"
    end
  end

  defp validate_external_services! do
    # Validate external API configuration
    api_config = Application.get_env(:my_app, :external_api)
    
    unless api_config[:base_url] do
      raise "External API base_url is required"
    end
    
    # Validate Redis if configured
    if Application.get_env(:my_app, :redis) do
      validate_redis_connection!()
    end
  end

  defp validate_redis_connection! do
    case Redix.command(:redix, ["PING"]) do
      {:ok, "PONG"} -> :ok
      {:error, reason} -> 
        raise "Redis connection failed: #{inspect(reason)}"
    end
  end
end
```

### Configuration Helper Module

```elixir
defmodule MyApp.Config do
  @moduledoc """
  Configuration helper module for accessing application settings.
  """

  @doc """
  Gets a configuration value with a default.
  """
  def get(key, default \\ nil) do
    Application.get_env(:my_app, key, default)
  end

  @doc """
  Gets a required configuration value, raising if not found.
  """
  def get!(key) do
    case Application.get_env(:my_app, key) do
      nil -> raise "Configuration key #{inspect(key)} is required but not set"
      value -> value
    end
  end

  @doc """
  Checks if a feature is enabled.
  """
  def feature_enabled?(feature) do
    get(:feature_flags, %{})
    |> Map.get(feature, false)
  end

  @doc """
  Gets environment name.
  """
  def environment do
    Application.get_env(:my_app, :environment) || config_env()
  end

  @doc """
  Checks if running in production.
  """
  def production? do
    config_env() == :prod
  end

  @doc """
  Checks if running in development.
  """
  def development? do
    config_env() == :dev
  end

  @doc """
  Checks if running in test.
  """
  def test? do
    config_env() == :test
  end

  defp config_env do
    Application.get_env(:my_app, :config_env) || :dev
  end
end
```

## 7. Common Configuration Patterns and Anti-patterns

### ✅ Best Practices

1. **Use `System.fetch_env!/1` for required environment variables** - fails fast if missing
2. **Keep `config/runtime.exs` for all dynamic configuration** - works across all environments
3. **Use build-time config for static values only** - avoid `System.get_env` in compile-time config
4. **Validate configuration at startup** - catch errors early
5. **Document all environment variables** - maintain clear documentation
6. **Use feature flags for conditional behavior** - easier to manage than environment checks
7. **Separate secrets from configuration** - use proper secret management

### ❌ Anti-patterns

1. **Don't check `Mix.env` directly in application code** - use config system instead
2. **Don't put secrets in compile-time config** - they get baked into releases
3. **Don't use `System.get_env` in `config/config.exs`** - not available at compile time
4. **Don't hardcode environment-specific values** - use environment variables
5. **Don't commit `.env` files** - they contain secrets
6. **Don't use different config structure per environment** - maintain consistency
7. **Don't skip configuration validation** - catch errors before production

### Recommended Patterns

#### Environment-based Feature Flags
```elixir
# config/runtime.exs
config :my_app, :feature_flags,
  new_ui: System.get_env("FEATURE_NEW_UI") == "true",
  analytics: System.get_env("FEATURE_ANALYTICS") == "true"

# In application code
if MyApp.Config.feature_enabled?(:new_ui) do
  render_new_ui()
else
  render_legacy_ui()
end
```

#### Configuration with Defaults
```elixir
# config/runtime.exs
config :my_app, :external_api,
  base_url: System.get_env("EXTERNAL_API_URL") || "https://api.example.com",
  timeout: String.to_integer(System.get_env("EXTERNAL_API_TIMEOUT") || "30000"),
  retries: String.to_integer(System.get_env("EXTERNAL_API_RETRIES") || "3")
```

#### Environment Variable Documentation
```elixir
defmodule MyApp.Config.EnvDocs do
  @moduledoc """
  Documentation for environment variables used by the application.
  """

  @env_vars [
    %{
      name: "DATABASE_URL",
      description: "PostgreSQL connection string",
      required: true,
      example: "postgresql://user:password@localhost/myapp_prod"
    },
    %{
      name: "SECRET_KEY_BASE",
      description: "Secret key for Phoenix sessions and cookies",
      required: true,
      example: "generated_by_mix_phx_gen_secret"
    },
    %{
      name: "PORT",
      description: "HTTP server port",
      required: false,
      default: "4000",
      example: "4000"
    }
  ]

  def list_env_vars, do: @env_vars

  def generate_env_template do
    @env_vars
    |> Enum.map(fn var ->
      comment = if var.required, do: "# Required", else: "# Optional"
      default = if var[:default], do: " (default: #{var.default})", else: ""
      example = if var[:example], do: var.example, else: ""
      
      """
      #{comment}#{default}
      # #{var.description}
      #{var.name}=#{example}
      """
    end)
    |> Enum.join("\n")
  end
end
```

## Summary Checklist

### Configuration Architecture
- ✅ All dynamic values in `runtime.exs`
- ✅ All secrets from ENV vars
- ✅ Dev uses static config only
- ✅ Use `System.fetch_env!/1` to fail fast on missing config
- ✅ Use staging as a first-class environment

### Security
- ✅ Never commit secrets to version control
- ✅ Use proper secret management systems in production
- ✅ Rotate secrets regularly
- ✅ Use different secrets for different environments

### Validation
- ✅ Validate configuration at application startup
- ✅ Provide clear error messages for missing configuration
- ✅ Document all environment variables
- ✅ Use default values where appropriate

### Tooling
- ✅ Use `direnv` or `dotenv` to manage `.env` files
- ✅ Use configuration helper modules for accessing settings
- ✅ Implement proper configuration validation
- ✅ Use feature flags for conditional behavior

This configuration management approach provides a solid foundation for Phoenix applications across all environments while maintaining security, clarity, and consistency.