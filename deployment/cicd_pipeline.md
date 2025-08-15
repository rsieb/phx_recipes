# CI/CD Pipeline Recipe

## Introduction

Continuous Integration and Continuous Deployment (CI/CD) are essential for modern Phoenix applications. This recipe covers comprehensive CI/CD setup including GitHub Actions workflows, test automation, database migrations, Docker builds, and deployment strategies following Phoenix best practices.

## GitHub Actions for Phoenix

### Basic CI Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

env:
  MIX_ENV: test
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

jobs:
  test:
    name: Test Suite
    runs-on: ubuntu-20.04
    
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: myapp_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
      
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.7'
        otp-version: '26.1'
        version-type: strict

    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: |
          deps
          _build
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
        restore-keys: |
          ${{ runner.os }}-mix-

    - name: Install dependencies
      run: |
        mix deps.get --only test
        mix deps.compile

    - name: Check formatting
      run: mix format --check-formatted

    - name: Run Credo
      run: mix credo --strict

    - name: Run security checks
      run: mix sobelow --config

    - name: Check for unused dependencies
      run: mix deps.unlock --check-unused

    - name: Compile (warnings as errors)
      run: mix compile --warnings-as-errors

    - name: Run tests
      run: mix test --cover --export-coverage default
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/myapp_test
        REDIS_URL: redis://localhost:6379/0

    - name: Generate coverage report
      run: mix test.coverage

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        files: ./cover/lcov.info
        fail_ci_if_error: true

  dialyzer:
    name: Dialyzer Analysis
    runs-on: ubuntu-20.04
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.7'
        otp-version: '26.1'
        version-type: strict

    - name: Cache PLT
      uses: actions/cache@v3
      with:
        path: priv/plts
        key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}
        restore-keys: |
          ${{ runner.os }}-plt-

    - name: Install dependencies
      run: |
        mix deps.get
        mix deps.compile

    - name: Run Dialyzer
      run: mix dialyzer

  assets:
    name: Assets Pipeline
    runs-on: ubuntu-20.04
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
        cache-dependency-path: assets/package-lock.json

    - name: Install Node dependencies
      run: |
        cd assets
        npm ci

    - name: Run ESLint
      run: |
        cd assets
        npm run lint

    - name: Run asset tests
      run: |
        cd assets
        npm test

    - name: Build assets
      run: |
        cd assets
        npm run build

    - name: Check asset build
      run: |
        mix assets.deploy
        test -f priv/static/assets/app.css
        test -f priv/static/assets/app.js
```

### Advanced Multi-Environment Workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [ main ]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'staging'
        type: choice
        options:
        - staging
        - production

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    uses: ./.github/workflows/ci.yml

  build:
    name: Build Docker Image
    runs-on: ubuntu-20.04
    needs: test
    outputs:
      image: ${{ steps.image.outputs.image }}
      digest: ${{ steps.build.outputs.digest }}
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=sha,prefix={{branch}}-
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Build and push Docker image
      id: build
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        build-args: |
          BUILD_ENV=production
          MIX_ENV=prod

    - name: Generate artifact attestation
      uses: actions/attest-build-provenance@v1
      with:
        subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME}}
        subject-digest: ${{ steps.build.outputs.digest }}
        push-to-registry: true

    - name: Output image
      id: image
      run: echo "image=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}" >> $GITHUB_OUTPUT

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-20.04
    needs: build
    if: github.ref == 'refs/heads/main' || github.event.inputs.environment == 'staging'
    environment:
      name: staging
      url: https://staging.myapp.com
    
    steps:
    - name: Deploy to Fly.io Staging
      uses: superfly/flyctl-actions/setup-flyctl@master
    
    - name: Deploy staging app
      run: |
        flyctl deploy \
          --image ${{ needs.build.outputs.image }} \
          --app myapp-staging \
          --strategy immediate
      env:
        FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

    - name: Run database migrations
      run: |
        flyctl ssh console \
          --app myapp-staging \
          --command "/app/bin/myapp eval \"MyApp.Release.migrate\""
      env:
        FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

    - name: Health check
      run: |
        sleep 30
        curl -f https://staging.myapp.com/health || exit 1

  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-20.04
    needs: [build, deploy-staging]
    if: github.ref == 'refs/heads/main' || github.event.inputs.environment == 'production'
    environment:
      name: production
      url: https://myapp.com
    
    steps:
    - name: Deploy to Fly.io Production
      uses: superfly/flyctl-actions/setup-flyctl@master
    
    - name: Deploy production app
      run: |
        flyctl deploy \
          --image ${{ needs.build.outputs.image }} \
          --app myapp-production \
          --strategy canary
      env:
        FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

    - name: Run database migrations
      run: |
        flyctl ssh console \
          --app myapp-production \
          --command "/app/bin/myapp eval \"MyApp.Release.migrate\""
      env:
        FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

    - name: Health check
      run: |
        sleep 60
        curl -f https://myapp.com/health || exit 1

    - name: Notify deployment
      uses: 8398a7/action-slack@v3
      with:
        status: ${{ job.status }}
        channel: '#deployments'
        webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

## Test Automation

### Comprehensive Test Configuration

```elixir
# test/test_helper.exs
ExUnit.start()

