# Phoenix Router and Pipelines Recipe

## Introduction

The Phoenix router is responsible for matching HTTP requests to controller actions and organizing them through pipelines. Pipelines are a way to group plugs that should be applied to specific routes, allowing you to organize middleware-like functionality such as authentication, authorization, and content type handling.

## Basic Router Setup

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Define pipelines
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Browser routes
  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/about", PageController, :about
    get "/contact", PageController, :contact
  end

  # API routes
  scope "/api", MyAppWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end
end
```

## Authentication Pipeline

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Import authentication plugs
  import MyAppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Authentication pipeline
  pipeline :require_authenticated_user do
    plug :require_authenticated_user
  end

  # Admin pipeline
  pipeline :require_admin do
    plug :require_authenticated_user
    plug :require_admin_user
  end

  # Public routes
  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
  end

  # Authenticated routes
  scope "/", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/dashboard", DashboardController, :index
    get "/profile", ProfileController, :show
    put "/profile", ProfileController, :update
    delete "/logout", SessionController, :delete
    
    resources "/posts", PostController
  end

  # Admin routes
  scope "/admin", MyAppWeb.Admin, as: :admin do
    pipe_through [:browser, :require_admin]

    get "/", DashboardController, :index
    resources "/users", UserController
    resources "/posts", PostController
  end

  # API routes with authentication
  scope "/api", MyAppWeb.API do
    pipe_through :api

    post "/auth/login", AuthController, :login
    post "/auth/register", AuthController, :register
  end

  scope "/api", MyAppWeb.API do
    pipe_through [:api, :require_authenticated_user]

    get "/profile", ProfileController, :show
    resources "/posts", PostController, except: [:new, :edit]
  end
end
```

## RESTful Resources

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # ... pipelines ...

  scope "/", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user]

    # Standard RESTful resource
    # Creates 7 routes: index, new, create, show, edit, update, delete
    resources "/posts", PostController

    # Resource with limited actions
    resources "/comments", CommentController, only: [:create, :update, :delete]

    # Resource excluding certain actions
    resources "/categories", CategoryController, except: [:delete]

    # Nested resources
    resources "/posts", PostController do
      resources "/comments", CommentController, only: [:create, :update, :delete]
    end

    # Resource with custom parameter name
    resources "/posts", PostController, param: "slug"

    # Resource with custom actions
    resources "/posts", PostController do
      member do
        post "/publish", PostController, :publish
        post "/unpublish", PostController, :unpublish
      end
      
      collection do
        get "/search", PostController, :search
      end
    end
  end
end
```

## Custom Pipelines for Different Content Types

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Standard pipelines
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # API with authentication
  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug :fetch_api_user
    plug :require_api_authentication
  end

  # File upload pipeline
  pipeline :upload do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :require_authenticated_user
    plug :validate_file_upload
  end

  # Webhook pipeline (no CSRF protection)
  pipeline :webhook do
    plug :accepts, ["json"]
    plug :validate_webhook_signature
  end

  # Admin panel with different layout
  pipeline :admin_layout do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :admin}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :require_admin_user
  end

  # Routes using different pipelines
  scope "/api/v1", MyAppWeb.API.V1 do
    pipe_through :authenticated_api
    
    resources "/users", UserController, except: [:new, :edit]
    resources "/posts", PostController, except: [:new, :edit]
  end

  scope "/upload", MyAppWeb do
    pipe_through :upload
    
    post "/avatar", UploadController, :avatar
    post "/document", UploadController, :document
  end

  scope "/webhooks", MyAppWeb do
    pipe_through :webhook
    
    post "/stripe", WebhookController, :stripe
    post "/github", WebhookController, :github
  end

  scope "/admin", MyAppWeb.Admin, as: :admin do
    pipe_through :admin_layout
    
    get "/", DashboardController, :index
    resources "/users", UserController
    resources "/settings", SettingController, singleton: true
  end
end
```

