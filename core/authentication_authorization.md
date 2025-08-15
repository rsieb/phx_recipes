# Authentication & Authorization Recipe

## Introduction

Authentication and authorization are critical components of most Phoenix applications. This recipe covers comprehensive patterns for implementing secure authentication using Phoenix.Token, session management, LiveView authentication, API authentication, and permission systems following Phoenix best practices.

## Basic Authentication with Phoenix.Token

### Simple Token-Based Auth

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
            |> put_session(:return_to, current_path(conn))
            |> redirect(to: "/login")
            |> halt()
        end
    end
  end
end
```

### Session Controller with Token Management

```elixir
defmodule MyAppWeb.SessionController do
  use MyAppWeb, :controller
  alias MyApp.Accounts
  alias MyAppWeb.Auth

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        token = Auth.sign_user_token(user.id)
        
        conn
        |> put_session(:user_token, token)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: get_session(conn, :return_to) || "/dashboard")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:new)
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:user_token)
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: "/")
  end
end
```

## LiveView Authentication with live_session

### Router Configuration

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import MyAppWeb.Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug :authenticate_user
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
  end

  # Protected routes with live_session
  scope "/", MyAppWeb do
    pipe_through [:browser, :authenticated]

    live_session :authenticated, on_mount: {MyAppWeb.Auth, :ensure_authenticated} do
      live "/dashboard", DashboardLive, :index
      live "/profile", ProfileLive, :show
      live "/profile/edit", ProfileLive, :edit
      live "/users", UserLive.Index, :index
      live "/users/:id", UserLive.Show, :show
    end
  end

  # Admin routes with additional authorization
  scope "/admin", MyAppWeb.Admin do
    pipe_through [:browser, :authenticated]

    live_session :admin, on_mount: {MyAppWeb.Auth, :ensure_admin} do
      live "/", AdminDashboardLive, :index
      live "/users", UserManagementLive, :index
      live "/settings", SettingsLive, :index
    end
  end
end
```

### LiveView Auth Hook

```elixir
defmodule MyAppWeb.Auth do
  import Phoenix.Component
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
            
            socket =
              socket
              |> assign(:current_user, user)
              |> assign(:current_scope, :user)

            {:cont, socket}

          {:error, _reason} ->
            socket =
              socket
              |> put_flash(:error, "Your session has expired. Please log in again.")
              |> redirect(to: "/login")

            {:halt, socket}
        end
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    case on_mount(:ensure_authenticated, _params, session, socket) do
      {:cont, socket} ->
        case socket.assigns.current_user.role do
          :admin ->
            socket = assign(socket, :current_scope, :admin)
            {:cont, socket}

          _role ->
            socket =
              socket
              |> put_flash(:error, "You don't have permission to access this area.")
              |> redirect(to: "/dashboard")

            {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:maybe_authenticated, _params, session, socket) do
    case session["user_token"] do
      nil ->
        socket = assign(socket, :current_user, nil)
        {:cont, socket}

      token ->
        case verify_user_token(token) do
          {:ok, user_id} ->
            user = MyApp.Accounts.get_user!(user_id)
            socket = assign(socket, :current_user, user)
            {:cont, socket}

          {:error, _reason} ->
            socket = assign(socket, :current_user, nil)
            {:cont, socket}
        end
    end
  end
end
```

## API Authentication with Bearer Tokens

### API Authentication Plug

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
        |> json(%{error: "Missing or invalid authorization header"})
        |> halt()
    end
  end

  def verify_api_token(token) do
    # Use longer expiry for API tokens (30 days)
    Phoenix.Token.verify(MyAppWeb.Endpoint, "api_auth", token, max_age: 2_592_000)
  end

  def generate_api_token(user_id) do
    Phoenix.Token.sign(MyAppWeb.Endpoint, "api_auth", user_id)
  end
end
```

### API Token Management

```elixir
defmodule MyApp.Accounts.APIToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :string
    field :last_used_at, :naive_datetime
    field :expires_at, :naive_datetime
    belongs_to :user, MyApp.Accounts.User

    timestamps()
  end

  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name, :expires_at])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end

  def create_changeset(api_token, attrs, user) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode64()
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16()

    api_token
    |> changeset(attrs)
    |> put_change(:token_hash, token_hash)
    |> put_change(:user_id, user.id)
    |> put_change(:expires_at, default_expiry())
    |> put_meta(:plain_token, token)
  end

  defp default_expiry do
    DateTime.utc_now()
    |> DateTime.add(30, :day)
    |> DateTime.to_naive()
  end
