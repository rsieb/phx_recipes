# Authentication & Authorization Recipe

## Introduction

Authentication verifies **who** a user is, while authorization determines **what** they can do. Together, they form the security foundation of your Phoenix application. This recipe covers when and how to implement these patterns effectively.

## When to Use These Patterns

**Use simple token authentication when:**
- Building an MVP with basic user sessions
- You need straightforward login/logout functionality
- External auth providers aren't required

**Use LiveView authentication when:**
- Your app is primarily LiveView-based
- You need real-time user state management
- Sessions should persist across LiveView connections

**Use API authentication when:**
- Building APIs for mobile apps or SPAs
- Implementing machine-to-machine communication
- Supporting multiple client types

**Use role-based authorization when:**
- You have distinct user types (admin, user, moderator)
- Permissions are relatively static
- Simple role hierarchies suffice

## Basic Authentication with Phoenix.Token

Phoenix.Token provides cryptographically signed tokens that are perfect for session management. They're tamper-proof and automatically expire.

```elixir
defmodule MyAppWeb.Auth do
  import Plug.Conn
  import Phoenix.Controller

  @max_age 86400 # 24 hours in seconds

  def sign_user_token(user_id) do
    Phoenix.Token.sign(MyAppWeb.Endpoint, "user_auth", user_id)
  end

  def verify_user_token(token) do
    Phoenix.Token.verify(MyAppWeb.Endpoint, "user_auth", token, max_age: @max_age)
  end

  def authenticate_user(conn, _opts) do
    case get_session(conn, :user_token) do
      nil ->
        conn
        |> put_session(:return_to, current_path(conn))
        |> redirect(to: "/login")
        |> halt()

      token ->
        case verify_user_token(token) do
          {:ok, user_id} ->
            user = MyApp.Accounts.get_user!(user_id)
            assign(conn, :current_user, user)

          {:error, _reason} ->
            conn
            |> delete_session(:user_token)
            |> redirect(to: "/login")
            |> halt()
        end
    end
  end
end
```

**Why this works:** Phoenix.Token uses your app's secret key to create unforgeable tokens. The max_age ensures tokens expire automatically, forcing periodic re-authentication for security.

**When to use:** This pattern is ideal for traditional web applications where users log in through forms and maintain sessions via cookies.

## LiveView Authentication Integration

LiveView applications need authentication that works seamlessly with real-time connections. The `live_session` and `on_mount` hooks provide this integration.

```elixir
# In your router
scope "/", MyAppWeb do
  pipe_through [:browser, :authenticated]

  live_session :authenticated, on_mount: {MyAppWeb.Auth, :ensure_authenticated} do
    live "/dashboard", DashboardLive, :index
    live "/profile", ProfileLive, :show
  end
end

# Authentication hook
defmodule MyAppWeb.Auth do
  import Phoenix.LiveView

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session["user_token"] do
      nil ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/login")

        {:halt, socket}

      token ->
        case verify_user_token(token) do
          {:ok, user_id} ->
            user = MyApp.Accounts.get_user!(user_id)
            socket = assign(socket, :current_user, user)
            {:cont, socket}

          {:error, _reason} ->
            socket =
              socket
              |> put_flash(:error, "Your session has expired.")
              |> redirect(to: "/login")

            {:halt, socket}
        end
    end
  end
end
```

**Why this works:** The `on_mount` hook runs before every LiveView in the session, ensuring authentication is checked consistently. Sessions are shared between traditional controllers and LiveViews.

**When to use:** Essential for any LiveView that requires authentication. Use `:maybe_authenticated` for public pages that show different content for logged-in users.

## API Authentication with Bearer Tokens

APIs need stateless authentication that works across different clients and doesn't rely on cookies or sessions.

```elixir
defmodule MyAppWeb.APIAuth do
  import Plug.Conn
  import Phoenix.Controller

  def authenticate_api(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case verify_api_token(token) do
          {:ok, user_id} ->
            user = MyApp.Accounts.get_user!(user_id)
            assign(conn, :current_user, user)

          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Invalid or expired token"})
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing authorization header"})
        |> halt()
    end
  end

  def verify_api_token(token) do
    # Use longer expiry for API tokens (30 days)
    Phoenix.Token.verify(MyAppWeb.Endpoint, "api_auth", token, max_age: 2_592_000)
  end
end
```

**Why this works:** Bearer tokens in the Authorization header are the standard for API authentication. They're stateless, work across different domains, and integrate well with mobile apps and SPAs.

**When to use:** For any API endpoints, mobile app backends, or when you need stateless authentication that doesn't rely on cookies.

