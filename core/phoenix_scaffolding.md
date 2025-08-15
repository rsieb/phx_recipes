# Phoenix Scaffolding Recipe - Complete Module Structure

```elixir
Mix.install([
  {:phoenix, "~> 1.7"},
  {:phoenix_live_view, "~> 0.20"},
  {:ecto, "~> 3.10"}
])
```

## The Problem: Incomplete Module Structure

❌ **Common Issues:**
- Missing controller tests
- No context boundary
- Incomplete changeset validation
- Missing view/component files
- No migration files
- Inconsistent naming conventions

## ✅ The Solution: Phoenix Scaffolding as a Checklist

Phoenix generators create complete, conventional module structures. Use them as blueprints even when building manually.

## Available Phoenix Generators

### 1. Context Generator (`mix phx.gen.context`)

Creates the data layer without web components:

```bash
mix phx.gen.context Accounts User users name:string email:string:unique age:integer
```

**Generated Files:**
```
lib/myapp/accounts.ex                    # Context module
lib/myapp/accounts/user.ex               # Schema
priv/repo/migrations/*_create_users.exs  # Migration
test/myapp/accounts_test.exs             # Context tests
test/support/fixtures/accounts_fixtures.ex # Test fixtures
```

### 2. HTML Generator (`mix phx.gen.html`)

Full CRUD web interface with traditional server-rendered pages:

```bash
mix phx.gen.html Accounts User users name:string email:string:unique age:integer
```

**Generated Files:**
```
# Data Layer
lib/myapp/accounts.ex
lib/myapp/accounts/user.ex
priv/repo/migrations/*_create_users.exs

# Web Layer
lib/myapp_web/controllers/user_controller.ex
lib/myapp_web/controllers/user_html.ex
lib/myapp_web/controllers/user_html/
├── index.html.heex
├── show.html.heex
├── new.html.heex
├── edit.html.heex
└── user_form.html.heex

# Tests
test/myapp/accounts_test.exs
test/myapp_web/controllers/user_controller_test.exs
test/support/fixtures/accounts_fixtures.ex
```

### 3. LiveView Generator (`mix phx.gen.live`)

Modern real-time interface with LiveView:

```bash
mix phx.gen.live Accounts User users name:string email:string:unique age:integer
```

**Generated Files:**
```
# Data Layer (same as above)
lib/myapp/accounts.ex
lib/myapp/accounts/user.ex
priv/repo/migrations/*_create_users.exs

# LiveView Layer
lib/myapp_web/live/user_live/
├── index.ex
├── show.ex
├── form_component.ex
├── index.html.heex
├── show.html.heex
└── form_component.html.heex

# Tests
test/myapp/accounts_test.exs
test/myapp_web/live/user_live_test.exs
test/support/fixtures/accounts_fixtures.ex
```

### 4. JSON API Generator (`mix phx.gen.json`)

RESTful JSON API:

```bash
mix phx.gen.json Accounts User users name:string email:string:unique age:integer
```

**Generated Files:**
```
# Data Layer (same as above)
lib/myapp/accounts.ex
lib/myapp/accounts/user.ex
priv/repo/migrations/*_create_users.exs

# API Layer
lib/myapp_web/controllers/user_controller.ex
lib/myapp_web/controllers/user_json.ex

# Tests
test/myapp/accounts_test.exs
test/myapp_web/controllers/user_controller_test.exs
test/support/fixtures/accounts_fixtures.ex
```

## Complete Module Checklist

Use this checklist to ensure you have all necessary files for any module:

### ✅ Data Layer Files

