# Phoenix Router-Based Testing Recipe

```elixir
Mix.install([
  {:phoenix, "~> 1.7"},
  {:phoenix_live_view, "~> 0.20"},
  {:plug_cowboy, "~> 2.5"}
])
```

## The Problem: Direct Controller Testing Anti-Pattern

❌ **Wrong Approach** - Calling controller functions directly:

```elixir
# DON'T DO THIS - Bypasses the entire Phoenix pipeline
test "should not call controller directly", %{conn: conn} do
  conn = 
    conn
    |> assign(:some_data, "value")
    |> MyAppWeb.SomeController.action(%{})  # Anti-pattern!
  
  # This misses router plugs, CSRF protection, authentication, etc.
end
```

**Why this fails:**
- Bypasses router pipeline and plugs
- Controllers expect properly processed `%Plug.Conn{}`
- No realistic test of actual request flow
- Missing CSRF, authentication, and other protections

## ✅ The Phoenix Way: Router-Based Testing

### Basic HTTP Request Testing

```elixir
test "proper Phoenix controller testing", %{conn: conn} do
  # Test through the router - this is the correct approach
  conn = get(conn, ~p"/some/path")
  
  assert html_response(conn, 200)
  assert conn.assigns.page_title == "Expected Title"
end

test "POST requests with params", %{conn: conn} do
  params = %{user: %{name: "John", email: "john@example.com"}}
  
  conn = post(conn, ~p"/users", params)
  
  assert redirected_to(conn) == ~p"/users/#{conn.assigns.user.id}"
  assert get_flash(conn, :info) == "User created successfully"
end
```

### Authentication Testing

```elixir
test "requires authentication", %{conn: conn} do
  # Test that unauthenticated requests are redirected
  conn = get(conn, ~p"/dashboard")
  
  assert redirected_to(conn) == ~p"/login"
  assert get_flash(conn, :error) == "You must log in to access this page"
end

test "authenticated user access", %{conn: conn} do
  user = insert(:user)
  
  conn = 
    conn
    |> log_in_user(user)  # Helper function to simulate login
    |> get(~p"/dashboard")
  
  assert html_response(conn, 200)
  assert conn.assigns.current_user.id == user.id
end
```

## Using `bypass_through` for Complex Scenarios

When you need to set up specific assigns or session data before hitting a route:

```elixir
test "OAuth callback with success", %{conn: conn} do
  auth = %Ueberauth.Auth{
    provider: :google,
    info: %{email: "user@example.com", name: "Test User"}
  }
  
  conn = 
    conn
    |> bypass_through(MyAppWeb.Router, :browser)  # Key: specify the pipeline
    |> get(~p"/auth/google")  # Initial request to set up session
    |> recycle()  # Preserve session
    |> assign(:ueberauth_auth, auth)  # Set up the auth struct
    |> get(~p"/auth/google/callback")  # The actual callback
  
  assert redirected_to(conn) == ~p"/dashboard"
  assert get_flash(conn, :info) == "Successfully signed in!"
end

test "OAuth callback with return_to", %{conn: conn} do
  auth = %Ueberauth.Auth{
    provider: :google,
    info: %{email: "user@example.com", name: "Test User"}
  }
  
  conn = 
    conn
    |> bypass_through(MyAppWeb.Router, :browser)
    |> get(~p"/auth/google")
    |> put_session(:return_to, "/profile")  # Set return URL
    |> assign(:ueberauth_auth, auth)
    |> get(~p"/auth/google/callback")
  
  assert redirected_to(conn) == "/profile"  # Should redirect to return_to
end
```

## Testing Different Response Types

### JSON API Testing

```elixir
test "JSON API endpoint", %{conn: conn} do
  conn = 
    conn
    |> put_req_header("accept", "application/json")
    |> get(~p"/api/users")
  
  assert json_response(conn, 200)
  assert %{"users" => users} = json_response(conn, 200)
  assert is_list(users)
end

test "JSON API with authentication", %{conn: conn} do
  user = insert(:user)
  token = generate_token(user)
  
  conn = 
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
    |> post(~p"/api/posts", %{post: %{title: "Test", content: "Content"}})
  
  assert %{"post" => post} = json_response(conn, 201)
  assert post["title"] == "Test"
end
```

### File Upload Testing

```elixir
test "file upload through router", %{conn: conn} do
  upload = %Plug.Upload{
    path: "test/fixtures/test_file.csv",
    filename: "test_file.csv",
    content_type: "text/csv"
  }
  
  conn = 
    conn
    |> log_in_user(insert(:user))
    |> post(~p"/uploads", %{file: upload})
  
  assert redirected_to(conn) == ~p"/uploads"
  assert get_flash(conn, :info) == "File uploaded successfully"
end
```

## Common Patterns and Helpers

### Setup Helper Functions

```elixir
defmodule MyAppWeb.ConnCase do
  use ExUnit.CaseTemplate
  
  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import MyAppWeb.ConnCase
      
      alias MyAppWeb.Router.Helpers, as: Routes
      
      @endpoint MyAppWeb.Endpoint
    end
  end
  
  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
  
  # Helper to simulate user login
  def log_in_user(conn, user) do
    token = MyApp.Accounts.generate_user_session_token(user)
    
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
```

### Testing Form Submissions

```elixir
test "form submission with validation errors", %{conn: conn} do
  conn = post(conn, ~p"/users", %{user: %{email: "invalid"}})
  
  assert html_response(conn, 200)  # Re-renders form with errors
  assert conn.assigns.changeset.errors[:email]
  assert get_flash(conn, :error) == "Please fix the errors below"
end

test "successful form submission", %{conn: conn} do
  valid_params = %{user: %{name: "John", email: "john@example.com"}}
  
  conn = post(conn, ~p"/users", valid_params)
  
  assert redirected_to(conn) =~ ~p"/users/"
  assert get_flash(conn, :info) == "User created successfully"
end
```

## Troubleshooting Common Issues

### "No response was set/sent" Error

This usually means the controller action crashed before sending a response:

```elixir
test "debug controller crashes", %{conn: conn} do
  # Add error handling to see what's happening
  assert_error_sent 500, fn ->
    get(conn, ~p"/some/problematic/path")
  end
  
  # Or catch the error
  assert_raise RuntimeError, fn ->
    get(conn, ~p"/some/path")
  end
end
```

### Missing Session/Flash Setup

```elixir
# If you need session but not going through full pipeline
conn = 
  conn
  |> Plug.Test.init_test_session(%{})
  |> Phoenix.Controller.fetch_flash()
  |> get(~p"/some/path")
```

### CSRF Token Issues

```elixir
test "POST with CSRF protection", %{conn: conn} do
  # Get CSRF token first
  form_conn = get(conn, ~p"/users/new")
  csrf_token = form_conn.assigns.csrf_token
  
  # Include it in POST
  conn = post(conn, ~p"/users", %{
    "_csrf_token" => csrf_token,
    user: %{name: "John"}
  })
  
  assert redirected_to(conn) =~ ~p"/users/"
end
```

## Key Takeaways

1. **Always test through the router** - Use `get()`, `post()`, etc.
2. **Use `bypass_through` only when necessary** - For setting up specific assigns/session
3. **Specify the pipeline** - `bypass_through(Router, :browser)` not just `bypass_through()`
4. **Test the full request lifecycle** - Don't shortcut the Phoenix pipeline
5. **Use helper functions** - Create reusable login, setup functions
6. **Test realistic scenarios** - Include headers, CSRF tokens, authentication

Remember: Controllers are part of a pipeline, not standalone functions!