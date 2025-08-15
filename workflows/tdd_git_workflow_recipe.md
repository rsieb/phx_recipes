# TDD Git Workflow Recipe - Feature Branch + Test-First Development

```bash
# Prerequisites: Ensure you have git configured
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## The Workflow Overview

This workflow enforces Test-Driven Development through git commits, creating a clear history of test-first development:

1. **Start Task** → Create feature branch
2. **Write Tests** → Commit failing tests
3. **Implement** → Commit when each test passes
4. **Complete** → Merge to main, push, cleanup

## Step-by-Step Workflow

### 1. Start a New Task

```bash
# Ensure you're on main and up-to-date
git checkout main
git pull origin main

# Create feature branch from main
git checkout -b feature/user-registration

# Alternative naming conventions:
# git checkout -b feature/add-user-validation
# git checkout -b bugfix/fix-email-validation
# git checkout -b refactor/extract-user-service
```

### 2. Write All Tests for Task Requirements

Write comprehensive tests that describe what you want to implement:

```bash
# Example: Adding user registration feature
# Write tests in appropriate files:
# - test/myapp/accounts_test.exs (context tests)
# - test/myapp_web/controllers/user_controller_test.exs (controller tests)
# - test/myapp_web/live/user_live_test.exs (LiveView tests if applicable)

# Run tests to verify they fail
mix test
```

**Example Test Suite for User Registration:**

```elixir
# test/myapp/accounts_test.exs
describe "register_user/1" do
  test "creates user with valid attributes" do
    attrs = %{
      name: "John Doe",
      email: "john@example.com", 
      password: "secure_password123"
    }
    
    assert {:ok, %User{} = user} = Accounts.register_user(attrs)
    assert user.name == "John Doe"
    assert user.email == "john@example.com"
    assert Bcrypt.verify_pass("secure_password123", user.password_hash)
  end

  test "returns error with invalid email" do
    attrs = %{name: "John", email: "invalid-email", password: "password123"}
    assert {:error, %Ecto.Changeset{}} = Accounts.register_user(attrs)
  end

  test "returns error with short password" do
    attrs = %{name: "John", email: "john@example.com", password: "123"}
    assert {:error, %Ecto.Changeset{}} = Accounts.register_user(attrs)
  end
end

# test/myapp_web/controllers/user_controller_test.exs
describe "POST /users/register" do
  test "redirects when data is valid", %{conn: conn} do
    valid_attrs = %{
      name: "John Doe",
      email: "john@example.com",
      password: "secure_password123"
    }
    
    conn = post(conn, ~p"/users/register", user: valid_attrs)
    
    assert redirected_to(conn) == ~p"/dashboard"
    assert get_flash(conn, :info) == "Registration successful!"
  end

  test "renders errors when data is invalid", %{conn: conn} do
    invalid_attrs = %{name: "", email: "invalid", password: "123"}
    
    conn = post(conn, ~p"/users/register", user: invalid_attrs)
    
    assert html_response(conn, 200) =~ "Register"
    assert html_response(conn, 200) =~ "can't be blank"
  end
end
```

### 3. Commit the Failing Tests

```bash
# Add all new test files
git add test/

# Commit with descriptive message
git commit -m "Add tests for user registration feature

- Test valid user creation in Accounts.register_user/1  
- Test email validation
- Test password validation
- Test registration controller endpoints
- All tests currently failing (TDD red phase)"

# Verify commit
git log --oneline -1
```

### 4. Implement Test by Test

Now implement just enough code to make each test pass, committing after each success:

#### Implementation Cycle 1: Basic Schema

```elixir
# Create/update lib/myapp/accounts/user.ex
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 6)
    |> unique_constraint(:email)
    |> hash_password()
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)
    
    if password && changeset.valid? do
      put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    else
      changeset
    end
  end
end
```

```bash
# Test specific function
mix test test/myapp/accounts_test.exs -v

# If basic schema tests pass, commit
git add lib/myapp/accounts/user.ex
git commit -m "Add User schema with password hashing

- Implements basic User schema
- Adds email validation  
- Adds password length validation
- Adds password hashing with Bcrypt
- Passes: basic user creation and validation tests"
```

#### Implementation Cycle 2: Context Function

```elixir
# Add to lib/myapp/accounts.ex
def register_user(attrs \\ %{}) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