end
```

### API Token Controller

```elixir
defmodule MyAppWeb.API.TokenController do
  use MyAppWeb, :controller
  alias MyApp.Accounts

  def create(conn, %{"token" => token_params}) do
    case Accounts.create_api_token(conn.assigns.current_user, token_params) do
      {:ok, {token_struct, plain_token}} ->
        conn
        |> put_status(:created)
        |> json(%{
          token: plain_token,
          name: token_struct.name,
          expires_at: token_struct.expires_at,
          message: "Store this token securely. You won't be able to see it again."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  def index(conn, _params) do
    tokens = Accounts.list_api_tokens(conn.assigns.current_user)
    json(conn, %{tokens: tokens})
  end

  def delete(conn, %{"id" => id}) do
    case Accounts.delete_api_token(conn.assigns.current_user, id) do
      {:ok, _token} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})
    end
  end
end
```

## Permission Systems

### Role-Based Access Control (RBAC)

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:user, :moderator, :admin], default: :user
    field :permissions, {:array, Ecto.Enum}, 
          values: [:read_users, :write_users, :read_posts, :write_posts, :moderate_content],
          default: []

    has_many :user_roles, MyApp.Accounts.UserRole
    many_to_many :roles, MyApp.Accounts.Role, join_through: "user_roles"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role, :permissions])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
```

### Permission Checking Module

```elixir
defmodule MyApp.Authorization do
  alias MyApp.Accounts.User

  # Permission definitions
  @role_permissions %{
    user: [:read_posts],
    moderator: [:read_posts, :write_posts, :moderate_content],
    admin: [:read_posts, :write_posts, :moderate_content, :read_users, :write_users]
  }

  def can?(user, permission) when is_atom(permission) do
    role_permissions = @role_permissions[user.role] || []
    permission in role_permissions or permission in user.permissions
  end

  def can?(user, permissions) when is_list(permissions) do
    Enum.all?(permissions, &can?(user, &1))
  end

  def can_any?(user, permissions) when is_list(permissions) do
    Enum.any?(permissions, &can?(user, &1))
  end

  def authorize(user, permission) do
    if can?(user, permission) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  def authorize!(user, permission) do
    case authorize(user, permission) do
      :ok -> :ok
      {:error, :unauthorized} -> raise "Unauthorized access"
    end
  end

  # Resource-based permissions
  def can_edit?(user, %{user_id: user_id}) when user.id == user_id, do: true
  def can_edit?(%{role: :admin}, _resource), do: true
  def can_edit?(_user, _resource), do: false

  def can_delete?(user, resource) do
    can_edit?(user, resource) or can?(user, :moderate_content)
  end
end
```

### Authorization Plugs

```elixir
defmodule MyAppWeb.Authorization do
  import Plug.Conn
  import Phoenix.Controller
  alias MyApp.Authorization

  def require_permission(conn, permission) do
    case Authorization.authorize(conn.assigns.current_user, permission) do
      :ok ->
        conn

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> put_view(html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON)
        |> render(:"403")
        |> halt()
    end
  end

  def require_role(conn, required_role) do
    user_role = conn.assigns.current_user.role

    if authorized_role?(user_role, required_role) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON)
      |> render(:"403")
      |> halt()
    end
  end

  def require_ownership_or_admin(conn, %{"id" => resource_id} = _params) do
    current_user = conn.assigns.current_user
    
    cond do
      current_user.role == :admin ->
        conn

      to_string(current_user.id) == resource_id ->
        conn

      true ->
        conn
        |> put_status(:forbidden)
        |> put_view(html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON)
        |> render(:"403")
        |> halt()
    end
  end

  defp authorized_role?(user_role, required_role) do
    role_hierarchy = [:user, :moderator, :admin]
    user_index = Enum.find_index(role_hierarchy, &(&1 == user_role)) || 0
    required_index = Enum.find_index(role_hierarchy, &(&1 == required_role)) || 0
    user_index >= required_index
  end
end
```

## Current User Patterns

### Context Functions with User Scoping

```elixir
defmodule MyApp.Blog do
  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Blog.Post
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

  def get_post!(id, user) do
    post = Repo.get!(Post, id)
    
    case can_view_post?(user, post) do
      true -> post
      false -> raise Ecto.NoResultsError
    end
  end

  def create_post(attrs, user) do
    %Post{}
    |> Post.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
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

  def delete_post(post, user) do
    with true <- Authorization.can_delete?(user, post) do
      Repo.delete(post)
    else
      false -> {:error, :forbidden}
    end
  end

  defp can_view_post?(user, post) do
    post.published or post.user_id == user.id or user.role in [:admin, :moderator]
  end
end
```

### LiveView Current User Helper

```elixir
defmodule MyAppWeb.LiveHelpers do
  import Phoenix.Component

  def assign_current_user(socket, user) do
    socket
    |> assign(:current_user, user)
    |> assign(:current_user_id, user.id)
    |> assign(:is_admin?, user.role == :admin)
    |> assign(:is_moderator?, user.role in [:admin, :moderator])
  end

  def current_user_can?(socket, permission) do
    MyApp.Authorization.can?(socket.assigns.current_user, permission)
  end

  def current_user_owns?(socket, resource) do
    socket.assigns.current_user.id == resource.user_id
  end
end
```

