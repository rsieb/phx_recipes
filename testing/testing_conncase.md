# Testing ConnCase Recipe

## Introduction

Phoenix's ConnCase provides a foundation for testing web controllers, plugs, and HTTP interactions. It sets up a connection struct, database sandboxing, and helpful testing utilities. This recipe covers how to effectively test Phoenix controllers, authentication, and web-specific functionality.

## Basic ConnCase Setup

```elixir
# test/support/conn_case.ex
defmodule MyAppWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MyAppWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint MyAppWeb.Endpoint

      use MyAppWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MyAppWeb.ConnCase
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = MyApp.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    token = MyApp.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
```

## Controller Testing

```elixir
defmodule MyAppWeb.PostControllerTest do
  use MyAppWeb.ConnCase

  import MyApp.BlogFixtures

  @create_attrs %{title: "Test Post", content: "Test content", published: true}
  @update_attrs %{title: "Updated Post", content: "Updated content", published: false}
  @invalid_attrs %{title: nil, content: nil, published: nil}

  setup :register_and_log_in_user

  describe "index" do
    test "lists all posts", %{conn: conn} do
      post = post_fixture()
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "Posts"
      assert html_response(conn, 200) =~ post.title
    end

    test "filters posts by search query", %{conn: conn} do
      post1 = post_fixture(title: "Elixir Guide")
      post2 = post_fixture(title: "Phoenix Tutorial")
      
      conn = get(conn, ~p"/posts?search=elixir")
      
      assert html_response(conn, 200) =~ post1.title
      refute html_response(conn, 200) =~ post2.title
    end

    test "paginates posts", %{conn: conn} do
      # Create 25 posts
      for i <- 1..25 do
        post_fixture(title: "Post #{i}")
      end
      
      # First page
      conn = get(conn, ~p"/posts?page=1")
      assert html_response(conn, 200) =~ "Post 1"
      
      # Second page
      conn = get(conn, ~p"/posts?page=2")
      assert html_response(conn, 200) =~ "Post 25"
    end
  end

  describe "show" do
    test "displays post", %{conn: conn} do
      post = post_fixture()
      conn = get(conn, ~p"/posts/#{post}")
      assert html_response(conn, 200) =~ post.title
    end

    test "returns 404 for non-existent post", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, ~p"/posts/999")
      end
    end
  end

  describe "new" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/posts/new")
      assert html_response(conn, 200) =~ "New Post"
    end
  end

  describe "create" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/posts", post: @create_attrs)
      
      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/posts/#{id}"
      
      conn = get(conn, ~p"/posts/#{id}")
      assert html_response(conn, 200) =~ @create_attrs.title
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/posts", post: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Post"
      assert html_response(conn, 200) =~ "can't be blank"
    end

    test "requires authentication", %{conn: conn} do
      conn = conn |> log_out_user()
      conn = post(conn, ~p"/posts", post: @create_attrs)
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "edit" do
    setup [:create_post]

    test "renders form for editing chosen post", %{conn: conn, post: post} do
      conn = get(conn, ~p"/posts/#{post}/edit")
      assert html_response(conn, 200) =~ "Edit Post"
    end
  end

  describe "update" do
    setup [:create_post]

    test "redirects when data is valid", %{conn: conn, post: post} do
      conn = put(conn, ~p"/posts/#{post}", post: @update_attrs)
      assert redirected_to(conn) == ~p"/posts/#{post}"
      
      conn = get(conn, ~p"/posts/#{post}")
      assert html_response(conn, 200) =~ @update_attrs.title
    end

    test "renders errors when data is invalid", %{conn: conn, post: post} do
      conn = put(conn, ~p"/posts/#{post}", post: @invalid_attrs)
      assert html_response(conn, 200) =~ "Edit Post"
    end

    test "only allows author to edit post", %{conn: conn, post: post} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)
      
      conn = put(conn, ~p"/posts/#{post}", post: @update_attrs)
      assert response(conn, 403)
    end
  end

  describe "delete" do
    setup [:create_post]

    test "deletes chosen post", %{conn: conn, post: post} do
      conn = delete(conn, ~p"/posts/#{post}")
      assert redirected_to(conn) == ~p"/posts"
      
      assert_error_sent 404, fn ->
        get(conn, ~p"/posts/#{post}")
      end
    end
  end

  defp create_post(_) do
    post = post_fixture()
    %{post: post}
  end

  defp log_out_user(conn) do
    conn
    |> Plug.Conn.configure_session(drop: true)
  end
end
```

## API Controller Testing

