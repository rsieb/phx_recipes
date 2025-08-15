# Test-Driven Development in Phoenix Recipe

```elixir
Mix.install([
  {:phoenix, "~> 1.7"},
  {:phoenix_live_view, "~> 0.20"},
  {:ecto, "~> 3.10"},
  {:ex_machina, "~> 2.7"}
])
```

## What is Test-Driven Development (TDD)?

TDD is a development practice where you write tests **before** writing the implementation code. It follows a simple cycle:

1. **Red**: Write a failing test
2. **Green**: Write minimal code to make it pass
3. **Refactor**: Improve the code while keeping tests green

## Why TDD Works Well with Phoenix

**Built-in Testing Support**: Phoenix projects come with comprehensive test suites by default
**Fast Feedback**: `mix test` provides rapid feedback loops
**Clear Boundaries**: Phoenix's layered architecture (Context → Controller → View) makes testing natural
**Rich Testing Tools**: ExUnit, Phoenix.ConnTest, and LiveView testing provide excellent tooling

## The TDD Cycle in Phoenix

### Red → Green → Refactor

```elixir
# 1. RED: Write a failing test
test "creates user with valid attributes" do
  attrs = %{name: "John", email: "john@example.com"}
  
  assert {:ok, %User{} = user} = Accounts.create_user(attrs)
  assert user.name == "John"
  assert user.email == "john@example.com"
end

# 2. GREEN: Write minimal implementation
def create_user(attrs \\ %{}) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# 3. REFACTOR: Improve while keeping tests green
def create_user(attrs \\ %{}) do
  attrs
  |> validate_required_fields()
  |> create_user_with_defaults()
  |> Repo.insert()
end
```

## TDD Layers in Phoenix

### 1. Schema/Context Layer (Bottom-Up)

Start with the data layer - schemas and context functions:

```elixir
# test/myapp/accounts_test.exs
defmodule MyApp.AccountsTest do
  use MyApp.DataCase
  alias MyApp.Accounts

  describe "users" do
    test "list_users/0 returns all users" do
      # RED: This will fail - function doesn't exist yet
      user = insert(:user)
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      # RED: This will fail
      user = insert(:user)
      assert Accounts.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      # RED: This will fail
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

    test "update_user/2 with valid data updates the user" do
      # RED: This will fail
      user = insert(:user)
      update_attrs = %{name: "Updated Name"}
      
      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.name == "Updated Name"
    end

    test "delete_user/1 deletes the user" do
      # RED: This will fail
      user = insert(:user)
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
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

  def list_users do
    Repo.all(User)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end
end
```

### 2. Schema Validation (TDD Changesets)

```elixir
# Start with failing validation tests
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
```

**GREEN**: Implement the changeset:

```elixir
# lib/myapp/accounts/user.ex
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :age, :integer

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :age])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
```

### 3. Controller Layer (Outside-In)

Test the web interface through HTTP requests:

```elixir
# test/myapp_web/controllers/user_controller_test.exs
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase
  import MyApp.AccountsFixtures

  describe "index" do
    test "lists all users", %{conn: conn} do
      user = user_fixture()
      conn = get(conn, ~p"/users")
      
      assert html_response(conn, 200) =~ "Listing Users"
      assert html_response(conn, 200) =~ user.name
    end
  end

  describe "new user" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/users/new")
      assert html_response(conn, 200) =~ "New User"
    end
  end

  describe "create user" do
    test "redirects to show when data is valid", %{conn: conn} do
      create_attrs = %{name: "John", email: "john@example.com", age: 30}
      
      conn = post(conn, ~p"/users", user: create_attrs)
      
      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/users/#{id}"
      
      # Follow redirect and verify
      conn = get(conn, ~p"/users/#{id}")
      assert html_response(conn, 200) =~ "John"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/users", user: %{name: nil, email: "invalid"})
      
      assert html_response(conn, 200) =~ "New User"
      assert html_response(conn, 200) =~ "can&#39;t be blank"
    end
  end
end
```

### 4. LiveView TDD

Testing LiveView components and interactions:

