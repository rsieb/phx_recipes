# Comprehensive Phoenix Testing Guide

---
Phoenix Version: 1.7+
Complexity: Beginner to Advanced
Time to Implement: Varies by test complexity (15 minutes for basic tests to several hours for comprehensive test suites)
Prerequisites: Phoenix architecture understanding, Ecto schemas/changesets, ExUnit basics, database transactions
---

## Prerequisites & Related Recipes

### Prerequisites
- Understanding of Phoenix application architecture (contexts, controllers, LiveView)
- Basic knowledge of Ecto schemas and changesets
- Familiarity with ExUnit testing framework
- Understanding of database transactions and test isolation

### Related Recipes
- **Foundation**: [Ecto Schema Basics](../data/ecto_schema_basics.md) - Testing schema validations and changesets
- **Business Logic**: [Phoenix Contexts](../core/phoenix_contexts.md) - Testing context functions and business logic
- **Web Layer**: [Phoenix LiveView Basics](../components/phoenix_liveview_basics.md) - Testing LiveView interactions and real-time features
- **TDD Workflow**: [Phoenix TDD Recipe](../workflows/phoenix_tdd_recipe.md) - Test-driven development methodology
- **Git Workflow**: [TDD Git Workflow](../workflows/tdd_git_workflow_recipe.md) - Integrating TDD with version control
- **Advanced Testing**: [Testing Real-time Features](../testing/testing_real_time_features.md) - Testing channels and presence

## Introduction

This guide provides a complete testing strategy for Phoenix applications, covering everything from basic unit tests to complex LiveView interactions. Phoenix's testing ecosystem is built on ExUnit and provides specialized tools for testing web applications, LiveView components, and real-time features.

## Table of Contents

