# Phoenix Environments: Development, Staging, and Production Reality Check

## The Problem: Mix.env Doesn't Exist in Production

Your code works perfectly in development with `Mix.env()`, then crashes in production with `(UndefinedFunctionError) function Mix.env/0 is undefined (module Mix is not available)`. This happens because Mix is a build tool that doesn't exist in production releases.

## Key Concept: Compile-Time vs Runtime

Phoenix has two distinct phases that many developers conflate:

1. **Compile-time**: When your code is being compiled (Mix is available)
2. **Runtime**: When your application is running (Mix is NOT available in releases)

```elixir
# ❌ WRONG - This crashes in production
defmodule MyApp.SomeModule do
  def check_environment do
    case Mix.env() do  # Mix doesn't exist in production!
      :prod -> do_production_thing()
      :dev -> do_dev_thing()
    end
  end
end

# ✅ CORRECT - Use Application.get_env configured at runtime
defmodule MyApp.SomeModule do
  def check_environment do
    case Application.get_env(:my_app, :environment) do
      :production -> do_production_thing()
      :staging -> do_staging_thing()
      _ -> do_dev_thing()
    end
  end
end
```

## The Standard Phoenix Approach

Experienced Phoenix developers keep it simple: set an environment variable explicitly in your deployment platform and read it in `runtime.exs`.

### 1. Configure in runtime.exs

```elixir
# config/runtime.exs
import Config

# Simple and explicit - this is what most Phoenix apps do
config :my_app, :environment, 
  System.get_env("APP_ENV", "development") |> String.to_atom()

# Use it for environment-specific configuration
environment = Application.get_env(:my_app, :environment)

config :my_app, MyApp.Repo,
  pool_size: if(environment == :production, do: 50, else: 10)

config :my_app,
  # Feature flags
  send_real_emails: environment in [:production, :staging],
  show_debug_toolbar: environment == :development,
  
  # Service URLs
  cdn_url: 
    case environment do
      :production -> "https://cdn.example.com"
      :staging -> "https://staging-cdn.example.com"
      _ -> ""
    end
```

### 2. Create a Simple Helper Module

```elixir
# lib/my_app/environment.ex
defmodule MyApp.Environment do
  @moduledoc """
  Runtime environment detection.
  """

  def current do
    Application.get_env(:my_app, :environment, :development)
  end

  def production? do
    current() == :production
  end

  def staging? do
    current() == :staging
  end

  def development? do
    current() == :development
  end

  def test? do
    # Special case: test environment is set at compile time
    Application.get_env(:my_app, :environment, :test) == :test
  end

  def production_or_staging? do
    current() in [:production, :staging]
  end
end
```

### 3. Set Environment Variables in Your Platform

**Fly.io:**
```bash
fly secrets set APP_ENV=production
# or for staging
fly secrets set APP_ENV=staging
```

**Heroku:**
```bash
heroku config:set APP_ENV=production
```

**Docker:**
```dockerfile
ENV APP_ENV=production
```

**Systemd:**
```ini
[Service]
Environment="APP_ENV=production"
```

**Kubernetes:**
```yaml
env:
  - name: APP_ENV
    value: "production"
```

### 4. Use in Your Application

```elixir
defmodule MyApp.Mailer do
  require Logger

  def send_email(to, subject, body) do
    if MyApp.Environment.production_or_staging?() do
      # Actually send the email
      deliver_email(to, subject, body)
    else
      # Just log in development
      Logger.info("Would send email to #{to}: #{subject}")
      {:ok, :logged}
    end
  end
end

defmodule MyAppWeb.ErrorView do
  use MyAppWeb, :view

  def render("500.html", _assigns) do
    if MyApp.Environment.development?() do
      # Show detailed error in development
      "Internal Server Error - Check your logs"
    else
      # Generic message in production
      "Something went wrong"
    end
  end
end
```

## Compile-Time Configuration (When Mix.env IS Available)

Use Mix.env() ONLY in config files during compilation:

```elixir
# config/config.exs - Mix.env() is safe here
import Config

config :my_app, MyAppWeb.Endpoint,
  debug_errors: Mix.env() == :dev,
  code_reloader: Mix.env() == :dev,
  check_origin: Mix.env() != :dev

config :logger, :console,
  format: if(Mix.env() == :prod, do: "[$level] $message\n", else: "[$level] $metadata $message\n")

# config/dev.exs, config/prod.exs, config/test.exs
# These files are selected based on MIX_ENV during compilation
```

## Common Anti-Patterns and How to Fix Them

### Anti-Pattern 1: Using Mix.env in Module Attributes

```elixir
# ❌ WRONG - Module attributes are compile-time
defmodule MyApp.SomeModule do
  @environment Mix.env()  # This is frozen at compile time!
  
  def get_env, do: @environment  # Always returns :prod in production builds
end

# ✅ CORRECT - Call at runtime
defmodule MyApp.SomeModule do
  def get_env, do: MyApp.Environment.current()
end
```

### Anti-Pattern 2: Compile-Time Conditionals

```elixir
# ❌ WRONG - This decision is made at compile time
defmodule MyApp.Service do
  if Mix.env() == :prod do
    def api_url, do: "https://api.example.com"
  else
    def api_url, do: "http://localhost:4001"
  end
end

# ✅ CORRECT - Make decision at runtime
defmodule MyApp.Service do
  def api_url do
    case MyApp.Environment.current() do
      :production -> "https://api.example.com"
      :staging -> "https://staging-api.example.com"
      _ -> "http://localhost:4001"
    end
  end
end
```

### Anti-Pattern 3: Forgetting Test Environment

```elixir
# ❌ WRONG - Doesn't handle test environment
def send_notification(user, message) do
  if MyApp.Environment.production?() do
    SMS.send(user.phone, message)
  else
    Logger.info("Would send SMS: #{message}")
  end
end

# ✅ CORRECT - Handle test environment explicitly
def send_notification(user, message) do
  case MyApp.Environment.current() do
    :production -> SMS.send(user.phone, message)
    :staging -> SMS.send(user.phone, "[STAGING] #{message}")
    :test -> {:ok, :test_mode}
    _ -> Logger.info("Would send SMS: #{message}")
  end
end
```

### Anti-Pattern 4: Over-Engineering Detection

```elixir
# ❌ WRONG - Too clever, hard to debug
def detect_environment do
  cond do
    System.get_env("FLY_APP_NAME") -> :production
    System.get_env("HEROKU_APP_NAME") -> :production
    System.get_env("RENDER") -> :production
    port == "4000" -> :development
    # ... 20 more conditions
  end
end

# ✅ CORRECT - Simple and explicit
def current do
  System.get_env("APP_ENV", "development") |> String.to_atom()
end
```

### Anti-Pattern 5: Not Documenting Environment Setup

```elixir
# ❌ WRONG - No documentation on what to set
config :my_app, :environment,
  System.get_env("SOME_VAR", "development") |> String.to_atom()

# ✅ CORRECT - Clear documentation
# Set APP_ENV to one of: development, staging, production
# Defaults to development if not set
# 
# Examples:
#   fly secrets set APP_ENV=production
#   export APP_ENV=staging
config :my_app, :environment,
  System.get_env("APP_ENV", "development") |> String.to_atom()
```

## Testing Environment-Specific Code

```elixir
# test/my_app/environment_test.exs
defmodule MyApp.EnvironmentTest do
  use ExUnit.Case

  setup do
    # Save original value
    original = Application.get_env(:my_app, :environment)
    
    on_exit(fn ->
      Application.put_env(:my_app, :environment, original)
    end)
  end

  test "production behavior" do
    Application.put_env(:my_app, :environment, :production)
    
    assert MyApp.Environment.production?()
    refute MyApp.Environment.development?()
  end

  test "staging behavior" do
    Application.put_env(:my_app, :environment, :staging)
    
    assert MyApp.Environment.staging?()
    assert MyApp.Environment.production_or_staging?()
  end
end

# For testing modules that use environment
defmodule MyApp.MailerTest do
  use ExUnit.Case

  describe "send_email/3" do
    test "sends real email in production" do
      Application.put_env(:my_app, :environment, :production)
      
      # Mock or assert on actual email sending
      assert {:ok, _} = MyApp.Mailer.send_email("test@example.com", "Subject", "Body")
    end

    test "logs email in development" do
      Application.put_env(:my_app, :environment, :development)
      
      # Assert on log output
      assert {:ok, :logged} = MyApp.Mailer.send_email("test@example.com", "Subject", "Body")
    end
  end
end
```