## Role-Based Authorization

Once you know who the user is, you need to control what they can do. Role-based systems group permissions by user type.

```elixir
defmodule MyApp.Authorization do
  @role_permissions %{
    user: [:read_posts],
    moderator: [:read_posts, :write_posts, :moderate_content],
    admin: [:read_posts, :write_posts, :moderate_content, :read_users, :write_users]
  }

  def can?(user, permission) when is_atom(permission) do
    role_permissions = @role_permissions[user.role] || []
    permission in role_permissions or permission in user.permissions
  end

  def authorize(user, permission) do
    if can?(user, permission) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  # Resource-based permissions
  def can_edit?(user, %{user_id: user_id}) when user.id == user_id, do: true
  def can_edit?(%{role: :admin}, _resource), do: true
  def can_edit?(_user, _resource), do: false
end
```

**Why this works:** This approach separates role-based permissions (consistent across all users of a role) from individual permissions (granted per user). Resource ownership is checked separately.

**When to use:** When you have clear user roles with distinct permissions. For more complex scenarios, consider attribute-based access control (ABAC) or policy-based systems.

## Context Integration with Authorization

Your contexts should enforce authorization consistently, making security a natural part of your business logic.

```elixir
defmodule MyApp.Blog do
  alias MyApp.Authorization

  def list_posts(%{role: :admin} = _user) do
    Repo.all(Post)
  end

  def list_posts(user) do
    from(p in Post,
      where: p.published == true or p.user_id == ^user.id
    )
    |> Repo.all()
  end

  def update_post(post, attrs, user) do
    with :ok <- Authorization.authorize(user, :write_posts),
         true <- Authorization.can_edit?(user, post) do
      post
      |> Post.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized} -> {:error, :unauthorized}
      false -> {:error, :forbidden}
    end
  end
end
```

**Why this works:** Authorization happens at the context level, ensuring business rules are enforced consistently across your application. Controllers become thin adapters that focus on HTTP concerns.

**When to use:** For all context functions that access sensitive data or perform privileged operations. This creates a secure-by-default system.

## Session Security Best Practices

Secure session configuration is crucial for protecting user authentication tokens and preventing session hijacking.

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  session_store: :cookie,
  session_options: [
    store: :cookie,
    key: "_my_app_key",
    signing_salt: System.get_env("SESSION_SIGNING_SALT"),
    same_site: "Lax",
    secure: true, # HTTPS only in production
    http_only: true,
    max_age: 86400 # 24 hours
  ]
```

**Why this works:** These settings prevent XSS attacks (http_only), CSRF attacks (same_site), and man-in-the-middle attacks (secure). The signing salt ensures session integrity.

**When to use:** Always configure these settings for production. Consider shorter max_age for high-security applications.

## Common Pitfalls and How to Avoid Them

**Timing Attacks in Authentication**
Always run password verification even for non-existent users to prevent attackers from determining valid email addresses through response timing.

**Session Fixation**
Always regenerate session IDs after login to prevent session fixation attacks. Phoenix does this automatically with `configure_session(conn, renew: true)`.

**Authorization Bypass**
Never rely on client-side authorization checks. Always enforce permissions in your contexts and controllers.

**Token Storage**
Store API tokens securely on the client side. Never include them in URLs or log them in plaintext.

## Testing Authentication & Authorization

Create helper functions that make testing authentication scenarios straightforward and consistent.

```elixir
defmodule MyAppWeb.AuthTestHelpers do
  def login_user(conn, user) do
    token = MyAppWeb.Auth.sign_user_token(user.id)
    
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  def login_admin(conn) do
    admin = user_fixture(%{role: :admin})
    login_user(conn, admin)
  end
end
```

**Why this works:** Test helpers abstract the authentication mechanism, making tests more readable and maintainable. They also ensure consistent test setup across your test suite.

## Decision Criteria

**Choose token-based authentication when:**
- Building traditional web applications
- Sessions should expire automatically
- You want simplicity and security

**Choose API tokens when:**
- Building APIs or mobile backends
- Clients need long-lived authentication
- Supporting multiple client types

**Choose role-based authorization when:**
- You have distinct user types
- Permissions are relatively stable
- Simple hierarchies work for your domain

**Consider more complex authorization when:**
- You need fine-grained permissions
- Resources have complex ownership models
- Dynamic permissions based on context

## References

- [Phoenix.Token Documentation](https://hexdocs.pm/phoenix/Phoenix.Token.html)
- [Phoenix Authentication Guide](https://hexdocs.pm/phoenix/authentication.html)
- [LiveView Authentication](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Router.html#live_session/3)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)