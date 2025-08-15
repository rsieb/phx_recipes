# Oban Background Jobs and Testing Recipe

```elixir
Mix.install([
  {:phoenix, "~> 1.7"},
  {:oban, "~> 2.17"},
  {:ecto, "~> 3.10"}
])
```

## What is Oban?

Oban is a robust background job processing library for Elixir that uses PostgreSQL for job storage and coordination. It provides:

- **Persistent job queues** stored in PostgreSQL
- **Reliable job execution** with retry mechanisms
- **Scheduled and recurring jobs** with cron-like syntax
- **Job prioritization** and queue management
- **Comprehensive testing tools** for job verification

## Why Oban Works Well with Phoenix

**Database-backed reliability**: Jobs survive application restarts
**Phoenix integration**: Works seamlessly with Ecto and Phoenix contexts
**Testing support**: Built-in testing utilities for job verification
**Observability**: Rich metrics and job monitoring capabilities
**Scalability**: Handles high-volume background processing

## Oban Setup in Phoenix

### 1. Installation and Configuration

```elixir
# mix.exs
def deps do
  [
    {:oban, "~> 2.17"}
  ]
end

# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10, emails: 20, reports: 5]

# config/test.exs
config :my_app, Oban, testing: :inline

# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Oban, Application.fetch_env!(:my_app, Oban)},
    MyAppWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 2. Database Migration

```bash
# Generate Oban migration
mix ecto.gen.migration add_oban_jobs_table

# Add to migration file
mix oban.gen.migration
```

```elixir
# priv/repo/migrations/xxx_add_oban_jobs_table.exs
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
```

## Creating Oban Workers

### Basic Worker Pattern

```elixir
# lib/my_app/workers/email_worker.ex
defmodule MyApp.Workers.EmailWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3

  alias MyApp.Mailer
  alias MyApp.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "type" => "welcome"}}) do
    user = Accounts.get_user!(user_id)
    
    case Mailer.send_welcome_email(user) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"user_id" => user_id, "type" => "password_reset"}}) do
    user = Accounts.get_user!(user_id)
    
    case Mailer.send_password_reset_email(user) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Handle unknown job types
  def perform(%Oban.Job{args: args}) do
    {:error, "Unknown email type: #{inspect(args)}"}
  end
end
```

### Data Processing Worker

```elixir
# lib/my_app/workers/import_processor.ex
defmodule MyApp.Workers.ImportProcessor do
  use Oban.Worker, 
    queue: :imports, 
    max_attempts: 5,
    tags: ["import", "data_processing"]

  alias MyApp.Imports
  alias MyApp.People

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_id" => import_id}}) do
    import = Imports.get_import!(import_id)
    
    # Update status to processing
    {:ok, import} = Imports.update_import(import, %{status: "processing"})
    
    case process_import_records(import) do
      {:ok, results} ->
        Imports.update_import(import, %{
          status: "completed",
          processed_records: results.processed_count,
          failed_records: results.failed_count
        })
        :ok
        
      {:error, reason} ->
        Imports.update_import(import, %{
          status: "failed",
          error_message: reason
        })
        {:error, reason}
    end
  end

  defp process_import_records(import) do
    staging_records = Imports.list_staging_records(import)
    
    results = 
      Enum.reduce(staging_records, %{processed_count: 0, failed_count: 0}, fn record, acc ->
        case process_single_record(record) do
          {:ok, _person} -> 
            %{acc | processed_count: acc.processed_count + 1}
          {:error, _reason} -> 
            %{acc | failed_count: acc.failed_count + 1}
        end
      end)
    
    {:ok, results}
  end

  defp process_single_record(staging_record) do
    # Transform staging record to person attributes
    attrs = %{
      name: staging_record.raw_data["name"],
      email: staging_record.raw_data["email"],
      company: staging_record.raw_data["company"]
    }
    
    People.create_person(attrs)
  end
