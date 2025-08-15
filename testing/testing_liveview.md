# Testing LiveView Recipe

## Introduction

Testing Phoenix LiveView applications requires understanding how to simulate user interactions, test real-time updates, and verify the behavior of stateful components. This recipe covers comprehensive testing strategies for LiveView applications, including component testing, event handling, and real-time feature testing.

## Basic LiveView Testing Setup

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

## Testing LiveView Components

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

  test "decrements counter", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/counter")
    
    # First increment to have a positive value
    lv |> element("button", "Increment") |> render_click()
    assert render(lv) =~ "Counter: 1"
    
    # Then decrement
    lv |> element("button", "Decrement") |> render_click()
    assert render(lv) =~ "Counter: 0"
    
    # Can go negative
    lv |> element("button", "Decrement") |> render_click()
    assert render(lv) =~ "Counter: -1"
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

## Testing Forms in LiveView

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
    assert has_element?(lv, "input[name='user[age]']")
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

  test "shows validation errors on submit", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/new")
    
    # Submit invalid data
    lv |> form("#user-form", user: @invalid_attrs) |> render_submit()
    
    # Should stay on form page with errors
    assert render(lv) =~ "Create User"
    assert render(lv) =~ "can't be blank"
    refute render(lv) =~ "User created successfully"
  end

  test "form is disabled during submission", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/new")
    
    # Start form submission
    form = form(lv, "#user-form", user: @valid_attrs)
    
    # Check that submit button is disabled during submission
    assert has_element?(lv, "button[type='submit']:not([disabled])")
    
    # After submission, should be redirected
    render_submit(form)
    assert_redirect(lv, ~p"/users/1")
  end
end
```

## Testing Real-time Updates

```elixir
defmodule MyAppWeb.ChatLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders chat room", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/chat/general")
    
    assert html =~ "Chat Room: general"
    assert has_element?(lv, "form[phx-submit='send_message']")
    assert has_element?(lv, "input[name='message']")
  end

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

  test "shows user presence", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/chat/general")
    
    # User should be shown as online
    assert render(lv) =~ user.name
    assert has_element?(lv, "[data-user-id='#{user.id}']")
  end

  test "handles user disconnection", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/chat/general")
    
    # User should be present
    assert render(lv) =~ user.name
    
    # Simulate disconnection
    close(lv)
    
    # Connect another user to verify the first user is no longer shown
    other_user = MyApp.AccountsFixtures.user_fixture()
    conn2 = log_in_user(conn, other_user)
    {:ok, lv2, _html} = live(conn2, ~p"/chat/general")
    
    # First user should no longer be shown as online
    refute render(lv2) =~ user.name
    assert render(lv2) =~ other_user.name
  end
end
```

## Testing File Uploads in LiveView

```elixir
defmodule MyAppWeb.UploadLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  @upload_config %{
    "avatar" => %{
      "content" => file_input_value("avatar.png", "image/png"),
      "last_modified" => 1_594_171_879_000,
      "name" => "avatar.png",
      "size" => 1396
    }
  }

  test "renders upload form", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/upload")
    
    assert html =~ "Upload Files"
    assert has_element?(lv, "form[phx-submit='save']")
    assert has_element?(lv, "input[type='file']")
  end

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
    
    # File should be listed
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

  test "validates file size", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/upload")
    
    # Try to upload file that's too large
    large_content = String.duplicate("a", 10_000_000)  # 10MB
    
    file_input = file_input(lv, "#upload-form", :avatar, [
      %{
        last_modified: 1_594_171_879_000,
        name: "large.png",
        content: large_content,
        size: byte_size(large_content),
        type: "image/png"
      }
    ])
    
    # Should show error for file too large
    assert render_upload(file_input, "large.png") =~ "too large"
  end

  test "cancels upload", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/upload")
    
    # Start upload
    file_input = file_input(lv, "#upload-form", :avatar, [
      %{
        last_modified: 1_594_171_879_000,
        name: "avatar.png",
        content: File.read!("test/fixtures/avatar.png"),
        size: 1396,
        type: "image/png"
      }
    ])
    
    # Cancel upload
    lv |> element("button[phx-click='cancel-upload']") |> render_click()
    
    # Upload should be cancelled
    refute render(lv) =~ "avatar.png"
    refute render(lv) =~ "100%"
  end