# Configure test database
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)

# Test support modules
defmodule MyApp.TestHelpers do
  @moduledoc """
  Helper functions for tests
  """

  def setup_test_data do
    # Create standard test data
    %{
      user: create_user(),
      admin: create_admin(),
      posts: create_posts(3)
    }
  end

  def create_user(attrs \\ %{}) do
    attrs = 
      Enum.into(attrs, %{
        email: "user-#{System.unique_integer()}@example.com",
        name: "Test User",
        password: "password123"
      })

    {:ok, user} = MyApp.Accounts.create_user(attrs)
    user
  end

  def create_admin(attrs \\ %{}) do
    attrs = Map.put(attrs, :role, :admin)
    create_user(attrs)
  end

  def create_posts(count) when is_integer(count) do
    user = create_user()
    
    Enum.map(1..count, fn i ->
      {:ok, post} = MyApp.Blog.create_post(%{
        title: "Test Post #{i}",
        content: "This is test content for post #{i}",
        user_id: user.id
      })
      post
    end)
  end

  def authenticate_user(conn, user) do
    token = MyAppWeb.Auth.sign_user_token(user.id)
    
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end

# Database cleaner
defmodule MyApp.DatabaseCleaner do
  @moduledoc """
  Cleans the database between tests
  """

  def clean do
    # Use TRUNCATE for faster cleanup
    tables = [
      "users",
      "posts", 
      "comments",
      "user_sessions"
    ]

    Enum.each(tables, fn table ->
      Ecto.Adapters.SQL.query!(MyApp.Repo, "TRUNCATE #{table} RESTART IDENTITY CASCADE", [])
    end)
  end
end
```

### Parallel Test Setup

```elixir
# config/test.exs
import Config

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "myapp_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Use different Redis database for each test partition
config :my_app, :redis_url, 
  System.get_env("REDIS_URL", "redis://localhost:6379/#{System.get_env("MIX_TEST_PARTITION", "0")}")

config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_long_enough",
  server: false

# Fast bcrypt for tests
config :bcrypt_elixir, :log_rounds, 1

# Disable Swoosh for tests
config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Test