end
```

### Scheduled/Recurring Worker

```elixir
# lib/my_app/workers/cleanup_worker.ex
defmodule MyApp.Workers.CleanupWorker do
  use Oban.Worker, 
    queue: :scheduled, 
    max_attempts: 1

  alias MyApp.Repo
  alias MyApp.Imports.Import

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"days" => days}}) do
    cutoff_date = Date.utc_today() |> Date.add(-days)
    
    {deleted_count, _} =
      from(i in Import,
        where: i.inserted_at < ^cutoff_date,
        where: i.status in ["completed", "failed"]
      )
      |> Repo.delete_all()
    
    {:ok, "Deleted #{deleted_count} old imports"}
  end
end

# Schedule in application.ex or via cron plugin
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron, 
     crontab: [
       {"0 2 * * *", MyApp.Workers.CleanupWorker, args: %{days: 30}}
     ]}
  ]
```

## Job Enqueueing Patterns

### Simple Job Enqueueing

```elixir
# In your context or controller
defmodule MyApp.Accounts do
  def create_user(attrs) do
    case do_create_user(attrs) do
      {:ok, user} ->
        # Enqueue welcome email
        %{user_id: user.id, type: "welcome"}
        |> MyApp.Workers.EmailWorker.new()
        |> Oban.insert()
        
        {:ok, user}
        
      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
```

### Scheduled Job Enqueueing

```elixir
# Schedule job for later execution
defmodule MyApp.Subscriptions do
  def create_trial_subscription(user) do
    {:ok, subscription} = do_create_subscription(user)
    
    # Schedule trial expiration reminder
    %{user_id: user.id, subscription_id: subscription.id}
    |> MyApp.Workers.TrialExpirationWorker.new(
      scheduled_at: DateTime.add(DateTime.utc_now(), 25, :day)
    )
    |> Oban.insert()
    
    {:ok, subscription}
  end
end
```

### Bulk Job Enqueueing

```elixir
# Enqueue multiple jobs efficiently
defmodule MyApp.Notifications do
  def send_newsletter_to_all_users do
    users = Accounts.list_active_users()
    
    jobs = 
      Enum.map(users, fn user ->
        MyApp.Workers.NewsletterWorker.new(%{
          user_id: user.id,
          newsletter_id: "weekly-update"
        })
      end)
    
    Oban.insert_all(jobs)
  end
end
```

## Testing Oban Workers

### Test Setup

```elixir
# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.DataCase
      
      # Add Oban testing support
      use Oban.Testing, repo: MyApp.Repo
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    :ok
  end
end

# test/support/conn_case.ex
defmodule MyApp.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import MyApp.ConnCase
      
      # Add Oban testing support
      use Oban.Testing, repo: MyApp.Repo
      
      alias MyApp.Router.Helpers, as: Routes
      @endpoint MyApp.Endpoint
    end
  end
end
```

### Worker Unit Tests

```elixir
# test/my_app/workers/email_worker_test.exs
defmodule MyApp.Workers.EmailWorkerTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workers.EmailWorker
  alias MyApp.Accounts
  
  describe "perform/1" do
    test "sends welcome email for valid user" do
      user = insert(:user)
      
      job = EmailWorker.new(%{user_id: user.id, type: "welcome"})
      
      assert {:ok, _} = perform_job(EmailWorker, job.args)
      
      # Verify email was sent (using a mock or test adapter)
      assert_email_sent(fn email ->
        assert email.to == [user.email]
        assert email.subject =~ "Welcome"
      end)
    end

    test "sends password reset email for valid user" do
      user = insert(:user)
      
      job = EmailWorker.new(%{user_id: user.id, type: "password_reset"})
      
      assert {:ok, _} = perform_job(EmailWorker, job.args)
      
      assert_email_sent(fn email ->
        assert email.to == [user.email]
        assert email.subject =~ "Password Reset"
      end)
    end

    test "returns error for non-existent user" do
      job = EmailWorker.new(%{user_id: 999999, type: "welcome"})
      
      assert_raise Ecto.NoResultsError, fn ->
        perform_job(EmailWorker, job.args)
      end
    end

    test "returns error for unknown email type" do
      user = insert(:user)
      
      job = EmailWorker.new(%{user_id: user.id, type: "unknown"})
      
      assert {:error, reason} = perform_job(EmailWorker, job.args)
      assert reason =~ "Unknown email type"
    end
  end