```elixir
# 1. Schema File
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

```elixir
# 2. Context File
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

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
```

```elixir
# 3. Migration File
# priv/repo/migrations/*_create_users.exs
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string
      add :age, :integer

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end
```

### ✅ Web Layer Files (Choose One Approach)

#### For Traditional HTML (Phoenix HTML)

```elixir
# Controller
# lib/myapp_web/controllers/user_controller.ex
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias MyApp.Accounts

  def index(conn, _params) do
    users = Accounts.list_users()
    render(conn, :index, users: users)
  end

  def show(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)
    render(conn, :show, user: user)
  end

  def new(conn, _params) do
    changeset = Accounts.change_user(%MyApp.Accounts.User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User created successfully.")
        |> redirect(to: ~p"/users/#{user}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  # ... edit, update, delete actions
end
```

#### For LiveView

```elixir
# lib/myapp_web/live/user_live/index.ex
defmodule MyAppWeb.UserLive.Index do
  use MyAppWeb, :live_view
  alias MyApp.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :users, Accounts.list_users())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # ... handle_event callbacks
end
```

### ✅ Test Files

```elixir
# 1. Context Tests
# test/myapp/accounts_test.exs
defmodule MyApp.AccountsTest do
  use MyApp.DataCase
  alias MyApp.Accounts

  describe "users" do
    alias MyApp.Accounts.User

    import MyApp.AccountsFixtures

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
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
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(%{})
    end

    # ... more tests
  end
end
```

```elixir
# 2. Controller/LiveView Tests
# test/myapp_web/controllers/user_controller_test.exs
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase
  import MyApp.AccountsFixtures

  describe "index" do
    test "lists all users", %{conn: conn} do
      conn = get(conn, ~p"/users")
      assert html_response(conn, 200) =~ "Listing Users"
    end
  end

  describe "new user" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/users/new")
      assert html_response(conn, 200) =~ "New User"
    end
  end

  # ... more tests
end
```

```elixir
# 3. Test Fixtures
# test/support/fixtures/accounts_fixtures.ex
defmodule MyApp.AccountsFixtures do
  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test User",
      email: unique_user_email(),
      age: 30
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> MyApp.Accounts.create_user()

    user
  end
end
```

## Router Configuration

Don't forget to add routes:

```elixir
# lib/myapp_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    
    # Add these routes after generation
    resources "/users", UserController
    # OR for LiveView:
    # live "/users", UserLive.Index, :index
    # live "/users/new", UserLive.Index, :new
    # live "/users/:id/edit", UserLive.Index, :edit
    # live "/users/:id", UserLive.Show, :show
    # live "/users/:id/show/edit", UserLive.Show, :edit
  end
end
```

## Verification Checklist

After creating a module (manually or via generator), verify you have:

### Data Layer ✅
- [ ] Schema file with proper validations
- [ ] Context module with CRUD functions
- [ ] Migration file with indexes
- [ ] Test fixtures

### Web Layer ✅
- [ ] Controller/LiveView with all actions
- [ ] HTML templates or LiveView templates
- [ ] Form components for create/edit
- [ ] Proper error handling

### Tests ✅
- [ ] Context tests for all functions
- [ ] Controller/LiveView tests for all actions
- [ ] Test fixtures with unique data generation
- [ ] Edge case testing (validations, errors)

### Configuration ✅
- [ ] Routes added to router
- [ ] Proper pipeline configuration
- [ ] Navigation links updated (if needed)

## Advanced Patterns

### Custom Generators

Create your own generator for consistent patterns:

```bash
# Create a custom generator
mix phx.gen.context Blog Post posts title:string content:text published:boolean author_id:references:users
```

### Nested Resources

```bash
mix phx.gen.html Blog Comment comments content:text post_id:references:posts user_id:references:users
```

### With Associations

```elixir
# In your schema
defmodule MyApp.Blog.Post do
  schema "posts" do
    field :title, :string
    field :content, :string
    
    belongs_to :author, MyApp.Accounts.User
    has_many :comments, MyApp.Blog.Comment
    
    timestamps()
  end
end
```

## When to Use Each Generator

1. **`phx.gen.context`** - Building APIs, data-only modules, or when you want custom web interfaces
2. **`phx.gen.html`** - Traditional web apps, admin interfaces, forms-heavy applications
3. **`phx.gen.live`** - Interactive web apps, real-time features, modern UX
4. **`phx.gen.json`** - REST APIs, mobile backends, microservices

## Key Takeaways

1. **Use generators as blueprints** - Even if customizing heavily
2. **Follow the file structure** - Conventions make code predictable
3. **Don't skip tests** - Generators create comprehensive test suites
4. **Verify completeness** - Use the checklist above
5. **Customize after generation** - Generators provide a solid foundation
6. **Maintain consistency** - All modules should follow the same patterns

Remember: A complete Phoenix module includes data layer, web layer, tests, and proper configuration!