end
```

## Testing Live Navigation

```elixir
defmodule MyAppWeb.NavigationLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "navigates between pages", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard")
    
    # Click link to profile
    lv |> element("a", "Profile") |> render_click()
    
    # Should navigate to profile page
    assert_patch(lv, ~p"/profile")
    assert render(lv) =~ "User Profile"
    
    # Click link to settings
    lv |> element("a", "Settings") |> render_click()
    
    # Should navigate to settings page
    assert_patch(lv, ~p"/settings")
    assert render(lv) =~ "Settings"
  end

  test "handles live navigation with parameters", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/posts")
    
    # Click on a specific post
    post = MyApp.BlogFixtures.post_fixture()
    lv |> element("a[href='/posts/#{post.id}']") |> render_click()
    
    # Should navigate to post show page
    assert_patch(lv, ~p"/posts/#{post.id}")
    assert render(lv) =~ post.title
  end

  test "handles back navigation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/posts")
    
    # Navigate to specific post
    post = MyApp.BlogFixtures.post_fixture()
    lv |> element("a[href='/posts/#{post.id}']") |> render_click()
    assert_patch(lv, ~p"/posts/#{post.id}")
    
    # Use browser back button
    lv |> render_patch(~p"/posts")
    
    # Should be back on posts index
    assert render(lv) =~ "All Posts"
  end

  test "preserves state during navigation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard")
    
    # Set some state (like a search query)
    lv |> form("#search-form", search: %{query: "test"}) |> render_change()
    
    # Navigate to another page
    lv |> element("a", "Profile") |> render_click()
    assert_patch(lv, ~p"/profile")
    
    # Navigate back
    lv |> element("a", "Dashboard") |> render_click()
    assert_patch(lv, ~p"/dashboard")
    
    # State should be preserved
    assert render(lv) =~ "test"
  end
end
```

## Testing LiveView Hooks

```elixir
defmodule MyAppWeb.HooksLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "handles JavaScript hook events", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/interactive")
    
    # Simulate JavaScript hook sending event
    lv |> render_hook("window-resize", %{width: 1024, height: 768})
    
    # LiveView should handle the event
    assert render(lv) =~ "Screen: 1024x768"
  end

  test "handles client-side validation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/form")
    
    # Simulate client-side validation hook
    lv |> render_hook("validate-email", %{email: "invalid-email"})
    
    # Should show validation error
    assert render(lv) =~ "Invalid email format"
  end

  test "handles scroll events", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/infinite-scroll")
    
    # Simulate scroll to bottom
    lv |> render_hook("scroll-bottom", %{})
    
    # Should load more items
    assert render(lv) =~ "Loading more items..."
  end

  test "handles keyboard shortcuts", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/editor")
    
    # Simulate keyboard shortcut
    lv |> render_hook("keyboard-shortcut", %{key: "ctrl+s"})
    
    # Should save document
    assert render(lv) =~ "Document saved"
  end