## Session Security

### Secure Session Configuration

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SALT")],
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

### Session Tracking and Management

```elixir
defmodule MyApp.Accounts.UserSession do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "user_sessions" do
    field :token_hash, :string
    field :user_agent, :string
    field :ip_address, :string
    field :expires_at, :naive_datetime
    belongs_to :user, MyApp.Accounts.User

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_agent, :ip_address, :expires_at])
    |> validate_required([:expires_at])
  end

  def active_sessions_query do
    from s in __MODULE__,
      where: s.expires_at > ^NaiveDateTime.utc_now()
  end
end
```

### Advanced Session Management

```elixir
defmodule MyApp.Accounts.SessionManager do
  alias MyApp.Repo
  alias MyApp.Accounts.UserSession
  import Ecto.Query

  def create_session(user, conn) do
    session_attrs = %{
      user_id: user.id,
      user_agent: get_user_agent(conn),
      ip_address: get_client_ip(conn),
      expires_at: session_expiry()
    }

    token = generate_session_token()
    token_hash = hash_token(token)

    case %UserSession{}
         |> UserSession.changeset(session_attrs)
         |> Ecto.Changeset.put_change(:token_hash, token_hash)
         |> Repo.insert() do
      {:ok, session} -> {:ok, session, token}
      error -> error
    end
  end

  def validate_session(token) do
    token_hash = hash_token(token)

    case Repo.one(
           from s in UserSession,
             where: s.token_hash == ^token_hash and s.expires_at > ^NaiveDateTime.utc_now(),
             preload: [:user]
         ) do
      nil -> {:error, :invalid_session}
      session -> {:ok, session.user}
    end
  end

  def revoke_session(token) do
    token_hash = hash_token(token)

    from(s in UserSession, where: s.token_hash == ^token_hash)
    |> Repo.delete_all()
  end

  def revoke_all_user_sessions(user_id) do
    from(s in UserSession, where: s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  def cleanup_expired_sessions do
    from(s in UserSession, where: s.expires_at <= ^NaiveDateTime.utc_now())
    |> Repo.delete_all()
  end

  defp generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16()
  end

  defp session_expiry do
    NaiveDateTime.utc_now() |> NaiveDateTime.add(86400, :second) # 24 hours
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent] -> String.slice(user_agent, 0, 255)
      _ -> "Unknown"
    end
  end

  defp get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip] -> List.first(String.split(ip, ",")) |> String.trim()
      _ -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end
end
```

## Testing Authentication & Authorization

### Test Support Module

```elixir
defmodule MyAppWeb.AuthTestHelpers do
  alias MyApp.Accounts
  alias MyAppWeb.Auth

  def register_and_login_user(conn) do
    user = user_fixture()
    login_user(conn, user)
  end

  def login_user(conn, user) do
    token = Auth.sign_user_token(user.id)
    
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  def login_admin(conn) do
    admin = user_fixture(%{role: :admin})
    login_user(conn, admin)
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "user#{System.unique_integer()}@example.com",
        name: "Test User",
        password: "hello world!"
      })
      |> Accounts.register_user()

    user
  end
end
```

### Controller Tests

```elixir
defmodule MyAppWeb.PostControllerTest do
  use MyAppWeb.ConnCase
  import MyAppWeb.AuthTestHelpers

  describe "GET /posts" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      assert redirected_to(conn) =~ "/login"
    end

    test "shows posts when authenticated", %{conn: conn} do
      conn = register_and_login_user(conn)
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "Posts"
    end
  end

  describe "POST /posts" do
    test "creates post when authorized", %{conn: conn} do
      user = user_fixture(%{permissions: [:write_posts]})
      conn = login_user(conn, user)
      
      conn = post(conn, ~p"/posts", post: valid_post_attrs())
      assert redirected_to(conn) =~ "/posts"
    end

    test "denies access without permission", %{conn: conn} do
      conn = register_and_login_user(conn)
      conn = post(conn, ~p"/posts", post: valid_post_attrs())
      assert response(conn, 403)
    end
  end
end
```

### LiveView Authentication Tests

```elixir
defmodule MyAppWeb.DashboardLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest
  import MyAppWeb.AuthTestHelpers

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/dashboard")
  end

  test "displays dashboard when authenticated", %{conn: conn} do
    conn = register_and_login_user(conn)
    {:ok, view, html} = live(conn, ~p"/dashboard")
    
    assert html =~ "Dashboard"
    assert has_element?(view, "#dashboard-content")
  end

  test "admin sections only visible to admins", %{conn: conn} do
    conn = login_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    
    assert has_element?(view, "#admin-panel")
  end
end
```

This comprehensive authentication and authorization recipe provides production-ready patterns for securing Phoenix applications with proper token management, session handling, LiveView integration, API authentication, and robust permission systems.