```elixir
defmodule MyAppWeb.API.PostControllerTest do
  use MyAppWeb.ConnCase, async: true

  import MyApp.BlogFixtures

  @create_attrs %{title: "Test Post", content: "Test content"}
  @update_attrs %{title: "Updated Post", content: "Updated content"}
  @invalid_attrs %{title: nil, content: nil}

  setup %{conn: conn} do
    user = user_fixture()
    token = generate_api_token(user)
    
    conn = 
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
    
    {:ok, conn: conn, user: user}
  end

  describe "index" do
    test "lists all posts", %{conn: conn} do
      post = post_fixture()
      conn = get(conn, ~p"/api/posts")
      
      assert json_response(conn, 200) == %{
        "data" => [
          %{
            "id" => post.id,
            "title" => post.title,
            "content" => post.content,
            "published" => post.published
          }
        ]
      }
    end

    test "supports pagination", %{conn: conn} do
      # Create 25 posts
      for i <- 1..25 do
        post_fixture(title: "Post #{i}")
      end
      
      conn = get(conn, ~p"/api/posts?page=1&per_page=10")
      response = json_response(conn, 200)
      
      assert length(response["data"]) == 10
      assert response["meta"]["total_pages"] == 3
      assert response["meta"]["current_page"] == 1
    end
  end

  describe "create" do
    test "renders post when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/posts", post: @create_attrs)
      
      response = json_response(conn, 201)
      assert response["data"]["id"]
      assert response["data"]["title"] == @create_attrs.title
      assert response["data"]["content"] == @create_attrs.content
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/posts", post: @invalid_attrs)
      
      response = json_response(conn, 422)
      assert response["errors"] != %{}
    end

    test "requires authentication", %{conn: conn} do
      conn = 
        conn
        |> delete_req_header("authorization")
        |> post(~p"/api/posts", post: @create_attrs)
      
      assert json_response(conn, 401)
    end
  end

  describe "show" do
    test "renders post", %{conn: conn} do
      post = post_fixture()
      conn = get(conn, ~p"/api/posts/#{post}")
      
      assert json_response(conn, 200) == %{
        "data" => %{
          "id" => post.id,
          "title" => post.title,
          "content" => post.content,
          "published" => post.published
        }
      }
    end

    test "returns 404 for non-existent post", %{conn: conn} do
      conn = get(conn, ~p"/api/posts/999")
      assert json_response(conn, 404)
    end
  end

  describe "update" do
    setup [:create_post]

    test "renders post when data is valid", %{conn: conn, post: post} do
      conn = put(conn, ~p"/api/posts/#{post}", post: @update_attrs)
      
      response = json_response(conn, 200)
      assert response["data"]["id"] == post.id
      assert response["data"]["title"] == @update_attrs.title
    end

    test "renders errors when data is invalid", %{conn: conn, post: post} do
      conn = put(conn, ~p"/api/posts/#{post}", post: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete" do
    setup [:create_post]

    test "deletes chosen post", %{conn: conn, post: post} do
      conn = delete(conn, ~p"/api/posts/#{post}")
      assert response(conn, 204)
      
      conn = get(conn, ~p"/api/posts/#{post}")
      assert json_response(conn, 404)
    end
  end

  defp create_post(_) do
    post = post_fixture()
    %{post: post}
  end

  defp generate_api_token(user) do
    Phoenix.Token.sign(MyAppWeb.Endpoint, "api_token", user.id)
  end
end
```

## Authentication Testing

```elixir
defmodule MyAppWeb.UserAuthTest do
  use MyAppWeb.ConnCase, async: true

  alias MyApp.Accounts
  import MyApp.AccountsFixtures

  @remember_me_cookie "_my_app_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, MyAppWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn = MyAppWeb.UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, user: user} do
      conn = conn |> put_session(:to_be_removed, "value") |> MyAppWeb.UserAuth.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> MyAppWeb.UserAuth.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> MyAppWeb.UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> MyAppWeb.UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)
    end
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      conn = conn |> put_session(:user_token, user_token) |> MyAppWeb.UserAuth.fetch_current_user([])
      assert conn.assigns.current_user.id == user.id
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> MyAppWeb.UserAuth.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> MyAppWeb.UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
      assert get_session(conn, :user_token) == user_token
    end

    test "does not authenticate if data is missing", %{conn: conn} do
      _ = Accounts.generate_user_session_token(user_fixture())
      conn = MyAppWeb.UserAuth.fetch_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end
  end

  describe "on_mount: mount_current_user" do
    test "assigns current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        MyAppWeb.UserAuth.on_mount(:mount_current_user, %{}, session, %Phoenix.LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "assigns nil to current_user assign if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        MyAppWeb.UserAuth.on_mount(:mount_current_user, %{}, session, %Phoenix.LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount: ensure_authenticated" do
    test "authenticates current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        MyAppWeb.UserAuth.on_mount(:ensure_authenticated, %{}, session, %Phoenix.LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "redirects to login page if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %Phoenix.LiveView.Socket{
        endpoint: MyAppWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = MyAppWeb.UserAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert Phoenix.Flash.get(updated_socket.assigns.flash, :error) =~ "You must log in"
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> MyAppWeb.UserAuth.require_authenticated_user([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "You must log in"
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> MyAppWeb.UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> MyAppWeb.UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> MyAppWeb.UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> MyAppWeb.UserAuth.require_authenticated_user([])
      refute conn.halted
    end
  end
end
```