end
```

### Integration Tests with Job Enqueueing

```elixir
# test/my_app/accounts_test.exs
defmodule MyApp.AccountsTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Accounts
  alias MyApp.Workers.EmailWorker

  describe "create_user/1" do
    test "creates user and enqueues welcome email" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        password: "secure_password"
      }
      
      assert {:ok, user} = Accounts.create_user(attrs)
      
      # Verify user was created
      assert user.name == "John Doe"
      assert user.email == "john@example.com"
      
      # Verify job was enqueued
      assert_enqueued(
        worker: EmailWorker,
        args: %{user_id: user.id, type: "welcome"}
      )
    end

    test "does not enqueue email on user creation failure" do
      attrs = %{email: "invalid-email"}  # Invalid attributes
      
      assert {:error, _changeset} = Accounts.create_user(attrs)
      
      # Verify no job was enqueued
      refute_enqueued(worker: EmailWorker)
    end
  end
end
```

### Controller Tests with Background Jobs

```elixir
# test/my_app_web/controllers/user_controller_test.exs
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase, async: true
  
  alias MyApp.Workers.EmailWorker

  describe "POST /users" do
    test "creates user and enqueues welcome email", %{conn: conn} do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        password: "secure_password"
      }
      
      conn = post(conn, ~p"/users", user: attrs)
      
      # Verify redirect
      assert redirected_to(conn) =~ "/users/"
      
      # Verify job was enqueued
      assert_enqueued(worker: EmailWorker, args: %{type: "welcome"})
    end

    test "does not enqueue email on validation failure", %{conn: conn} do
      attrs = %{email: "invalid"}
      
      conn = post(conn, ~p"/users", user: attrs)
      
      # Verify form re-renders
      assert html_response(conn, 200) =~ "New User"
      
      # Verify no job was enqueued
      refute_enqueued(worker: EmailWorker)
    end
  end
end
```

### Testing Job Execution in Integration Tests

```elixir
# test/my_app/imports_integration_test.exs
defmodule MyApp.ImportsIntegrationTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Imports
  alias MyApp.Workers.ImportProcessor

  test "complete import workflow" do
    # Create import with staging records
    import = insert(:import)
    insert(:staging_record, import: import, raw_data: %{"name" => "John", "email" => "john@example.com"})
    insert(:staging_record, import: import, raw_data: %{"name" => "Jane", "email" => "jane@example.com"})
    
    # Execute the job
    job = ImportProcessor.new(%{import_id: import.id})
    assert {:ok, _} = perform_job(ImportProcessor, job.args)
    
    # Verify import was processed
    updated_import = Imports.get_import!(import.id)
    assert updated_import.status == "completed"
    assert updated_import.processed_records == 2
    assert updated_import.failed_records == 0
    
    # Verify people were created
    assert length(MyApp.People.list_people()) == 2
  end

  test "handles processing errors gracefully" do
    import = insert(:import)
    # Insert invalid staging record
    insert(:staging_record, import: import, raw_data: %{"name" => "", "email" => "invalid"})
    
    job = ImportProcessor.new(%{import_id: import.id})
    assert {:ok, _} = perform_job(ImportProcessor, job.args)
    
    # Verify import handled errors
    updated_import = Imports.get_import!(import.id)
    assert updated_import.status == "completed"
    assert updated_import.processed_records == 0
    assert updated_import.failed_records == 1
  end
end
```

## Testing Patterns and Best Practices

### 1. Use Oban.Testing for Job Verification

```elixir
# Test that jobs are enqueued (not executed)
test "enqueues notification job" do
  user = insert(:user)
  
  MyApp.Notifications.send_welcome_notification(user)
  
  assert_enqueued(
    worker: MyApp.Workers.NotificationWorker,
    args: %{user_id: user.id, type: "welcome"}
  )
end