end
```

## Testing LiveView Error Handling

```elixir
defmodule MyAppWeb.ErrorHandlingLiveTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  setup :register_and_log_in_user

  test "handles process crashes gracefully", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/crash-test")
    
    # Trigger an error that crashes the LiveView process
    assert_raise RuntimeError, fn ->
      lv |> element("button", "Crash") |> render_click()
    end
    
    # LiveView should restart
    {:ok, lv, _html} = live(conn, ~p"/crash-test")
    assert render(lv) =~ "Crash Test"
  end

  test "handles network errors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/network-test")
    
    # Simulate network timeout
    log = capture_log(fn ->
      lv |> element("button", "Network Call") |> render_click()
    end)
    
    assert log =~ "Network timeout"
    assert render(lv) =~ "Network error occurred"
  end

  test "handles validation errors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/validation-test")
    
    # Submit invalid data
    lv |> form("#test-form", data: %{invalid: "data"}) |> render_submit()
    
    # Should show error message
    assert render(lv) =~ "Invalid data provided"
    
    # Form should remain functional
    assert has_element?(lv, "form#test-form")
  end

  test "handles authorization errors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin")
    
    # Try to access admin function as regular user
    lv |> element("button", "Admin Action") |> render_click()
    
    # Should show access denied message
    assert render(lv) =~ "Access denied"
    
    # Should not crash the LiveView
    assert process_alive?(lv.pid)
  end
end
```

## Testing LiveView Components

```elixir
defmodule MyAppWeb.ComponentsTest do
  use MyAppWeb.LiveCase

  import Phoenix.LiveViewTest

  alias MyAppWeb.Components.Modal

  test "renders modal component" do
    html = render_component(Modal, %{
      id: "test-modal",
      title: "Test Modal",
      show: true
    })
    
    assert html =~ "Test Modal"
    assert html =~ "test-modal"
  end

  test "modal shows and hides" do
    {:ok, lv, _html} = live_isolated(MyAppWeb.ModalLive, %{})
    
    # Modal should be hidden initially
    refute render(lv) =~ "modal-content"
    
    # Show modal
    lv |> element("button", "Show Modal") |> render_click()
    assert render(lv) =~ "modal-content"
    
    # Hide modal
    lv |> element("button", "Close") |> render_click()
    refute render(lv) =~ "modal-content"
  end

  test "modal handles escape key" do
    {:ok, lv, _html} = live_isolated(MyAppWeb.ModalLive, %{})
    
    # Show modal
    lv |> element("button", "Show Modal") |> render_click()
    assert render(lv) =~ "modal-content"
    
    # Press escape key
    lv |> render_key("escape")
    refute render(lv) =~ "modal-content"
  end
end
```

## Testing Helpers

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
  Asserts that a LiveView contains specific text.
  """
  def assert_text(lv, text) do
    assert render(lv) =~ text
  end

  @doc """
  Asserts that a LiveView does not contain specific text.
  """
  def refute_text(lv, text) do
    refute render(lv) =~ text
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
  Waits for a specific element to appear.
  """
  def wait_for_element(lv, selector, timeout \\ 1000) do
    :timer.sleep(100)
    
    case has_element?(lv, selector) do
      true -> :ok
      false when timeout > 0 -> wait_for_element(lv, selector, timeout - 100)
      false -> raise "Element #{selector} did not appear within timeout"
    end
  end

  @doc """
  Simulates typing in an input field.
  """
  def type_in_field(lv, selector, text) do
    element = element(lv, selector)
    render_change(element, %{value: text})
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

## Tips & Best Practices

### LiveView Testing Structure
- Use `live/2` to mount LiveView pages
- Use `live_isolated/3` for testing individual components
- Use `render_component/2` for testing pure components
- Test both initial render and user interactions

### Event Testing
- Test all user interactions (clicks, form submissions, key presses)
- Test real-time updates and broadcasts
- Test error scenarios and edge cases
- Verify state changes after events

### Form Testing
- Test form validation on both change and submit
- Test both valid and invalid data scenarios
- Test form clearing and reset functionality
- Test conditional form fields

### File Upload Testing
- Test file type validation
- Test file size limits
- Test upload progress and cancellation
- Test multiple file uploads

### Performance Testing
- Test with large datasets
- Test concurrent user interactions
- Test memory usage during long-running tests
- Use `async: true` where appropriate

## References

- [Phoenix LiveView Testing](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)
- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/ExUnit.html)
- [Phoenix Testing Guide](https://hexdocs.pm/phoenix/testing.html)