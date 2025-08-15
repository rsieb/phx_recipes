
# Environment Best Practices in Phoenix

This guide defines best practices for managing environments (`dev`, `staging`, `prod`) in a Phoenix app.

Follow these conventions unless there is a compelling reason not to. They’re based on what experienced Phoenix developers do to avoid pain.

---

## ☝️ One Principle: Everything that changes by environment goes in the ENV

- Do **not** hardcode secrets, URLs, or environment-specific logic.
- Instead, load them using `System.fetch_env!/1` or `System.get_env/1` in `config/runtime.exs`.

---

## 📁 File Structure and Purpose

| File                  | Purpose                                                                 |
|-----------------------|-------------------------------------------------------------------------|
| `config/config.exs`   | Compile-time shared defaults. Avoid runtime values here.                |
| `config/dev.exs`      | Developer machine config (local-only). OK to keep simple here.          |
| `config/test.exs`     | For CI and local testing. Hardcode safely.                              |
| `config/prod.exs`     | Avoid if possible. Use `runtime.exs` instead for production overrides.   |
| `config/runtime.exs`  | Primary config for staging/prod. All dynamic config goes here.          |

---

## 🔑 Secrets and Environment Variables

- Use `.env` and load with [`direnv`](https://direnv.net/) or [`dotenv`](https://github.com/bkeepers/dotenv).
- Never commit `.env` files.
- Prefix sensitive env vars clearly:
  - `DATABASE_URL`
  - `SECRET_KEY_BASE`
  - `PHX_HOST`
  - `POOL_SIZE`

Example `.env` (non-prod):
```env
DATABASE_URL=postgresql://localhost/leadpoise_dev
SECRET_KEY_BASE=...
PHX_HOST=localhost
POOL_SIZE=10
```

---

## 🔧 config/runtime.exs Template

```elixir
import Config

if config_env() in [:prod, :staging] do
  database_url = System.fetch_env!("DATABASE_URL")

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true

  config :my_app, MyAppWeb.Endpoint,
    url: [host: System.fetch_env!("PHX_HOST"), port: 443],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true
end
```

---

## 🧪 Dev Setup (`dev.exs`)

- Keep it simple and developer-friendly.
- Use local database without secrets.
- Never reference runtime env vars.

```elixir
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  database: "my_app_dev",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

---

## 🧪 Test Setup (`test.exs`)

- Use static in-memory or sandboxed resources.
- No runtime dependencies.

```elixir
config :my_app, MyApp.Repo,
  database: "my_app_test",
  pool: Ecto.Adapters.SQL.Sandbox
```

---

## 🧱 Setting Up a Staging Environment

1. **Create a new staging environment on your hosting platform (e.g., Railway, Fly.io, Gigalixir)**.

2. **Set the following environment variables:**
   ```env
   MIX_ENV=staging
   DATABASE_URL=your-staging-db-url
   SECRET_KEY_BASE=generated-staging-secret
   PHX_HOST=staging.myapp.com
   POOL_SIZE=10
   ```

3. **Deploy with `MIX_ENV=staging`**:
   - If using releases:
     ```bash
     MIX_ENV=staging mix release
     ```
   - Deploy the release binary with proper ENV settings.

4. **Use the same `runtime.exs` logic for both `:prod` and `:staging`:**
   - This avoids duplication and encourages consistency.

5. **Point a staging domain at it** (`staging.myapp.com`) and test with HTTPS enabled.

6. **Set `check_origin` in your `runtime.exs` or via ENV:**
   ```elixir
   check_origin: [
     "https://staging.myapp.com"
   ]
   ```

7. **Ensure migrations are run during staging deploys:**
   ```bash
   bin/my_app eval "MyApp.Release.migrate"
   ```

---

## 🔄 Release Tasks

Use a `Release` module to run migrations:

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

Run with:

```bash
bin/my_app eval "MyApp.Release.migrate"
```

---

## ✅ Summary Checklist

✅ All dynamic values in `runtime.exs`  
✅ All secrets from ENV vars  
✅ Dev uses static config only  
✅ Avoid `prod.exs` – handle it via `runtime.exs`  
✅ Use `System.fetch_env!/1` to fail fast on missing config  
✅ Never use `config/4` – only `config/3` with `import Config`  
✅ Use `:staging` as a first-class environment (not a hacked-up `:prod`)

---

## 🛠 Tooling Tips

- Use `direnv` or `dotenv-linter` to manage `.env` files.
- Use `mix config_env()` to check environment in code.
- Use `mix release` with runtime config and a bootstrap script to handle releases cleanly.

---

## 🤝 Adopt This as a Team Convention

- Copy/paste this file into your repo as `environment_best_practices_in_phoenix.md`
- Refer to it in onboarding docs
- Make PR reviewers enforce it

Consistency avoids production bugs and onboarding friction.