# Test job execution
test "processes notification successfully" do
  user = insert(:user)
  
  job = MyApp.Workers.NotificationWorker.new(%{user_id: user.id, type: "welcome"})
  
  assert {:ok, result} = perform_job(MyApp.Workers.NotificationWorker, job.args)
  assert result == "Notification sent successfully"
end
```

### 2. Test Error Handling and Retries

```elixir
# test/my_app/workers/api_worker_test.exs
defmodule MyApp.Workers.ApiWorkerTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workers.ApiWorker
  
  test "retries on temporary API failures" do
    # Mock API to fail first time, succeed second time
    with_mock MyApp.ExternalAPI, [
      call: fn -> {:error, :timeout} end
    ] do
      job = ApiWorker.new(%{endpoint: "/users", data: %{}})
      
      # First attempt should fail and be retried
      assert {:error, :timeout} = perform_job(ApiWorker, job.args)
    end
    
    # Verify job can succeed on retry
    with_mock MyApp.ExternalAPI, [
      call: fn -> {:ok, %{status: "success"}} end
    ] do
      job = ApiWorker.new(%{endpoint: "/users", data: %{}})
      
      assert {:ok, result} = perform_job(ApiWorker, job.args)
      assert result.status == "success"
    end
  end
end
```

### 3. Test Scheduled Jobs

```elixir
# test/my_app/workers/cleanup_worker_test.exs
defmodule MyApp.Workers.CleanupWorkerTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workers.CleanupWorker
  alias MyApp.Imports.Import

  test "deletes old completed imports" do
    # Create old completed import
    old_import = insert(:import, 
      status: "completed",
      inserted_at: DateTime.add(DateTime.utc_now(), -35, :day)
    )
    
    # Create recent import (should not be deleted)
    recent_import = insert(:import, 
      status: "completed",
      inserted_at: DateTime.add(DateTime.utc_now(), -5, :day)
    )
    
    # Run cleanup job
    job = CleanupWorker.new(%{days: 30})
    assert {:ok, result} = perform_job(CleanupWorker, job.args)
    
    # Verify old import was deleted
    refute Repo.get(Import, old_import.id)
    
    # Verify recent import was preserved
    assert Repo.get(Import, recent_import.id)
    
    # Verify result message
    assert result =~ "Deleted 1 old imports"
  end
end
```

### 4. Test Job Dependencies and Workflows

```elixir
# test/my_app/workflows/user_onboarding_test.exs
defmodule MyApp.Workflows.UserOnboardingTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workflows.UserOnboarding
  alias MyApp.Workers.{EmailWorker, SetupWorker, AnalyticsWorker}

  test "enqueues complete onboarding workflow" do
    user = insert(:user)
    
    UserOnboarding.start(user)
    
    # Verify welcome email is sent immediately
    assert_enqueued(
      worker: EmailWorker,
      args: %{user_id: user.id, type: "welcome"}
    )
    
    # Verify setup job is scheduled for later
    assert_enqueued(
      worker: SetupWorker,
      args: %{user_id: user.id}
    )
    
    # Verify analytics job is scheduled
    assert_enqueued(
      worker: AnalyticsWorker,
      args: %{user_id: user.id, event: "user_created"}
    )
  end
end
```

## Common Testing Anti-Patterns

### ❌ Don't Test Oban Internals

```elixir
# BAD - Testing Oban's job storage
test "job is stored in database" do
  job = EmailWorker.new(%{user_id: 1})
  Oban.insert(job)
  
  # Don't test Oban's internal job storage
  assert Repo.get_by(Oban.Job, args: %{user_id: 1})
end

# GOOD - Test your business logic
test "sends welcome email" do
  user = insert(:user)
  job = EmailWorker.new(%{user_id: user.id, type: "welcome"})
  
  assert {:ok, _} = perform_job(EmailWorker, job.args)
  assert_email_sent(fn email -> assert email.to == [user.email] end)
end
```

### ❌ Don't Test Job Execution in Unit Tests

```elixir
# BAD - Testing actual job execution in unit tests
test "user creation triggers email" do
  attrs = %{name: "John", email: "john@example.com"}
  
  {:ok, user} = Accounts.create_user(attrs)
  
  # Don't wait for actual job execution
  :timer.sleep(100)
  assert_email_sent(fn email -> assert email.to == [user.email] end)