```bash
# Test the context function
mix test test/myapp/accounts_test.exs::MyApp.AccountsTest -v

# If context tests pass, commit
git add lib/myapp/accounts.ex
git commit -m "Add Accounts.register_user/1 function

- Implements user registration in context layer
- Passes: Accounts.register_user/1 tests"
```

#### Implementation Cycle 3: Migration

```bash
# Generate and run migration
mix ecto.gen.migration create_users
```

```elixir
# Edit migration file
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end
```

```bash
# Run migration and test
mix ecto.migrate
mix test test/myapp/accounts_test.exs -v

# Commit migration
git add priv/repo/migrations/
git commit -m "Add users table migration

- Creates users table with name, email, password_hash
- Adds unique constraint on email
- Database tests now pass"
```

#### Implementation Cycle 4: Controller

```elixir
# Add to lib/myapp_web/controllers/user_controller.ex
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias MyApp.Accounts

  def register(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Registration successful!")
        |> redirect(to: ~p"/dashboard")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :register, changeset: changeset)
    end
  end

  def new(conn, _params) do
    changeset = Accounts.change_user(%User{})
    render(conn, :register, changeset: changeset)
  end
end
```

```bash
# Test controller
mix test test/myapp_web/controllers/user_controller_test.exs -v

# Commit controller
git add lib/myapp_web/controllers/user_controller.ex
git commit -m "Add user registration controller

- Implements registration endpoint
- Handles success and error cases
- Passes: controller registration tests"
```

#### Implementation Cycle 5: Routes and Templates

```elixir
# Add to lib/myapp_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser
  
  get "/users/register", UserController, :new
  post "/users/register", UserController, :register
end
```

```heex
<!-- lib/myapp_web/controllers/user_html/register.html.heex -->
<div class="mx-auto max-w-sm">
  <h1 class="text-2xl font-bold">Register</h1>
  
  <.simple_form for={@changeset} action={~p"/users/register"}>
    <.input field={@changeset[:name]} label="Name" />
    <.input field={@changeset[:email]} type="email" label="Email" />
    <.input field={@changeset[:password]} type="password" label="Password" />
    
    <:actions>
      <.button>Register</.button>
    </:actions>
  </.simple_form>
</div>
```

```bash
# Run all tests
mix test

# If all tests pass, commit
git add lib/myapp_web/router.ex lib/myapp_web/controllers/user_html/
git commit -m "Add registration routes and templates

- Adds GET/POST routes for user registration
- Adds registration form template
- All registration tests now pass"
```

### 5. Final Integration Test and Cleanup

```bash
# Run full test suite
mix test

# If everything passes, commit any final changes
git add .
git commit -m "Complete user registration feature

- All tests passing
- Feature ready for merge"
```

### 6. Merge Back to Main

```bash
# Switch to main and ensure it's up-to-date
git checkout main
git pull origin main

# Merge feature branch (use --no-ff to preserve branch history)
git merge --no-ff feature/user-registration

# Alternative: Use squash merge for cleaner history
# git merge --squash feature/user-registration
# git commit -m "Add user registration feature"
```

### 7. Push to Origin

```bash
# Push updated main branch
git push origin main
```

### 8. Delete Feature Branch

```bash
# Delete local feature branch
git branch -d feature/user-registration

# Delete remote feature branch (if you pushed it)
git push origin --delete feature/user-registration
```

## Commit Message Conventions

### Good Commit Messages for This Workflow

```bash
# Initial test commit
"Add tests for user authentication feature

- Test user login with valid credentials
- Test user login with invalid credentials  
- Test password reset flow
- Test account lockout after failed attempts
- All tests currently failing (TDD red phase)"

# Implementation commits
"Add User.authenticate/2 function

- Implements password verification
- Passes: authentication validation tests"

"Add session management to AuthController

- Implements login/logout endpoints
- Handles authentication errors
- Passes: controller authentication tests"

# Final commit
"Complete user authentication feature

- All authentication tests passing
- Feature ready for merge"
```

### Commit Message Template

```bash
# Configure git to use a commit template
git config --global commit.template ~/.gitmessage

# Create ~/.gitmessage template
# Subject line (50 chars max)

# Body: What and why (wrap at 72 chars)
# - Use bullet points for multiple changes
# - Reference tests that now pass
# - Note any remaining failing tests
```

## Workflow Variations

### For Bug Fixes