## Live Routes and LiveView

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import Phoenix.LiveView.Router

  # ... pipelines ...

  scope "/", MyAppWeb do
    pipe_through :browser

    # Traditional controller route
    get "/", PageController, :home

    # LiveView routes
    live "/dashboard", DashboardLive, :index
    live "/profile", ProfileLive, :show
    live "/profile/edit", ProfileLive, :edit
    
    # LiveView with parameters
    live "/posts/:id", PostLive, :show
    live "/posts/:id/edit", PostLive, :edit
    
    # LiveView with custom parameter constraints
    live "/posts/:slug", PostLive, :show, constraints: %{slug: ~r/[a-z0-9\-]+/}
  end

  scope "/admin", MyAppWeb.Admin, as: :admin do
    pipe_through [:browser, :require_admin]

    # Admin LiveView routes
    live "/", DashboardLive, :index
    live "/users", UserLive.Index, :index
    live "/users/new", UserLive.Index, :new
    live "/users/:id", UserLive.Show, :show
    live "/users/:id/edit", UserLive.Show, :edit
  end

  # LiveView with authentication check
  scope "/", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated, on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}] do
      live "/settings", SettingsLive, :index
      live "/billing", BillingLive, :index
    end
  end
end
```

## Error Handling and Forwarding

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # ... pipelines and routes ...

  # Forward to a specific plug/application
  scope "/dev" do
    pipe_through :browser
    
    if Mix.env() == :dev do
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Forward API documentation
  scope "/" do
    pipe_through :browser
    
    forward "/docs", PhoenixSwagger.Plug.SwaggerUI,
      otp_app: :my_app, 
      swagger_file: "swagger.json"
  end

  # Catch-all route for SPA applications
  scope "/", MyAppWeb do
    pipe_through :browser
    
    # This should be the last route
    get "/*path", PageController, :spa
  end
```

## Route Helpers and Path Generation

```elixir
# In your controllers, views, or templates
defmodule MyAppWeb.PostController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    posts = Blog.list_posts()
    render(conn, :index, posts: posts)
  end

  def create(conn, %{"post" => post_params}) do
    case Blog.create_post(post_params) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post created successfully.")
        |> redirect(to: ~p"/posts/#{post}")
        
      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end

# In templates using the ~p sigil
<%= link "View Post", to: ~p"/posts/#{@post}" %>
<%= link "Edit", to: ~p"/posts/#{@post}/edit" %>
<%= link "All Posts", to: ~p"/posts" %>

# Using route helpers in tests
defmodule MyAppWeb.PostControllerTest do
  use MyAppWeb.ConnCase

  test "GET /posts", %{conn: conn} do
    conn = get(conn, ~p"/posts")
    assert html_response(conn, 200) =~ "Posts"
  end

  test "POST /posts with valid data", %{conn: conn} do
    conn = post(conn, ~p"/posts", post: @valid_attrs)
    assert redirected_to(conn) == ~p"/posts/#{conn.assigns.post}"
  end
end
```

## Custom Plugs in Pipelines

```elixir
defmodule MyAppWeb.Plugs.RateLimiter do
  import Plug.Conn
  import Phoenix.Controller

  def init(options) do
    options
  end

  def call(conn, _opts) do
    case check_rate_limit(conn) do
      :ok -> conn
      :rate_limited -> 
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end

  defp check_rate_limit(_conn) do
    # Implement rate limiting logic
    :ok
  end
end

defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  
  pipeline :rate_limited_api do
    plug :accepts, ["json"]
    plug MyAppWeb.Plugs.RateLimiter
  end

  scope "/api", MyAppWeb.API do
    pipe_through :rate_limited_api
    
    # These routes will be rate limited
    post "/search", SearchController, :search
    post "/upload", UploadController, :create
  end
end
```

## Tips & Best Practices

### Pipeline Organization
- Keep pipelines focused on specific concerns (authentication, content type, etc.)
- Use descriptive names for custom pipelines
- Layer pipelines logically (auth after session, admin after auth)

### Route Organization
- Group related routes in the same scope
- Use consistent naming conventions for controllers and actions
- Place more specific routes before general ones

### Performance Considerations
- Use route constraints to avoid unnecessary controller calls
- Consider using `plug :accepts` early in pipelines to reject invalid content types
- Use caching plugs in pipelines for static content

### Security
- Always use CSRF protection for browser pipelines
- Implement proper authentication and authorization
- Use HTTPS in production with `force_ssl: true`
- Validate and sanitize route parameters

### Testing
- Test route pipelines independently
- Use route helpers in tests for maintainability
- Test both authenticated and unauthenticated access patterns

## References

- [Phoenix Routing Documentation](https://hexdocs.pm/phoenix/routing.html)
- [Phoenix.Router Documentation](https://hexdocs.pm/phoenix/Phoenix.Router.html)
- [Plug Documentation](https://hexdocs.pm/plug/Plug.html)
- [Phoenix LiveView Routing](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Router.html)