end

# GOOD - Test job enqueueing
test "user creation enqueues email job" do
  attrs = %{name: "John", email: "john@example.com"}
  
  {:ok, user} = Accounts.create_user(attrs)
  
  # Test that job was enqueued
  assert_enqueued(
    worker: EmailWorker,
    args: %{user_id: user.id, type: "welcome"}
  )
end
```

## Advanced Testing Patterns

### Testing with Different Queue Configurations

```elixir
# test/my_app/workers/priority_worker_test.exs
defmodule MyApp.Workers.PriorityWorkerTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workers.PriorityWorker

  test "high priority jobs are processed first" do
    # Enqueue low priority job
    low_priority_job = PriorityWorker.new(
      %{task: "low_priority"}, 
      priority: 3
    )
    
    # Enqueue high priority job
    high_priority_job = PriorityWorker.new(
      %{task: "high_priority"}, 
      priority: 1
    )
    
    # Insert both jobs
    Oban.insert(low_priority_job)
    Oban.insert(high_priority_job)
    
    # Verify high priority job is processed first
    assert_enqueued(worker: PriorityWorker, args: %{task: "high_priority"})
    assert_enqueued(worker: PriorityWorker, args: %{task: "low_priority"})
  end
end
```

### Testing Job Cancellation

```elixir
# test/my_app/jobs/cancellation_test.exs
defmodule MyApp.Jobs.CancellationTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workers.NewsletterWorker

  test "cancels pending newsletter jobs when user unsubscribes" do
    user = insert(:user)
    
    # Enqueue newsletter job
    job = NewsletterWorker.new(%{user_id: user.id})
    {:ok, inserted_job} = Oban.insert(job)
    
    # User unsubscribes
    MyApp.Newsletters.unsubscribe(user)
    
    # Verify job was cancelled
    cancelled_job = Repo.get(Oban.Job, inserted_job.id)
    assert cancelled_job.state == "cancelled"
  end
end
```

## Performance Testing for Jobs

```elixir
# test/my_app/workers/bulk_processor_test.exs
defmodule MyApp.Workers.BulkProcessorTest do
  use MyApp.DataCase, async: true
  
  alias MyApp.Workers.BulkProcessor

  @tag :performance
  test "processes large batches efficiently" do
    # Create large dataset
    import_batch = insert(:import_batch)
    records = insert_list(1000, :staging_record, import_batch: import_batch)
    
    # Measure job execution time
    start_time = System.monotonic_time()
    
    job = BulkProcessor.new(%{import_batch_id: import_batch.id})
    assert {:ok, _} = perform_job(BulkProcessor, job.args)
    
    end_time = System.monotonic_time()
    execution_time = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    # Assert reasonable performance (adjust threshold as needed)
    assert execution_time < 5000  # 5 seconds max
    
    # Verify all records were processed
    assert MyApp.People.count_people() == 1000
  end
end
```

## Key Testing Takeaways

1. **Use `Oban.Testing`** - Provides `assert_enqueued` and `perform_job` helpers
2. **Test job enqueueing separately from execution** - Unit tests verify jobs are enqueued, integration tests verify execution
3. **Test error handling** - Verify jobs handle failures gracefully and retry appropriately
4. **Test business logic, not Oban internals** - Focus on your worker's behavior, not Oban's job storage
5. **Use fixtures and factories** - Create consistent test data for jobs
6. **Test job dependencies** - Verify job workflows and sequences work correctly

## Commands for Development

```bash
# Run tests with Oban
mix test

# Run specific worker tests
mix test test/my_app/workers/

# Run tests with coverage
mix test --cover

# Check job queue status in development
iex -S mix
iex> Oban.config() |> Oban.peek_queue(:default)
```

Remember: Oban testing is about verifying your background job logic works correctly, not testing Oban itself. Focus on business logic, error handling, and job workflows rather than the underlying job execution infrastructure.