```elixir
# test/myapp_web/live/user_live_test.exs
defmodule MyAppWeb.UserLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest
  import MyApp.AccountsFixtures

  describe "Index" do
    test "lists all users", %{conn: conn} do
      user = user_fixture()
      {:ok, _index_live, html} = live(conn, ~p"/users")

      assert html =~ "Listing Users"
      assert html =~ user.name
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert index_live |> element("a", "New User") |> render_click() =~
               "New User"

      assert_patch(index_live, ~p"/users/new")

      assert index_live
             |> form("#user-form", user: %{name: nil, email: "invalid"})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user-form", user: %{name: "John", email: "john@example.com"})
             |> render_submit()

      assert_patch(index_live, ~p"/users")

      html = render(index_live)
      assert html =~ "User created successfully"
      assert html =~ "John"
    end

    test "updates user in listing", %{conn: conn} do
      user = user_fixture()
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert index_live |> element("#users-#{user.id} a", "Edit") |> render_click() =~
               "Edit User"

      assert_patch(index_live, ~p"/users/#{user}/edit")

      assert index_live
             |> form("#user-form", user: %{name: "Updated Name"})
             |> render_submit()

      assert_patch(index_live, ~p"/users")

      html = render(index_live)
      assert html =~ "User updated successfully"
      assert html =~ "Updated Name"
    end

    test "deletes user in listing", %{conn: conn} do
      user = user_fixture()
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert index_live |> element("#users-#{user.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#users-#{user.id}")
    end
  end
end
```

## TDD Best Practices for Phoenix

### 1. Test Structure Patterns

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

### 2. Test Factories with ExMachina

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
end

# In tests
test "admin can delete users" do
  admin = insert(:admin_user)
  user = insert(:user)
  
  conn = 
    build_conn()
    |> log_in_user(admin)
    |> delete(~p"/users/#{user}")
  
  assert redirected_to(conn) == ~p"/users"
  assert_raise Ecto.NoResultsError, fn -> 
    Accounts.get_user!(user.id) 
  end
end
```

### 3. Integration Testing

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

### 4. Async Testing for Side Effects

```elixir
# Test background jobs and emails
test "create_user/1 enqueues welcome email job" do
  attrs = %{name: "John", email: "john@example.com"}
  
  assert {:ok, user} = Accounts.create_user(attrs)
  
  assert_enqueued(
    worker: MyApp.Workers.EmailWorker,
    args: %{user_id: user.id, type: "welcome"}
  )
end
```

## TDD Anti-Patterns to Avoid

### ❌ Don't Test Implementation Details

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

### ❌ Don't Write Tests After Implementation

```elixir
# This defeats the purpose of TDD
def create_user(attrs) do
  # Implementation written first
end

test "create_user works" do
  # Test written to match existing implementation
end
```

### ❌ Don't Skip the Refactor Step

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

## Benefits of TDD in Phoenix

1. **Better Design**: Writing tests first forces you to think about API design
2. **Comprehensive Coverage**: Tests are written as requirements, not afterthoughts  
3. **Regression Safety**: Changes break tests immediately
4. **Documentation**: Tests serve as living documentation
5. **Confidence**: Refactoring is safer with comprehensive test coverage

## When to Use TDD

**Great for:**
- Core business logic and context functions
- Complex algorithms and validations
- API endpoints and controller actions
- Critical user flows

**Consider alternatives for:**
- UI styling and layout
- Third-party integrations (use integration tests)
- Simple CRUD operations (scaffolding tests may suffice)

## Key Takeaways

1. **Start with failing tests** - Write the test you wish you had
2. **Make it pass with minimal code** - Don't over-engineer initially
3. **Refactor relentlessly** - Improve design while keeping tests green
4. **Test behavior, not implementation** - Focus on what, not how
5. **Use Phoenix's testing tools** - ConnTest, LiveViewTest, and ExUnit are powerful
6. **Layer your tests** - Unit tests for contexts, integration tests for controllers

Remember: TDD isn't about testing - it's about design. The tests are a byproduct of thinking through your API before implementing it!