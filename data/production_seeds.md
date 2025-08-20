# Production Seeds Recipe

## Problem

In production Phoenix releases, there's no `mix run priv/repo/seeds.exs`. You need a way to run seed data after deploying to Fly.io or other production environments.

## Solution: Release Module

### 1. Create Release Module

```elixir
# lib/my_app/release.ex
defmodule MyApp.Release do
  @app :my_app

  def migrate do
    load_app()
    
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()
    
    # Optionally run migrations first
    migrate()
    
    seed_file = Application.app_dir(@app, "priv/repo/seeds.exs")
    
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _ ->
        Code.eval_file(seed_file)
      end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

### 2. Make Seeds Idempotent

```elixir
# priv/repo/seeds.exs
alias MyApp.Repo
alias MyApp.Accounts.User

# Create admin user - won't fail if already exists
admin_attrs = %{
  email: "admin@example.com",
  name: "Admin",
  password: "changeme123"  # Change in production!
}

%User{}
|> User.changeset(admin_attrs)
|> Repo.insert(
  on_conflict: :nothing,
  conflict_target: :email
)

IO.puts("Admin user seeded")

# Alternative: Check before insert
unless Repo.get_by(User, email: "admin@example.com") do
  %User{}
  |> User.changeset(admin_attrs)
  |> Repo.insert!()
end
```

## Fly.io Deployment

### Docker Setup

```dockerfile
# Dockerfile
FROM elixir:1.15-alpine AS app

# ... your existing build steps ...

# Add entrypoint
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["start"]
```

```bash
#!/bin/sh
# entrypoint.sh
set -e

case "$1" in
  start)
    echo "Running migrations..."
    bin/my_app eval "MyApp.Release.migrate()"
    echo "Starting app..."
    bin/my_app start
    ;;
  *)
    exec "$@"
    ;;
esac
```

### Fly.io Configuration

```toml
# fly.toml
[deploy]
  # Auto-run migrations on deploy
  release_command = "/app/bin/my_app eval 'MyApp.Release.migrate()'"

[processes]
  app = "/app/bin/my_app start"
```

### Running Seeds

```bash
# After deployment, SSH in and run seeds manually
fly ssh console -C "/app/bin/my_app eval 'MyApp.Release.seed()'"

# Or run from your local machine
fly ssh console
/app/bin/my_app eval 'MyApp.Release.seed()'
```

## MVP Patterns

### Simple Reference Data

```elixir
# priv/repo/seeds.exs - Keep it simple for MVP
alias MyApp.Repo

# Insert reference data that your app needs
plans = [
  %{name: "free", price: 0, features: ["basic"]},
  %{name: "pro", price: 29, features: ["all"]}
]

for plan <- plans do
  %MyApp.Billing.Plan{}
  |> MyApp.Billing.Plan.changeset(plan)
  |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
end
```

### Development vs Production Seeds

```elixir
# priv/repo/seeds.exs
alias MyApp.Repo

# Always seed essential data
%MyApp.Accounts.User{}
|> MyApp.Accounts.User.changeset(%{
  email: "admin@example.com",
  password: System.get_env("ADMIN_PASSWORD", "changeme123")
})
|> Repo.insert(on_conflict: :nothing, conflict_target: :email)

# Only seed test data in dev/staging
if Application.get_env(:my_app, :environment) != :prod do
  for i <- 1..10 do
    %MyApp.Accounts.User{}
    |> MyApp.Accounts.User.changeset(%{
      email: "user#{i}@example.com",
      password: "password123"
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: :email)
  end
  
  IO.puts("Development seeds completed")
end
```

## Common Issues and Solutions

### Seeds Failing Silently

Add error handling to see what's wrong:

```elixir
# lib/my_app/release.ex
def seed do
  load_app()
  migrate()
  
  seed_file = Application.app_dir(@app, "priv/repo/seeds.exs")
  
  for repo <- repos() do
    case Ecto.Migrator.with_repo(repo, fn _ -> Code.eval_file(seed_file) end) do
      {:ok, _, _} -> 
        IO.puts("✓ Seeds completed")
      {:error, error} -> 
        IO.puts("✗ Seed failed: #{inspect(error)}")
        raise "Seeding failed"
    end
  end
end
```

### Can't Find Seed File

Check the path in production:

```elixir
def seed do
  load_app()
  
  seed_file = Application.app_dir(@app, "priv/repo/seeds.exs")
  IO.puts("Looking for seeds at: #{seed_file}")
  IO.puts("File exists: #{File.exists?(seed_file)}")
  
  # ... rest of function
end
```

## Quick Reference

```bash
# Local development
mix run priv/repo/seeds.exs

# Production (Fly.io)
fly ssh console -C "/app/bin/my_app eval 'MyApp.Release.migrate()'"  # Migrations only
fly ssh console -C "/app/bin/my_app eval 'MyApp.Release.seed()'"     # Migrations + seeds

# Check if seeds ran
fly ssh console
/app/bin/my_app remote
iex> MyApp.Repo.get_by(MyApp.Accounts.User, email: "admin@example.com")
```

## MVP Tips

1. **Keep seeds minimal** - Only seed what's absolutely necessary (admin user, reference data)
2. **Use `on_conflict: :nothing`** - Simplest way to make seeds idempotent
3. **Run seeds manually** - Don't auto-run in production; do it deliberately after deploy
4. **Use environment variables** - For sensitive data like admin passwords
5. **Test locally first** - Run `mix run priv/repo/seeds.exs` twice to ensure idempotency

## Don't Do This in MVP

- Complex seed modules and organization (just use one file)
- Environment-specific seed files (use simple if statements)
- Automated seeding on every deploy (run manually when needed)
- Complex Multi transactions in seeds (keep it simple)
- Heavy business logic in seeds (just insert data)

Remember: For MVP, seeds should just create an admin user and any essential reference data. Everything else can be added through your app's UI.