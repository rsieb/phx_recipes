# Configuration and Secrets Recipe

## Introduction

Proper configuration and secret management are crucial for Phoenix applications. This recipe covers how to structure configuration files, manage environment-specific settings, handle secrets securely, and follow best practices for configuration management across different deployment environments.

## Basic Phoenix Configuration Structure

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

# Configure Swoosh for emails
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Local

# Configure logging
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure Phoenix generators
config :phoenix, :json_library, Jason

# Import environment specific config
import_config "#{config_env()}.exs"
```

## Environment-Specific Configuration

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
```

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
```

```elixir
# config/prod.exs - Production configuration
import Config

# Database configuration from environment
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

# Production endpoint configuration
config :my_app, MyAppWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "4000")
  ],
  https: [
    port: String.to_integer(System.get_env("HTTPS_PORT") || "4001"),
    cipher_suite: :strong,
    keyfile: System.get_env("SSL_KEY_FILE"),
    certfile: System.get_env("SSL_CERT_FILE")
  ],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Configure mailer for production
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Mailgun,
  api_key: System.get_env("MAILGUN_API_KEY"),
  domain: System.get_env("MAILGUN_DOMAIN")

# Configure external services
config :my_app, :external_api,
  base_url: System.get_env("EXTERNAL_API_URL"),
  api_key: System.get_env("EXTERNAL_API_KEY"),
  timeout: String.to_integer(System.get_env("EXTERNAL_API_TIMEOUT") || "30000")

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

## Runtime Configuration

```elixir
# config/runtime.exs - Runtime configuration
import Config

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
    ip: parse_ip(System.get_env("PHX_IP") || "0.0.0.0"),
    port: String.to_integer(System.get_env("PORT") || "4000")
  ],
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
    environment_name: System.get_env("SENTRY_ENVIRONMENT") || "production"
end

# Configure feature flags
config :my_app, :feature_flags,
  new_ui: System.get_env("FEATURE_NEW_UI") == "true",
  analytics: System.get_env("FEATURE_ANALYTICS") == "true",
  rate_limiting: System.get_env("FEATURE_RATE_LIMITING") == "true"

# Helper function to parse IP addresses
defp parse_ip(ip) when is_binary(ip) do
  ip
  |> String.split(".")
  |> Enum.map(&String.to_integer/1)
  |> List.to_tuple()
end
```

## Configuration Module

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
  Gets database configuration.
  """
  def database do
    get(MyApp.Repo, [])
  end

  @doc """
  Gets endpoint configuration.
  """
  def endpoint do
    get(MyAppWeb.Endpoint, [])
  end

  @doc """
  Gets external API configuration.
  """
  def external_api do
    get(:external_api, %{})
  end

  @doc """
  Gets feature flag configuration.
  """
  def feature_flags do
    get(:feature_flags, %{})
  end

  @doc """
  Checks if a feature is enabled.
  """
  def feature_enabled?(feature) do
    feature_flags()
    |> Map.get(feature, false)
  end

  @doc """
  Gets Redis configuration.
  """
  def redis do
    get(:redis, %{})
  end

  @doc """
  Gets mail configuration.
  """
  def mailer do
    get(MyApp.Mailer, [])
  end

  @doc """
  Gets monitoring configuration.
  """
  def monitoring do
    %{
      sentry: Application.get_env(:sentry, :dsn),
      prometheus: get(:prometheus, %{}),
      health_check: get(:health_check, %{})
    }
  end

  @doc """
  Gets environment name.
  """
  def environment do
    System.get_env("MIX_ENV") || "dev"
  end

  @doc """
  Checks if running in production.
  """
  def production? do
    environment() == "prod"
  end

  @doc """
  Checks if running in development.
  """
  def development? do
    environment() == "dev"
  end

  @doc """
  Checks if running in test.
  """
  def test? do
    environment() == "test"
  end
end
```

## Secrets Management

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

  @doc """
  Retrieves multiple secrets at once.
  """
  def get_secrets(keys) do
    keys
    |> Enum.map(fn key -> {key, get_secret(key)} end)
    |> Map.new()
  end

  @doc """
  Rotates a secret (if supported by the secret store).
  """
  def rotate_secret(key, new_value) do
    case secret_store() do
      :aws_secrets_manager -> rotate_in_aws_secrets_manager(key, new_value)
      :vault -> rotate_in_vault(key, new_value)
      _ -> {:error, :not_supported}
    end
  end

  # Private functions

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

  defp rotate_in_aws_secrets_manager(key, new_value) do
    ExAws.SecretsManager.update_secret(key, secret_string: new_value)
    |> ExAws.request()
  end

  defp rotate_in_vault(key, new_value) do
    vault_path = Application.get_env(:my_app, :vault_path, "secret/")
    Vault.write("#{vault_path}#{key}", %{value: new_value})
  end
end
```

## Configuration Validation

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

## Development Configuration Helpers

```elixir
# config/dev.local.exs (optional, gitignored)
import Config

# Override any development settings locally
config :my_app, MyApp.Repo,
  database: "my_app_dev_local"

config :my_app, :external_api,
  base_url: "http://localhost:3000",
  mock: false

config :my_app, :feature_flags,
  new_ui: true,
  analytics: false

# Personal development settings
config :my_app, MyAppWeb.Endpoint,
  http: [port: 4001]
```

## Environment Variable Documentation

```elixir
# lib/my_app/config/env_docs.ex
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
    },
    %{
      name: "PHX_HOST",
      description: "Phoenix application hostname",
      required: false,
      default: "localhost",
      example: "myapp.com"
    },
    %{
      name: "POOL_SIZE",
      description: "Database connection pool size",
      required: false,
      default: "10",
      example: "20"
    },
    %{
      name: "REDIS_URL",
      description: "Redis connection string",
      required: false,
      example: "redis://localhost:6379/0"
    },
    %{
      name: "SENTRY_DSN",
      description: "Sentry error reporting DSN",
      required: false,
      example: "https://key@sentry.io/project"
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

## Tips & Best Practices

### Configuration Organization
- Use `config/config.exs` for common settings
- Use environment-specific files for environment differences
- Use `config/runtime.exs` for runtime configuration
- Keep sensitive data in environment variables

### Security
- Never commit secrets to version control
- Use proper secret management systems in production
- Rotate secrets regularly
- Use different secrets for different environments

### Validation
- Validate configuration at application startup
- Provide clear error messages for missing configuration
- Document all environment variables
- Use default values where appropriate

### Environment Management
- Use `.env` files for local development
- Use container secrets for containerized deployments
- Use cloud-native secret management in cloud environments
- Implement proper secret rotation strategies

## References

- [Phoenix Configuration](https://hexdocs.pm/phoenix/Phoenix.Config.html)
- [Elixir Config](https://hexdocs.pm/elixir/Config.html)
- [Environment Variables](https://hexdocs.pm/elixir/System.html#get_env/2)
- [Secrets Management Best Practices](https://owasp.org/www-project-cheat-sheets/cheatsheets/Secrets_Management_CheatSheet.html)