## Plug Testing

```elixir
defmodule MyAppWeb.Plugs.RateLimiterTest do
  use MyAppWeb.ConnCase, async: true

  alias MyAppWeb.Plugs.RateLimiter

  setup %{conn: conn} do
    conn = conn |> Plug.Conn.put_req_header("x-forwarded-for", "127.0.0.1")
    {:ok, conn: conn}
  end

  describe "call/2" do
    test "allows requests under limit", %{conn: conn} do
      opts = RateLimiter.init(max_requests: 10, window_seconds: 60)
      
      conn = RateLimiter.call(conn, opts)
      
      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") == ["10"]
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["9"]
    end

    test "blocks requests over limit", %{conn: conn} do
      opts = RateLimiter.init(max_requests: 1, window_seconds: 60)
      
      # First request should pass
      conn1 = RateLimiter.call(conn, opts)
      refute conn1.halted
      
      # Second request should be blocked
      conn2 = RateLimiter.call(conn, opts)
      assert conn2.halted
      assert conn2.status == 429
      assert get_resp_header(conn2, "x-ratelimit-remaining") == ["0"]
    end

    test "uses IP address for rate limiting", %{conn: conn} do
      opts = RateLimiter.init(max_requests: 1, window_seconds: 60)
      
      # Request from first IP
      conn1 = conn |> Plug.Conn.put_req_header("x-forwarded-for", "1.1.1.1")
      conn1 = RateLimiter.call(conn1, opts)
      refute conn1.halted
      
      # Request from second IP should not be affected
      conn2 = conn |> Plug.Conn.put_req_header("x-forwarded-for", "2.2.2.2")
      conn2 = RateLimiter.call(conn2, opts)
      refute conn2.halted
    end

    test "includes reset time in headers", %{conn: conn} do
      opts = RateLimiter.init(max_requests: 1, window_seconds: 60)
      
      conn = RateLimiter.call(conn, opts)
      
      reset_time = get_resp_header(conn, "x-ratelimit-reset") |> List.first()
      assert reset_time != nil
      assert String.to_integer(reset_time) > System.system_time(:second)
    end
  end
end
```

## File Upload Testing

```elixir
defmodule MyAppWeb.UploadControllerTest do
  use MyAppWeb.ConnCase, async: true

  @upload %Plug.Upload{
    content_type: "image/png",
    filename: "test.png",
    path: "test/fixtures/files/test.png"
  }

  @large_upload %Plug.Upload{
    content_type: "image/png",
    filename: "large.png",
    path: "test/fixtures/files/large.png"
  }

  setup :register_and_log_in_user

  describe "create upload" do
    test "uploads valid file", %{conn: conn} do
      conn = post(conn, ~p"/uploads", %{"upload" => %{"file" => @upload}})
      
      assert redirected_to(conn) =~ ~p"/uploads"
      assert get_flash(conn, :info) =~ "File uploaded successfully"
    end

    test "rejects invalid file type", %{conn: conn} do
      invalid_upload = %{@upload | content_type: "text/plain", filename: "test.txt"}
      
      conn = post(conn, ~p"/uploads", %{"upload" => %{"file" => invalid_upload}})
      
      assert html_response(conn, 200) =~ "Invalid file type"
    end

    test "rejects file too large", %{conn: conn} do
      conn = post(conn, ~p"/uploads", %{"upload" => %{"file" => @large_upload}})
      
      assert html_response(conn, 200) =~ "File is too large"
    end

    test "handles missing file", %{conn: conn} do
      conn = post(conn, ~p"/uploads", %{"upload" => %{"file" => nil}})
      
      assert html_response(conn, 200) =~ "Please select a file"
    end
  end

  describe "show upload" do
    test "displays upload for owner", %{conn: conn, user: user} do
      upload = create_upload(user)
      
      conn = get(conn, ~p"/uploads/#{upload}")
      
      assert html_response(conn, 200) =~ upload.filename
    end

    test "denies access to other users' uploads", %{conn: conn} do
      other_user = user_fixture()
      upload = create_upload(other_user)
      
      conn = get(conn, ~p"/uploads/#{upload}")
      
      assert response(conn, 403)
    end
  end

  describe "download upload" do
    test "serves file for owner", %{conn: conn, user: user} do
      upload = create_upload(user)
      
      conn = get(conn, ~p"/uploads/#{upload}/download")
      
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert get_resp_header(conn, "content-disposition") == ["attachment; filename=\"#{upload.filename}\""]
    end

    test "denies download to other users", %{conn: conn} do
      other_user = user_fixture()
      upload = create_upload(other_user)
      
      conn = get(conn, ~p"/uploads/#{upload}/download")
      
      assert response(conn, 403)
    end
  end

  defp create_upload(user) do
    {:ok, upload} = MyApp.Files.create_upload(%{
      filename: "test.png",
      content_type: "image/png",
      size: 1024,
      user_id: user.id
    })
    upload
  end
end
```