# Faster tests
config :phoenix, :plug_init_mode, :runtime
```

### Test Categories and Organization

```elixir
# test/my_app/accounts_test.exs
defmodule MyApp.AccountsTest do
  use MyApp.DataCase
  alias MyApp.Accounts

  @moduletag :unit

  describe "create_user/1" do
    test "creates user with valid attributes" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "password123"
      }

      assert {:ok, user} = Accounts.create_user(attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      refute user.password == "password123" # Should be hashed
    end

    test "returns error with invalid email" do
      attrs = %{email: "invalid", name: "Test", password: "password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "has invalid format" in errors_on(changeset).email
    end
  end

  describe "authenticate_user/2" do
    test "authenticates user with correct credentials" do
      user = user_fixture()
      assert {:ok, authenticated_user} = Accounts.authenticate_user(user.email, "password123")
      assert authenticated_user.id == user.id
    end

    test "returns error with incorrect password" do
      user = user_fixture()
      assert {:error, :invalid_credentials} = Accounts.authenticate_user(user.email, "wrong")
    end
  end
end

# test/my_app_web/controllers/page_controller_test.exs
defmodule MyAppWeb.PageControllerTest do
  use MyAppWeb.ConnCase

  @moduletag :integration

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome"
  end
end

# test/my_app_web/live/post_live_test.exs
defmodule MyAppWeb.PostLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  @moduletag :feature

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "Index" do
    test "lists all posts", %{conn: conn, user: user} do
      conn = authenticate_user(conn, user)
      {:ok, _index_live, html} = live(conn, ~p"/posts")

      assert html =~ "Listing Posts"
    end

    test "saves new post", %{conn: conn, user: user} do
      conn = authenticate_user(conn, user)
      {:ok, index_live, _html} = live(conn, ~p"/posts")

      assert index_live |> element("a", "New Post") |> render_click() =~
               "New Post"

      assert_patch(index_live, ~p"/posts/new")

      assert index_live
             |> form("#post-form", post: %{title: "", content: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#post-form", post: %{title: "Test Post", content: "Test content"})
             |> render_submit()

      assert_patch(index_live, ~p"/posts")

      html = render(index_live)
      assert html =~ "Test Post"
    end
  end
end
```

### Test Performance and Monitoring

```elixir
# test/support/performance_case.ex
defmodule MyApp.PerformanceCase do
  @moduledoc """
  Performance testing utilities
  """

  defmacro __using__(_) do
    quote do
      import MyApp.PerformanceCase
    end
  end

  def benchmark(name, fun) do
    {time, result} = :timer.tc(fun)
    time_ms = time / 1000
    
    if time_ms > 100 do
      IO.puts("⚠️  Slow test: #{name} took #{time_ms}ms")
    end
    
    result
  end

  def assert_fast(fun, max_time_ms \\ 50) do
    {time, result} = :timer.tc(fun)
    time_ms = time / 1000
    
    if time_ms > max_time_ms do
      flunk("Operation took #{time_ms}ms, expected under #{max_time_ms}ms")
    end
    
    result
  end

  def memory_usage(fun) do
    :erlang.garbage_collect()
    memory_before = :erlang.memory(:total)
    
    result = fun.()
    
    :erlang.garbage_collect()
    memory_after = :erlang.memory(:total)
    memory_used = memory_after - memory_before
    
    {result, memory_used}
  end
end

# Usage in tests
defmodule MyApp.Blog.PerformanceTest do
  use MyApp.DataCase
  use MyApp.PerformanceCase

  @moduletag :performance

  test "list_posts is fast with many posts" do
    # Create 1000 posts
    Enum.each(1..1000, fn _ ->
      post_fixture()
    end)

    assert_fast(fn ->
      MyApp.Blog.list_posts()
    end, 100) # Should complete within 100ms
  end

  test "memory usage is reasonable for large queries" do
    Enum.each(1..100, fn _ ->
      post_fixture()
    end)

    {posts, memory_used} = memory_usage(fn ->
      MyApp.Blog.list_posts_with_comments()
    end)

    assert length(posts) == 100
    assert memory_used < 1_000_000 # Less than 1MB
  end
end
```

## Database Migrations in CI

### Migration Safety Checks

```elixir
# lib/my_app/release.ex
defmodule MyApp.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :my_app

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def migration_status do
    load_app()

    for repo <- repos() do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrations/1) do
        {:ok, migrations, _} ->
          IO.puts("=== #{repo} ===")
          
          for {status, number, description} <- migrations do
            status_string = 
              case status do
                :up -> "✓"
                :down -> "✗"
              end
            
            IO.puts("#{status_string} #{number} #{description}")
          end

        {:error, error} ->
          IO.puts("Error checking migrations for #{repo}: #{inspect(error)}")
      end
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

### Migration Testing Strategy

```elixir
# test/migrations_test.exs
defmodule MyApp.MigrationsTest do
  use ExUnit.Case
  alias Ecto.Migrator

  @moduletag :migrations

  describe "migrations" do
    test "all migrations are reversible" do
      repo = MyApp.Repo
      
      # Get all migrations
      migrations_path = Application.app_dir(:my_app, "priv/repo/migrations")
      migration_files = Path.wildcard("#{migrations_path}/*.exs")
      
      Enum.each(migration_files, fn file ->
        # Extract version from filename
        version = 
          file
          |> Path.basename()
          |> String.split("_")
          |> List.first()
          |> String.to_integer()

        # Test migration up
        {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, to: version))
        
        # Test migration down (should not fail)
        try do
          {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version - 1))
          
          # Migrate back up for next test
          {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, to: version))
        rescue
          error ->
            flunk("Migration #{version} is not reversible: #{inspect(error)}")
        end
      end)
    end

    test "migrations don't break existing data" do
      # This would be more complex in practice, testing specific data scenarios
      repo = MyApp.Repo
      
      # Create test data before migrations
      test_user = insert_test_user()
      
      # Run latest migration
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, all: true))
      
      # Verify test data still exists and is valid
      user = repo.get(MyApp.Accounts.User, test_user.id)
      assert user.email == test_user.email
    end
  end

  defp insert_test_user do
    %MyApp.Accounts.User{
      email: "test@example.com",
      name: "Test User",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
    |> MyApp.Repo.insert!()
  end
end
```

### Safe Migration Patterns

```elixir
# priv/repo/migrations/20231201120000_add_index_safely.exs
defmodule MyApp.Repo.Migrations.AddIndexSafely do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # Create index concurrently to avoid locking
    create index("posts", ["user_id"], concurrently: true)
  end

  def down do
    drop index("posts", ["user_id"])
  end
end

# priv/repo/migrations/20231201130000_add_column_with_default.exs
defmodule MyApp.Repo.Migrations.AddColumnWithDefault do
  use Ecto.Migration

  def up do
    # Step 1: Add column without default
    alter table("users") do
      add :status, :string
    end

    # Step 2: Update existing records
    execute "UPDATE users SET status = 'active' WHERE status IS NULL"

    # Step 3: Add NOT NULL constraint
    alter table("users") do
      modify :status, :string, null: false
    end

    # Step 4: Add index
    create index("users", ["status"])
  end

  def down do
    alter table("users") do
      remove :status
    end
  end
end
```

## Docker Builds

### Multi-Stage Dockerfile

```dockerfile
# Dockerfile
# Use the official Elixir image as the base image
FROM elixir:1.15.7-otp-26-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm

# Set build ENV
ENV MIX_ENV=prod

# Create app directory and copy mix files
WORKDIR /app
COPY mix.exs mix.lock ./
COPY config config

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install mix dependencies
RUN mix deps.get --only=prod
RUN mix deps.compile

# Install and build assets
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix ./assets --progress=false --no-audit --loglevel=error

COPY priv priv
COPY assets assets
RUN npm run --prefix ./assets build
RUN mix assets.deploy

# Copy source code
COPY lib lib

# Compile the release
RUN mix compile

# Build the release
RUN mix release

# Start a new build stage for the runtime
FROM alpine:3.18 AS runner

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs

# Create a non-root user
RUN addgroup -S myapp && adduser -S myapp -G myapp

# Set the user and work directory
USER myapp
WORKDIR /app

# Copy the release from the builder stage
COPY --from=builder --chown=myapp:myapp /app/_build/prod/rel/myapp ./

# Set environment variables
ENV HOME=/app
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey
ENV PORT=4000
ENV PHX_HOST=localhost

# Expose the port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD /app/bin/myapp rpc "MyApp.HealthCheck.check()" || exit 1

# Start the application
CMD ["/app/bin/myapp", "start"]
```

### Docker Compose for Development

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/myapp_dev
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY_BASE: supersecret
    volumes:
      - .:/app
      - /app/deps
      - /app/_build
    depends_on:
      - db
      - redis
    command: mix phx.server

  db:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: myapp_dev
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  test_db:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: myapp_test
    ports:
      - "5433:5432"
    tmpfs:
      - /var/lib/postgresql/data

volumes:
  postgres_data:
  redis_data:
```

### Development Dockerfile

```dockerfile
# Dockerfile.dev
FROM elixir:1.15.7-otp-26

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    nodejs \
    npm \
    inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set working directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./

# Install Elixir dependencies
RUN mix deps.get

# Copy package files
COPY assets/package.json assets/package-lock.json ./assets/

# Install Node dependencies
RUN npm ci --prefix ./assets

# Copy source
COPY . .

# Compile dependencies
RUN mix deps.compile

# Expose port
EXPOSE 4000

# Start development server
CMD ["mix", "phx.server"]
```

## Deployment Strategies

### Blue-Green Deployment with Fly.io

```yaml
# fly.toml
app = "myapp-production"
primary_region = "sjc"

[build]
  image = "myapp:latest"

[env]
  PHX_HOST = "myapp.com"
  PORT = "8080"
  MIX_ENV = "prod"
  ECTO_IPV6 = "true"
  ERL_AFLAGS = "-proto_dist inet6_tcp"

[experimental]
  auto_rollback = true

[[services]]
  http_checks = []
  internal_port = 8080
  processes = ["app"]
  protocol = "tcp"
  script_checks = []

  [services.concurrency]
    hard_limit = 1000
    soft_limit = 200
    type = "connections"

  [[services.ports]]
    force_https = true
    handlers = ["http"]
    port = 80

  [[services.ports]]
    handlers = ["tls", "http"]
    port = 443

  [[services.tcp_checks]]
    grace_period = "10s"
    interval = "15s"
    restart_limit = 0
    timeout = "2s"

  [[services.http_checks]]
    interval = "10s"
    grace_period = "5s"
    method = "get"
    path = "/health"
    protocol = "http"
    timeout = "2s"
    tls_skip_verify = false

[deploy]
  release_command = "/app/bin/myapp eval MyApp.Release.migrate"
  strategy = "bluegreen"

[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 512
```

### Deployment Script

```bash
#!/bin/bash
# scripts/deploy.sh

set -e

ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}

echo "🚀 Deploying to $ENVIRONMENT with image tag $IMAGE_TAG"

# Build and push image
echo "📦 Building Docker image..."
docker build -t myapp:$IMAGE_TAG .
docker tag myapp:$IMAGE_TAG ghcr.io/username/myapp:$IMAGE_TAG
docker push ghcr.io/username/myapp:$IMAGE_TAG

# Deploy based on environment
case $ENVIRONMENT in
  staging)
    echo "🔄 Deploying to staging..."
    flyctl deploy \
      --image ghcr.io/username/myapp:$IMAGE_TAG \
      --app myapp-staging \
      --strategy immediate
    ;;
  production)
    echo "🔄 Deploying to production..."
    # Production uses blue-green deployment
    flyctl deploy \
      --image ghcr.io/username/myapp:$IMAGE_TAG \
      --app myapp-production \
      --strategy bluegreen
    ;;
  *)
    echo "❌ Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

