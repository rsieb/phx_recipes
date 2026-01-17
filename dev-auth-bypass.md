# Dev/Test Authentication Bypass Recipe

## Problem
UAT (User Acceptance Testing) requires manual authentication for every authenticated route, making testing tedious and slow. Need atomic test access without login flows.

## Solution
Environment-based authentication bypass that auto-authenticates a test user in dev/test environments only.

## Implementation

### 1. Router Plug (`lib/middling_web/router.ex`)

Add bypass plug to `:browser` pipeline:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, {MiddlingWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers, %{...}

  plug :fetch_current_user
  plug :maybe_bypass_auth  # ← Add this line
  plug :fetch_impersonator_user
  # ... rest of pipeline
end
```

### 2. Bypass Logic (end of `router.ex`)

```elixir
# Dev/Test Auth Bypass for UAT Testing
defp maybe_bypass_auth(conn, _opts) do
  if bypass_auth_enabled?() && is_nil(conn.assigns[:current_user]) do
    case get_or_create_test_user() do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> put_session(:user_id, user.id)

      {:error, _reason} ->
        conn
    end
  else
    conn
  end
end

defp bypass_auth_enabled? do
  Application.get_env(:middling, :bypass_auth, false) == true
end

defp get_or_create_test_user do
  alias Middling.Accounts

  case Accounts.get_user_by_email("test@example.com") do
    %Accounts.User{confirmed_at: confirmed_at} = user when not is_nil(confirmed_at) ->
      {:ok, user}

    %Accounts.User{} = user ->
      {:ok, Accounts.confirm_user!(user)}

    nil ->
      case Accounts.register_user(%{
             email: "test@example.com",
             password: "password123456",
             is_onboarded: true
           }) do
        {:ok, user} -> {:ok, Accounts.confirm_user!(user)}
        {:error, _changeset} = error -> error
      end
  end
end
```

### 3. Enable in Dev Config (`config/dev.exs`)

```elixir
config :middling, :env, :dev

# Enable auth bypass for UAT testing
config :middling, bypass_auth: true
```

### 4. Enable in Test Config (`config/test.exs`)

```elixir
config :middling, :env, :test

# Enable auth bypass for UAT testing
config :middling, bypass_auth: true
```

## Usage

### Development
```bash
# Start server
iex -S mix phx.server

# Access any authenticated route - auto-logged in as test@example.com
# http://localhost:4004/app/proposals
# http://localhost:4004/app/decode/123
# http://localhost:4004/app/dashboard
```

### Testing
```bash
# All tests auto-authenticate
mix test

# Wallaby E2E tests skip login flow
mix test --only wallaby
```

## Benefits

✅ **Scalable**: Works for ALL authenticated routes automatically
✅ **Standard Pattern**: Phoenix best practice (plug-based)
✅ **Zero Auth Changes**: No modifications to auth logic
✅ **Safe**: Only enabled via explicit config
✅ **One-Time Setup**: Works forever for all features

## Security

### Production Safety
- ❌ **Never enabled in production** (no config setting)
- ✅ **Explicit opt-in** via environment config
- ✅ **Test user clearly identified** (test@example.com)
- ✅ **No backdoor logic** in production code paths

### Deployment Checklist
```bash
# Verify bypass_auth is false/absent in production
grep -r "bypass_auth.*true" config/prod.exs
# Should return nothing

# Verify production config doesn't leak
grep -r "test@example.com" config/prod.exs
# Should return nothing
```

## Alternatives Considered

### ❌ Individual Dev Routes
```elixir
live "/dev/proposals", ProposalLive.Index
live "/dev/decode/:id", DecoderLive.Show
```
**Problem**: Unscalable - need duplicate routes for every feature

### ❌ On-Mount Hook Modification
```elixir
def on_mount(:require_authenticated_user, ...) do
  if dev?, do: auto_login()
end
```
**Problem**: Modifies core auth logic, harder to reason about

### ✅ Query Parameter Toggle
```elixir
defp maybe_bypass_auth(conn, _opts) do
  cond do
    conn.params["_bypass_auth"] == "true" ->
      # Enable for session
    conn.params["_bypass_auth"] == "false" ->
      # Disable for session
    # ...
  end
end
```
**Use case**: When you want to test both authenticated and unauthenticated states in same dev session

## Test User Details

**Email**: `test@example.com`
**Password**: `password123456`
**Status**: Confirmed, onboarded
**Created**: Auto-created on first bypass
**Reused**: Subsequent requests use existing user

## Troubleshooting

### Bypass Not Working
```bash
# Verify config
grep bypass_auth config/dev.exs
# Should show: config :middling, bypass_auth: true

# Restart server to pick up config changes
# (config changes require server restart)
```

### Test User Issues
```bash
# Manually create test user if needed
mix run -e "
  {:ok, user} = Middling.Accounts.register_user(%{
    email: \"test@example.com\",
    password: \"password123456\",
    is_onboarded: true
  })
  Middling.Accounts.confirm_user!(user)
"
```

### Still Seeing Login Screen
1. Check config file has `bypass_auth: true`
2. Restart Phoenix server (config changes need restart)
3. Verify plug is in `:browser` pipeline
4. Check plug order (must be after `:fetch_current_user`)

## Related Patterns

### Magic Link Auth (Staging)
For staging environments with some security but easy access:

```elixir
defp check_magic_token(conn, _opts) do
  case conn.params["magic_token"] do
    nil -> conn
    token ->
      case Phoenix.Token.verify(MyAppWeb.Endpoint, "magic auth", token) do
        {:ok, user_id} ->
          user = Accounts.get_user!(user_id)
          conn
          |> assign(:current_user, user)
          |> put_session(:user_id, user.id)
        {:error, _} -> conn
      end
  end
end
```

Usage: `https://staging.app.com/dashboard?magic_token=xyz`

### Multiple Test Users (Role Testing)
Seed different user roles and add dev toolbar to switch:

```elixir
defp get_test_user_by_role(role) do
  Accounts.get_user_by_email("test-#{role}@example.com")
end
```

Access: `/dev/switch-user?role=admin`

## Credits

Pattern recommended by Claude Sonnet 4.5 based on Phoenix community best practices.