1. [Testing Setup and Configuration](#testing-setup-and-configuration)
2. [Unit Testing (Schemas and Contexts)](#unit-testing-schemas-and-contexts)
3. [Controller Testing](#controller-testing)
4. [LiveView Testing](#liveview-testing)
5. [TDD Workflow and Best Practices](#tdd-workflow-and-best-practices)
6. [Testing Helpers and Utilities](#testing-helpers-and-utilities)
7. [Common Testing Patterns and Anti-patterns](#common-testing-patterns-and-anti-patterns)

## Testing Setup and Configuration

### Basic ConnCase Setup

```elixir
# test/support/conn_case.ex
defmodule MyAppWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
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
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = MyApp.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.
  """
  def log_in_user(conn, user) do
    token = MyApp.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
```

### LiveView Testing Setup

```elixir
# test/support/live_case.ex
defmodule MyAppWeb.LiveCase do
  @moduledoc """
  This module defines the test case to be used by LiveView tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint MyAppWeb.Endpoint

      use MyAppWeb, :verified_routes

      # Import conveniences for testing with LiveView
      import Phoenix.LiveViewTest
      import MyAppWeb.LiveCase
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users for LiveView tests.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = MyApp.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn` for LiveView tests.
  """
  def log_in_user(conn, user) do
    token = MyApp.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
```

### Test Factories with ExMachina

```elixir
# test/support/factory.ex
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def user_factory do
    %MyApp.Accounts.User{
      name: sequence(:name, &"User #{&1}"),
      email: sequence(:email, &"user#{&1}@example.com"),
      age: Enum.random(18..80)
    }
  end

  def admin_user_factory do
    struct!(user_factory(), %{role: :admin})
  end

  def post_factory do
    %MyApp.Blog.Post{
      title: sequence(:title, &"Post #{&1}"),
      content: "This is post content",
      published: true,
      user: build(:user)
    }
  end
end
```

## Unit Testing (Schemas and Contexts)

### Testing Ecto Schemas and Changesets

```elixir
defmodule MyApp.Accounts.UserTest do
  use MyApp.DataCase
  alias MyApp.Accounts.User

  describe "changeset/2" do
    test "changeset with valid attributes" do
      changeset = User.changeset(%User{}, %{
        name: "John",
        email: "john@example.com",
        age: 25
      })
      
      assert changeset.valid?
    end

    test "changeset requires name" do
      changeset = User.changeset(%User{}, %{email: "john@example.com"})
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "changeset validates email format" do
      changeset = User.changeset(%User{}, %{
        name: "John", 
        email: "invalid-email"
      })
      
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end

    test "changeset validates unique email" do
      insert(:user, email: "taken@example.com")
      
      changeset = User.changeset(%User{}, %{
        name: "John",
        email: "taken@example.com"
      })
      
      {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).email
    end
  end
end
```

### Testing Context Functions

```elixir
defmodule MyApp.AccountsTest do
  use MyApp.DataCase
  alias MyApp.Accounts

  describe "users" do
    test "list_users/0 returns all users" do
      user = insert(:user)
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = insert(:user)
      assert Accounts.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{name: "John", email: "john@example.com", age: 30}
      
      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.name == "John"
      assert user.email == "john@example.com"
      assert user.age == 30
    end

    test "create_user/1 with invalid data returns error changeset" do
      invalid_attrs = %{name: nil, email: "invalid-email"}
      
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = insert(:user)
      update_attrs = %{name: "Updated Name"}
      
      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.name == "Updated Name"
    end

    test "delete_user/1 deletes the user" do
      user = insert(:user)
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end
  end
end
```

## Controller Testing

### The Phoenix Way: Router-Based Testing

**❌ Wrong Approach** - Don't call controller functions directly:

```elixir
# DON'T DO THIS - Bypasses the entire Phoenix pipeline
test "should not call controller directly", %{conn: conn} do
  conn = 
    conn
    |> assign(:some_data, "value")
    |> MyAppWeb.SomeController.action(%{})  # Anti-pattern!
end
```

**✅ Correct Approach** - Test through the router:

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
end
```

### API Controller Testing

```elixir
defmodule MyAppWeb.API.PostControllerTest do
  use MyAppWeb.ConnCase, async: true

  import MyApp.BlogFixtures

  @create_attrs %{title: "Test Post", content: "Test content"}
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
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/posts", post: @invalid_attrs)
      
      response = json_response(conn, 422)
      assert response["errors"] != %{}
    end
  end

  defp generate_api_token(user) do
    Phoenix.Token.sign(MyAppWeb.Endpoint, "api_token", user.id)
  end
end
```

### Using bypass_through for Complex Scenarios

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
```

## LiveView Testing

### Basic LiveView Component Testing

```elixir
defmodule MyAppWeb.CounterLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  test "renders initial state", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/counter")
    
    assert html =~ "Counter: 0"
    assert has_element?(lv, "button", "Increment")
    assert has_element?(lv, "button", "Decrement")
  end

  test "increments counter", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/counter")
    
    # Click increment button
    lv |> element("button", "Increment") |> render_click()
    
    assert render(lv) =~ "Counter: 1"
    
    # Click multiple times
    lv |> element("button", "Increment") |> render_click()
    lv |> element("button", "Increment") |> render_click()
    
    assert render(lv) =~ "Counter: 3"
  end

  test "resets counter", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/counter")
    
    # Increment a few times
    lv |> element("button", "Increment") |> render_click()
    lv |> element("button", "Increment") |> render_click()
    assert render(lv) =~ "Counter: 2"
    
    # Reset
    lv |> element("button", "Reset") |> render_click()
    assert render(lv) =~ "Counter: 0"
  end
end
```

### Testing Forms in LiveView

```elixir
defmodule MyAppWeb.UserFormLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  @valid_attrs %{name: "John Doe", email: "john@example.com", age: 30}
  @invalid_attrs %{name: nil, email: "invalid", age: -5}

  test "renders form", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/users/new")
    
    assert html =~ "Create User"
    assert has_element?(lv, "form")
    assert has_element?(lv, "input[name='user[name]']")
    assert has_element?(lv, "input[name='user[email]']")
  end

  test "validates form on change", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/new")
    
    # Submit invalid data
    lv |> form("#user-form", user: @invalid_attrs) |> render_change()
    
    assert render(lv) =~ "can't be blank"
    assert render(lv) =~ "has invalid format"
    assert render(lv) =~ "must be greater than 0"
  end

  test "creates user with valid data", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/new")
    
    # Submit valid data
    lv |> form("#user-form", user: @valid_attrs) |> render_submit()
    
    # Should redirect to user show page
    assert_redirect(lv, ~p"/users/1")
    
    # Verify user was created
    user = MyApp.Accounts.get_user!(1)
    assert user.name == @valid_attrs.name
    assert user.email == @valid_attrs.email
  end
end
```

### Testing Real-time Updates

```elixir
defmodule MyAppWeb.ChatLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "sends and receives messages", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/chat/general")
    
    # Send a message
    lv
    |> form("#message-form", message: %{content: "Hello, world!"})
    |> render_submit()
    
    # Message should appear in chat
    assert render(lv) =~ "Hello, world!"
    assert render(lv) =~ user.name
    
    # Form should be cleared
    assert has_element?(lv, "input[name='message'][value='']")
  end

  test "broadcasts messages to other users", %{conn: conn} do
    # Create two users
    user1 = MyApp.AccountsFixtures.user_fixture()
    user2 = MyApp.AccountsFixtures.user_fixture()
    
    # Connect both users to the same chat room
    conn1 = log_in_user(conn, user1)
    conn2 = log_in_user(conn, user2)
    
    {:ok, lv1, _html} = live(conn1, ~p"/chat/general")
    {:ok, lv2, _html} = live(conn2, ~p"/chat/general")
    
    # User 1 sends a message
    lv1
    |> form("#message-form", message: %{content: "Hello from user 1"})
    |> render_submit()
    
    # Both users should see the message
    assert render(lv1) =~ "Hello from user 1"
    assert render(lv2) =~ "Hello from user 1"
    assert render(lv2) =~ user1.name
  end
end
```

### Testing File Uploads in LiveView

```elixir
defmodule MyAppWeb.UploadLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "uploads file successfully", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/upload")
    
    # Select file
    file_input = file_input(lv, "#upload-form", :avatar, [
      %{
        last_modified: 1_594_171_879_000,
        name: "avatar.png",
        content: File.read!("test/fixtures/avatar.png"),
        size: 1396,
        type: "image/png"
      }
    ])
    
    # File should be selected
    assert render_upload(file_input, "avatar.png") =~ "100%"
    
    # Submit form
    lv |> form("#upload-form") |> render_submit()
    
    # Should show success message
    assert render(lv) =~ "File uploaded successfully"
    assert render(lv) =~ "avatar.png"
  end

  test "validates file type", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/upload")
    
    # Try to upload invalid file type
    file_input = file_input(lv, "#upload-form", :avatar, [
      %{
        last_modified: 1_594_171_879_000,
        name: "document.pdf",
        content: "fake pdf content",
        size: 1000,
        type: "application/pdf"
      }
    ])
    
    # Should show error for invalid file type
    assert render_upload(file_input, "document.pdf") =~ "not accepted"
  end
end
```

## TDD Workflow and Best Practices

### The TDD Cycle in Phoenix

TDD follows a simple cycle:
1. **Red**: Write a failing test
2. **Green**: Write minimal code to make it pass
3. **Refactor**: Improve the code while keeping tests green

### Bottom-Up TDD: Start with Contexts

```elixir
# test/myapp/accounts_test.exs
defmodule MyApp.AccountsTest do
  use MyApp.DataCase
  alias MyApp.Accounts

  describe "users" do
    test "create_user/1 with valid data creates a user" do
      # RED: This will fail - function doesn't exist yet
      valid_attrs = %{name: "John", email: "john@example.com", age: 30}
      
      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.name == "John"
      assert user.email == "john@example.com"
      assert user.age == 30
    end

    test "create_user/1 with invalid data returns error changeset" do
      # RED: This will fail
      invalid_attrs = %{name: nil, email: "invalid-email"}
      
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(invalid_attrs)
    end
  end
end
```

**GREEN**: Implement minimal context functions:

```elixir
# lib/myapp/accounts.ex
defmodule MyApp.Accounts do
  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Accounts.User

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

**REFACTOR**: Improve while keeping tests green:

```elixir
def create_user(attrs \\ %{}) do
  attrs
  |> validate_required_fields()
  |> create_user_with_defaults()
  |> Repo.insert()
end
```

### Integration Testing

```elixir
# Test full user journeys
test "user registration and login flow", %{conn: conn} do
  # Visit registration page
  conn = get(conn, ~p"/users/register")
  assert html_response(conn, 200) =~ "Register"
  
  # Submit registration
  conn = post(conn, ~p"/users/register", %{
    user: %{
      name: "John Doe",
      email: "john@example.com",
      password: "secure_password123"
    }
  })
  
  # Should redirect to login
  assert redirected_to(conn) == ~p"/users/log_in"
  
  # Verify user was created
  user = Accounts.get_user_by_email("john@example.com")
  assert user.name == "John Doe"
  
  # Test login
  conn = post(conn, ~p"/users/log_in", %{
    user: %{
      email: "john@example.com",
      password: "secure_password123"
    }
  })
  
  assert redirected_to(conn) == ~p"/dashboard"
end
```

## Testing Helpers and Utilities

### ConnCase Helpers

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
  Asserts that a JSON response has specific structure.
  """
  def assert_json_response(conn, status, expected_keys) do
    response = json_response(conn, status)
    
    Enum.each(expected_keys, fn key ->
      assert Map.has_key?(response, key), "Expected key '#{key}' not found in response"
    end)
    
    response
  end
end
```

### LiveView Testing Helpers

```elixir
defmodule MyAppWeb.LiveTestHelpers do
  @moduledoc """
  Helper functions for LiveView testing.
  """

  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  @doc """
  Asserts that a LiveView element exists with specific attributes.
  """
  def assert_element(lv, selector, attrs \\ []) do
    assert has_element?(lv, selector)
    
    Enum.each(attrs, fn {attr, value} ->
      assert has_element?(lv, "#{selector}[#{attr}='#{value}']")
    end)
  end

  @doc """
  Fills out a form with given data.
  """
  def fill_form(lv, form_selector, data) do
    lv |> form(form_selector, data) |> render_change()
  end

  @doc """
  Submits a form with given data.
  """
  def submit_form(lv, form_selector, data) do
    lv |> form(form_selector, data) |> render_submit()
  end

  @doc """
  Creates a test file upload.
  """
  def test_file_upload(name, content_type \\ "text/plain", content \\ "test content") do
    %{
      last_modified: 1_594_171_879_000,
      name: name,
      content: content,
      size: byte_size(content),
      type: content_type
    }
  end
end
```

## Common Testing Patterns and Anti-patterns

### ✅ Good Testing Patterns

#### Test Structure Patterns

```elixir
# Use descriptive test names that explain intent
test "create_user/1 sends welcome email when user is created" do
  # Given - setup
  attrs = %{name: "John", email: "john@example.com"}
  
  # When - action
  assert {:ok, user} = Accounts.create_user(attrs)
  
  # Then - assertion
  assert_email_sent(fn email ->
    assert email.to == [{"John", "john@example.com"}]
    assert email.subject == "Welcome to our app!"
  end)
end

# Use setup for common data
setup do
  user = insert(:user)
  {:ok, user: user}
end

# Group related tests
describe "when user is authenticated" do
  setup [:authenticate_user]
  
  test "allows access to dashboard", %{conn: conn} do
    conn = get(conn, ~p"/dashboard")
    assert html_response(conn, 200)
  end
end
```

#### Test Boundaries

```elixir
# Test behavior, not implementation
test "create_user with valid attrs returns user" do
  attrs = %{name: "John", email: "john@example.com"}
  assert {:ok, %User{} = user} = Accounts.create_user(attrs)
  assert user.name == "John"
end

# Use async: true when possible
defmodule MyAppWeb.PostControllerTest do
  use MyAppWeb.ConnCase, async: true
  # Tests that don't need database isolation
end
```

### ❌ Testing Anti-patterns to Avoid

#### Don't Test Implementation Details

```elixir
# BAD - Testing internal implementation
test "create_user calls User.changeset" do
  expect(User, :changeset, fn _, _ -> %Ecto.Changeset{valid?: true} end)
  Accounts.create_user(%{})
end

# GOOD - Test behavior
test "create_user with valid attrs returns user" do
  attrs = %{name: "John", email: "john@example.com"}
  assert {:ok, %User{} = user} = Accounts.create_user(attrs)
  assert user.name == "John"
end
```

#### Don't Call Controllers Directly

```elixir
# BAD - Bypasses Phoenix pipeline
test "should not call controller directly", %{conn: conn} do
  conn = MyAppWeb.SomeController.action(conn, %{})  # Anti-pattern!
end

# GOOD - Test through router
test "proper Phoenix controller testing", %{conn: conn} do
  conn = get(conn, ~p"/some/path")
  assert html_response(conn, 200)
end
```

#### Don't Skip the Refactor Step

```elixir
# After getting tests to pass, always refactor
def create_user(attrs) do
  # GREEN: Minimal implementation that passes
  %User{name: attrs.name, email: attrs.email} |> Repo.insert()
end

# REFACTOR: Improve while keeping tests green
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

### Troubleshooting Common Issues

#### "No response was set/sent" Error

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

#### CSRF Token Issues

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

## TDD Workflow Commands

```bash
# Run tests continuously during development
mix test.watch

# Run specific test file
mix test test/myapp/accounts_test.exs

# Run specific test
mix test test/myapp/accounts_test.exs:25

# Run tests with coverage
mix test --cover

# Run only failed tests
mix test --failed
```

## Key Takeaways

### Testing Philosophy
1. **Test behavior, not implementation** - Focus on what, not how
2. **Always test through the router** - Use `get()`, `post()`, etc.
3. **Start with failing tests** - Write the test you wish you had
4. **Make it pass with minimal code** - Don't over-engineer initially
5. **Refactor relentlessly** - Improve design while keeping tests green

### Test Organization
- Use descriptive test names that explain the expected behavior
- Group related tests using `describe` blocks
- Use setup callbacks for common test data
- Keep tests focused on single behaviors

### Performance Testing
- Use `async: true` for tests that don't need database isolation
- Use fixtures for test data creation
- Mock external services in tests
- Consider using `setup_all` for expensive setup operations

### TDD Benefits
1. **Better Design**: Writing tests first forces you to think about API design
2. **Comprehensive Coverage**: Tests are written as requirements, not afterthoughts  
3. **Regression Safety**: Changes break tests immediately
4. **Documentation**: Tests serve as living documentation
5. **Confidence**: Refactoring is safer with comprehensive test coverage

Remember: TDD isn't about testing - it's about design. The tests are a byproduct of thinking through your API before implementing it! Controllers are part of a pipeline, not standalone functions, so always test through the full Phoenix request lifecycle.