# Health check
echo "🏥 Running health check..."
sleep 30

if [ $ENVIRONMENT = "staging" ]; then
  HEALTH_URL="https://staging.myapp.com/health"
else
  HEALTH_URL="https://myapp.com/health"
fi

if curl -f $HEALTH_URL; then
  echo "✅ Deployment successful!"
else
  echo "❌ Health check failed!"
  exit 1
fi

echo "🎉 Deployment to $ENVIRONMENT completed successfully!"
```

### Rollback Strategy

```elixir
# lib/my_app/deployment.ex
defmodule MyApp.Deployment do
  @moduledoc """
  Deployment utilities for production operations
  """

  def current_version do
    Application.spec(:my_app, :vsn) |> to_string()
  end

  def deployment_info do
    %{
      version: current_version(),
      build_time: build_time(),
      git_sha: git_sha(),
      environment: Mix.env()
    }
  end

  def health_check do
    checks = [
      database_check(),
      redis_check(),
      external_services_check()
    ]

    all_healthy = Enum.all?(checks, & &1.status == :ok)

    %{
      status: if(all_healthy, do: :healthy, else: :unhealthy),
      checks: checks,
      timestamp: DateTime.utc_now()
    }
  end

  defp database_check do
    try do
      MyApp.Repo.query!("SELECT 1", [])
      %{name: :database, status: :ok}
    rescue
      _ -> %{name: :database, status: :error}
    end
  end

  defp redis_check do
    try do
      Redix.command!(:redix, ["PING"])
      %{name: :redis, status: :ok}
    rescue
      _ -> %{name: :redis, status: :error}
    end
  end

  defp external_services_check do
    # Check critical external services
    %{name: :external_services, status: :ok}
  end

  defp build_time do
    case :application.get_key(:my_app, :build_time) do
      {:ok, time} -> time
      :undefined -> "unknown"
    end
  end

  defp git_sha do
    case :application.get_key(:my_app, :git_sha) do
      {:ok, sha} -> sha
      :undefined -> "unknown"
    end
  end
end
```

### Monitoring and Alerting

```elixir
# lib/my_app_web/controllers/health_controller.ex
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller
  alias MyApp.Deployment

  def show(conn, _params) do
    health = Deployment.health_check()
    
    status_code = 
      case health.status do
        :healthy -> 200
        :unhealthy -> 503
      end

    conn
    |> put_status(status_code)
    |> json(health)
  end

  def version(conn, _params) do
    json(conn, Deployment.deployment_info())
  end

  def ready(conn, _params) do
    # Readiness probe for Kubernetes/Fly.io
    case Deployment.health_check() do
      %{status: :healthy} ->
        send_resp(conn, 200, "ready")

      _ ->
        send_resp(conn, 503, "not ready")
    end
  end

  def live(conn, _params) do
    # Liveness probe - minimal check
    send_resp(conn, 200, "alive")
  end
end
```

This comprehensive CI/CD pipeline recipe provides production-ready patterns for automated testing, building, and deploying Phoenix applications with proper safety checks, monitoring, and rollback capabilities.