## Environment Variables Best Practices

### What Phoenix Developers Actually Use

```elixir
# config/runtime.exs - The standard approach
import Config

# Core environment
config :my_app, :environment,
  System.get_env("APP_ENV", "development") |> String.to_atom()

# Database (usually set by platform)
database_url =
  System.get_env("DATABASE_URL") ||
  raise """
  environment variable DATABASE_URL is missing.
  For example: ecto://USER:PASS@HOST/DATABASE
  """

config :my_app, MyApp.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

# Secret key base (required for production)
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
  if Application.get_env(:my_app, :environment) == :development do
    "development-secret-key-base-at-least-64-characters-long"
  else
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """
  end

config :my_app, MyAppWeb.Endpoint,
  secret_key_base: secret_key_base

# Host configuration
host = System.get_env("PHX_HOST") || "localhost"
port = String.to_integer(System.get_env("PORT") || "4000")

config :my_app, MyAppWeb.Endpoint,
  url: [host: host, port: 443, scheme: "https"],
  http: [port: port]
```

## Quick Reference

| Context | Mix.env() Available? | What to Use | Example |
|---------|---------------------|-------------|---------|
| config/*.exs | ✅ Yes | `Mix.env()` | `if Mix.env() == :dev` |
| runtime.exs | ❌ No | `System.get_env()` | `System.get_env("APP_ENV")` |
| Application code | ❌ No in prod | `Application.get_env()` | `MyApp.Environment.current()` |
| Tests | ✅ Yes | Either | Prefer `Application.get_env` |
| Releases | ❌ No | `Application.get_env()` | `MyApp.Environment.current()` |

## Deployment Checklist

When deploying a Phoenix app:

1. **Set APP_ENV explicitly**
   ```bash
   # Production
   fly secrets set APP_ENV=production
   
   # Staging
   fly secrets set APP_ENV=staging
   ```

2. **Verify in logs**
   ```elixir
   # Add to your application.ex start/2
   def start(_type, _args) do
     Logger.info("Starting MyApp in #{MyApp.Environment.current()} environment")
     # ... rest of startup
   end
   ```

3. **Test environment-specific features**
   - Email sending
   - Error reporting
   - Feature flags
   - External service URLs

## The Golden Rules

1. **Keep it simple** - Use explicit `APP_ENV` environment variable
2. **Never use Mix.env() in application code** - Only in config files
3. **Document your environment variables** - Make deployment clear
4. **Default to safe values** - Usually development or readonly mode
5. **Test environment-specific code** - Don't assume it works
6. **Log the environment on startup** - Helps debugging deployment issues

## Complete Working Example

```elixir
# config/runtime.exs
import Config

# Simple, explicit environment configuration
config :my_app, :environment,
  System.get_env("APP_ENV", "development") |> String.to_atom()

# lib/my_app/environment.ex
defmodule MyApp.Environment do
  def current, do: Application.get_env(:my_app, :environment, :development)
  def production?, do: current() == :production
  def staging?, do: current() == :staging
  def development?, do: current() == :development
end

# Usage in your app
defmodule MyApp.SomeService do
  require Logger
  
  def process_payment(amount) do
    if MyApp.Environment.production?() do
      # Real payment processing
      PaymentGateway.charge(amount)
    else
      # Fake success in development/staging
      Logger.info("Simulated payment: $#{amount}")
      {:ok, "fake_transaction_id"}
    end
  end
end
```

This is the standard approach used by experienced Phoenix developers. It's simple, explicit, and easy to debug when things go wrong.