```bash
# Create bug fix branch
git checkout -b bugfix/fix-email-validation-regex

# Write failing test that reproduces the bug
git commit -m "Add test reproducing email validation bug

- Test shows regex accepts invalid emails like 'user@'
- Currently failing"

# Fix the bug
git commit -m "Fix email validation regex

- Update regex to require domain
- Passes: email validation test"

# Merge and cleanup
git checkout main
git merge --no-ff bugfix/fix-email-validation-regex
git push origin main
git branch -d bugfix/fix-email-validation-regex
```

### For Refactoring

```bash
git checkout -b refactor/extract-user-service

# Write tests for new structure first
git commit -m "Add tests for extracted UserService

- Test user creation through service layer
- Test validation handling
- Currently failing (service doesn't exist)"

# Implement refactoring
git commit -m "Extract UserService from Accounts context

- Moves user-specific logic to dedicated service
- Maintains existing API
- All tests passing"
```

## Best Practices

### 1. Keep Commits Atomic

```bash
# GOOD: Each commit has one responsibility
git commit -m "Add User schema with validations"
git commit -m "Add Accounts.create_user/1 function"  
git commit -m "Add user creation controller endpoint"

# BAD: Large commit with multiple concerns
git commit -m "Add user stuff"
```

### 2. Write Meaningful Test Descriptions

```elixir
# GOOD: Clear intent
test "create_user/1 sends welcome email to new user"
test "create_user/1 returns error when email already exists"

# BAD: Vague or implementation-focused
test "user test"
test "changeset validation"
```

### 3. Handle Failing Tests Appropriately

```bash
# If tests break during implementation
git add .
git commit -m "WIP: Implementing user validation

- Password validation partially complete
- 2 tests still failing: email format, password confirmation
- Will fix in next commit"
```

### 4. Use Feature Flags for Large Features

```elixir
# For features that take multiple days
if Application.get_env(:myapp, :enable_new_user_registration, false) do
  # New registration flow
else
  # Old registration flow
end
```

## Troubleshooting Common Issues

### Merge Conflicts

```bash
# If main has moved ahead while you worked
git checkout main
git pull origin main
git checkout feature/your-feature

# Rebase your feature branch
git rebase main

# Resolve conflicts, then continue
git add .
git rebase --continue
```

### Tests Become Flaky

```bash
# Commit stable state, then investigate
git add .
git commit -m "Save progress - investigating flaky test

- UserController tests passing
- UserLive tests occasionally failing
- Need to fix timing issue"
```

### Need to Change Direction Mid-Feature

```bash
# Create new branch from current point
git checkout -b feature/user-registration-simplified

# Continue with new approach
git commit -m "Simplify user registration approach

- Remove complex validation
- Focus on basic registration first"
```

## Integration with Phoenix Development

### Running Tests During Development

```bash
# Use Phoenix's test watcher
mix test.watch

# Run specific tests as you implement
mix test test/myapp/accounts_test.exs:42

# Run tests with coverage
mix test --cover
```

### Database Management

```bash
# Reset test database between feature branches
MIX_ENV=test mix ecto.reset

# Run migrations in test environment
MIX_ENV=test mix ecto.migrate
```

## Key Benefits of This Workflow

1. **Enforces TDD**: Can't implement without tests first
2. **Clear History**: Git log shows test-first development
3. **Easy Review**: Reviewers can see tests before implementation
4. **Safe Refactoring**: Comprehensive test coverage from start
5. **Documentation**: Tests serve as living documentation
6. **Rollback Safety**: Any commit can be safely reverted

## When to Deviate

**Skip for:**
- Simple typo fixes
- Documentation updates  
- Configuration changes
- Emergency hotfixes

**Modify for:**
- Large features (break into smaller feature branches)
- Research spikes (use `spike/` prefix)
- Pair programming (looser commit requirements)

## Commands Cheat Sheet

```bash
# Start feature
git checkout main && git pull origin main
git checkout -b feature/my-feature

# TDD cycle  
# 1. Write tests
git add test/ && git commit -m "Add tests for feature X"
# 2. Implement
git add . && git commit -m "Implement feature X"

# Complete feature
git checkout main && git pull origin main
git merge --no-ff feature/my-feature
git push origin main
git branch -d feature/my-feature

# Quick status
git status
git log --oneline -5
mix test
```

Remember: This workflow creates discipline around TDD while maintaining clean git history. The key is consistency - follow the pattern even for small features to build the habit!