## Testing Helpers

```elixir
# test/support/test_helpers.ex
defmodule MyAppWeb.TestHelpers do
  @moduledoc """
  Helper functions for testing web functionality.
  """

  import Phoenix.ConnTest
  import ExUnit.Assertions

  @doc """
  Asserts that a form has specific errors.
  """
  def assert_form_errors(conn, form_selector, field, expected_errors) do
    form = conn |> html_response(200) |> Floki.find(form_selector)
    
    errors = 
      form
      |> Floki.find("[data-field='#{field}'] .error")
      |> Floki.text()
    
    Enum.each(expected_errors, fn error ->
      assert errors =~ error
    end)
  end

  @doc """
  Asserts that a flash message is present.
  """
  def assert_flash(conn, type, message) do
    flash = Phoenix.Flash.get(conn.assigns.flash, type)
    assert flash =~ message
  end

  @doc """
  Asserts that a redirect occurs with a specific status.
  """
  def assert_redirect(conn, expected_path, status \\ 302) do
    assert conn.status == status
    assert redirected_to(conn) == expected_path
  end

  @doc """
  Creates a mock upload for testing.
  """
  def mock_upload(filename, content_type \\ "image/png", size \\ 1024) do
    %Plug.Upload{
      content_type: content_type,
      filename: filename,
      path: create_temp_file(size)
    }
  end

  @doc """
  Asserts that a JSON response has specific structure.
  """
  def assert_json_response(conn, status, expected_keys) do
    response = json_response(conn, status)
    
    Enum.each(expected_keys, fn key ->
      assert Map.has_key?(response, key), "Expected key '#{key}' not found in response"
    end)
    
    response
  end

  @doc """
  Asserts that pagination information is correct.
  """
  def assert_pagination(response, page, per_page, total) do
    assert response["meta"]["current_page"] == page
    assert response["meta"]["per_page"] == per_page
    assert response["meta"]["total"] == total
    assert response["meta"]["total_pages"] == ceil(total / per_page)
  end

  defp create_temp_file(size) do
    {:ok, path} = Plug.Upload.random_file("test")
    File.write!(path, String.duplicate("a", size))
    path
  end
end
```

## Tips & Best Practices

### Test Organization
- Use descriptive test names that explain the expected behavior
- Group related tests using `describe` blocks
- Use setup callbacks for common test data
- Keep tests focused on single behaviors

### Authentication Testing
- Test both authenticated and unauthenticated scenarios
- Test authorization (can this user access this resource?)
- Test session management and token handling
- Test logout and session cleanup

### Controller Testing
- Test all controller actions (index, show, create, update, delete)
- Test both success and failure scenarios
- Test parameter validation and error handling
- Test redirects and response formats

### API Testing
- Test JSON response formats
- Test API authentication and authorization
- Test pagination and filtering
- Test error response formats

### Performance Testing
- Use `async: true` for tests that don't need database isolation
- Use fixtures for test data creation
- Mock external services in tests
- Consider using `setup_all` for expensive setup operations

## References

- [Phoenix.ConnTest Documentation](https://hexdocs.pm/phoenix/Phoenix.ConnTest.html)
- [Phoenix Testing Guide](https://hexdocs.pm/phoenix/testing.html)
- [Plug.Test Documentation](https://hexdocs.pm/plug/Plug.Test.html)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/ExUnit.html)