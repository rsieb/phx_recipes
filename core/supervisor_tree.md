# Supervisor Tree Recipe

## Introduction

Supervisor trees are the backbone of fault-tolerant Elixir applications. Supervisors monitor child processes and restart them when they fail, implementing the "let it crash" philosophy. This recipe shows how to design and implement robust supervisor hierarchies for Phoenix applications.

## Basic Supervisor

```elixir
defmodule MyApp.WorkerSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Worker processes
      {MyApp.CacheWorker, []},
      {MyApp.EmailSender, []},
      {MyApp.StatsCollector, []}
    ]

    # Restart strategy: if one child fails, restart only that child
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Application Supervisor with Phoenix

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      MyAppWeb.Telemetry,
      
      # Start the Ecto repository
      MyApp.Repo,
      
      # Start the PubSub system
      {Phoenix.PubSub, name: MyApp.PubSub},
      
      # Start Finch for HTTP requests
      {Finch, name: MyApp.Finch},
      
      # Start background job processor
      {Oban, Application.fetch_env!(:my_app, Oban)},
      
      # Start custom supervisors
      MyApp.ServiceSupervisor,
      MyApp.WorkerSupervisor,
      
      # Start the Endpoint (web server)
      MyAppWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

## Service Supervisor with Different Strategies

```elixir
defmodule MyApp.ServiceSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Critical services that must restart together
      {MyApp.DatabaseService, []},
      {MyApp.CacheService, []},
      {MyApp.MetricsService, []},
    ]

    # If one critical service fails, restart all of them
    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule MyApp.BackgroundJobSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Background job workers
      {MyApp.EmailWorker, []},
      {MyApp.ReportWorker, []},
      {MyApp.CleanupWorker, []},
    ]

    # Rest for one restart: if too many failures, stop the supervisor
    Supervisor.init(children, 
      strategy: :rest_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end
end
```

## Dynamic Supervisor for Runtime Children

```elixir
defmodule MyApp.ConnectionSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # API functions
  def start_connection(user_id) do
    child_spec = {MyApp.UserConnection, user_id}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_connection(user_id) do
    case find_connection(user_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  def list_connections do
    DynamicSupervisor.which_children(__MODULE__)
  end

  defp find_connection(user_id) do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.find_value(fn {_, pid, _, _} ->
      if GenServer.call(pid, :get_user_id) == user_id do
        pid
      end
    end)
  end
end

defmodule MyApp.UserConnection do
  use GenServer

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end

  def init(user_id) do
    {:ok, %{user_id: user_id, connected_at: DateTime.utc_now()}}
  end

  def handle_call(:get_user_id, _from, state) do
    {:reply, state.user_id, state}
  end

  defp via_tuple(user_id) do
    {:via, Registry, {MyApp.ConnectionRegistry, user_id}}
  end
end
```

## Supervisor with Task.Supervisor

```elixir
defmodule MyApp.TaskSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for process lookup
      {Registry, keys: :unique, name: MyApp.TaskRegistry},
      
      # Task supervisor for one-off tasks
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      
      # Dedicated supervisor for long-running tasks
      {MyApp.LongRunningTaskSupervisor, []},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule MyApp.LongRunningTaskSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Long-running background tasks
      {MyApp.DataSyncTask, []},
      {MyApp.HealthCheckTask, []},
      {MyApp.MetricsCollectionTask, []},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Usage module for task management
defmodule MyApp.TaskManager do
  def start_async_task(function) do
    Task.Supervisor.start_child(MyApp.TaskSupervisor, function)
  end

  def start_async_task(module, function, args) do
    Task.Supervisor.start_child(MyApp.TaskSupervisor, module, function, args)
  end

  def start_monitored_task(function) do
    Task.Supervisor.async_nolink(MyApp.TaskSupervisor, function)
  end

  def await_task(task, timeout \\ 5000) do
    Task.await(task, timeout)
  end
end
```

## Supervisor with PartitionSupervisor

```elixir
defmodule MyApp.PartitionedSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Partitioned supervisor for better concurrency
      {PartitionSupervisor,
       child_spec: {MyApp.Worker, []},
       name: MyApp.WorkerPartitionSupervisor,
       partitions: System.schedulers_online()},
      
      # Registry for process lookup
      {Registry, keys: :unique, name: MyApp.WorkerRegistry},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule MyApp.Worker do
  use GenServer

  def start_link(partition) do
    GenServer.start_link(__MODULE__, partition, 
      name: {:via, PartitionSupervisor, {MyApp.WorkerPartitionSupervisor, partition}})
  end

  def init(partition) do
    {:ok, %{partition: partition, jobs: []}}
  end

  def handle_call({:add_job, job}, _from, state) do
    new_state = %{state | jobs: [job | state.jobs]}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_jobs, _from, state) do
    {:reply, state.jobs, state}
  end
end

# Helper module for interacting with partitioned workers
defmodule MyApp.WorkerManager do
  def add_job(key, job) do
    partition = :erlang.phash2(key, System.schedulers_online())
    worker_pid = {:via, PartitionSupervisor, {MyApp.WorkerPartitionSupervisor, partition}}
    GenServer.call(worker_pid, {:add_job, job})
  end

  def get_jobs(key) do
    partition = :erlang.phash2(key, System.schedulers_online())
    worker_pid = {:via, PartitionSupervisor, {MyApp.WorkerPartitionSupervisor, partition}}
    GenServer.call(worker_pid, :get_jobs)
  end
end
```

## Supervisor with Circuit Breaker Pattern

```elixir
defmodule MyApp.ExternalServiceSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # External service connections with circuit breakers
      {MyApp.ApiClientSupervisor, []},
      {MyApp.DatabaseConnectionSupervisor, []},
      {MyApp.CacheConnectionSupervisor, []},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule MyApp.ApiClientSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # API clients with circuit breaker
      {MyApp.PaymentApiClient, []},
      {MyApp.EmailApiClient, []},
      {MyApp.AnalyticsApiClient, []},
    ]

    # If external services fail frequently, use rest_for_one
    # so dependent services are also restarted
    Supervisor.init(children, 
      strategy: :rest_for_one,
      max_restarts: 3,
      max_seconds: 60
    )
  end
end

defmodule MyApp.PaymentApiClient do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    state = %{
      circuit_breaker: :closed,
      failure_count: 0,
      last_failure_time: nil
    }
    
    {:ok, state}
  end

  def handle_call({:make_request, request}, _from, state) do
    case state.circuit_breaker do
      :open ->
        if should_try_request?(state) do
          # Try request and potentially close circuit
          result = make_api_request(request)
          handle_request_result(result, state)
        else
          {:reply, {:error, :circuit_breaker_open}, state}
        end
      
      :closed ->
        result = make_api_request(request)
        handle_request_result(result, state)
    end
  end

  defp handle_request_result({:ok, result}, state) do
    # Success: close circuit and reset failure count
    new_state = %{state | 
      circuit_breaker: :closed,
      failure_count: 0,
      last_failure_time: nil
    }
    {:reply, {:ok, result}, new_state}
  end

  defp handle_request_result({:error, reason}, state) do
    failure_count = state.failure_count + 1
    
    new_state = %{state |
      failure_count: failure_count,
      last_failure_time: DateTime.utc_now()
    }
    
    # Open circuit if too many failures
    new_state = if failure_count >= 3 do
      %{new_state | circuit_breaker: :open}
    else
      new_state
    end
    
    {:reply, {:error, reason}, new_state}
  end

  defp should_try_request?(state) do
    # Try again after 30 seconds
    DateTime.diff(DateTime.utc_now(), state.last_failure_time, :second) > 30
  end

  defp make_api_request(_request) do
    # Simulate API request
    if :rand.uniform() > 0.7 do
      {:ok, %{status: :success}}
    else
      {:error, :api_unavailable}
    end
  end
end
```

## Supervisor Testing

```elixir
defmodule MyApp.SupervisorTest do
  use ExUnit.Case, async: true

  test "supervisor starts all children" do
    # Start supervisor
    {:ok, supervisor} = MyApp.WorkerSupervisor.start_link([])
    
    # Check that all children are started
    children = Supervisor.which_children(supervisor)
    assert length(children) == 3
    
    # Verify each child is alive
    Enum.each(children, fn {_id, pid, _type, _modules} ->
      assert Process.alive?(pid)
    end)
    
    # Cleanup
    Supervisor.stop(supervisor)
  end

  test "supervisor restarts failed children" do
    {:ok, supervisor} = MyApp.WorkerSupervisor.start_link([])
    
    # Get initial children
    initial_children = Supervisor.which_children(supervisor)
    
    # Kill one child
    {_id, pid, _type, _modules} = List.first(initial_children)
    Process.exit(pid, :kill)
    
    # Wait for restart
    :timer.sleep(100)
    
    # Check that child was restarted
    new_children = Supervisor.which_children(supervisor)
    assert length(new_children) == length(initial_children)
    
    # Verify new child has different PID
    {_id, new_pid, _type, _modules} = List.first(new_children)
    assert new_pid != pid
    
    Supervisor.stop(supervisor)
  end

  test "dynamic supervisor manages children" do
    {:ok, _} = MyApp.ConnectionSupervisor.start_link([])
    
    # Start a connection
    {:ok, pid} = MyApp.ConnectionSupervisor.start_connection("user123")
    assert Process.alive?(pid)
    
    # Check connection is listed
    connections = MyApp.ConnectionSupervisor.list_connections()
    assert length(connections) == 1
    
    # Stop connection
    :ok = MyApp.ConnectionSupervisor.stop_connection("user123")
    
    # Verify connection is removed
    connections = MyApp.ConnectionSupervisor.list_connections()
    assert length(connections) == 0
  end

  test "supervisor handles maximum restart frequency" do
    # This test requires careful setup of restart limits
    # and timing to verify supervisor shutdown behavior
    {:ok, supervisor} = Supervisor.start_link([
      {MyApp.CrashingWorker, []}
    ], strategy: :one_for_one, max_restarts: 2, max_seconds: 5)
    
    # Cause multiple failures rapidly
    for _ <- 1..5 do
      [{_id, pid, _type, _modules}] = Supervisor.which_children(supervisor)
      Process.exit(pid, :kill)
      :timer.sleep(100)
    end
    
    # Supervisor should shutdown due to too many restarts
    refute Process.alive?(supervisor)
  end
end
```

## Supervisor Monitoring and Telemetry

```elixir
defmodule MyApp.SupervisorTelemetry do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Attach to supervisor events
    :telemetry.attach_many(
      "supervisor-events",
      [
        [:supervisor, :child_started],
        [:supervisor, :child_terminated],
        [:supervisor, :child_restarted]
      ],
      &handle_event/4,
      nil
    )
    
    {:ok, %{}}
  end

  def handle_event([:supervisor, :child_started], measurements, metadata, _config) do
    Logger.info("Child started: #{inspect(metadata.child_spec.id)}")
    
    # Send metrics to monitoring system
    :telemetry.execute([:my_app, :supervisor, :child_started], measurements, metadata)
  end

  def handle_event([:supervisor, :child_terminated], measurements, metadata, _config) do
    Logger.warn("Child terminated: #{inspect(metadata.child_spec.id)}, reason: #{inspect(metadata.reason)}")
    
    # Send alert if abnormal termination
    if metadata.reason not in [:normal, :shutdown] do
      send_alert("Child #{metadata.child_spec.id} crashed: #{metadata.reason}")
    end
    
    :telemetry.execute([:my_app, :supervisor, :child_terminated], measurements, metadata)
  end

  def handle_event([:supervisor, :child_restarted], measurements, metadata, _config) do
    Logger.info("Child restarted: #{inspect(metadata.child_spec.id)}")
    
    :telemetry.execute([:my_app, :supervisor, :child_restarted], measurements, metadata)
  end

  defp send_alert(message) do
    # Send to monitoring system, Slack, etc.
    MyApp.AlertManager.send_alert(message)
  end
end
```

## Tips & Best Practices

### Supervisor Design
- Use `:one_for_one` for independent processes
- Use `:one_for_all` for tightly coupled processes
- Use `:rest_for_one` for processes with dependencies
- Configure appropriate restart limits to prevent infinite restart loops

### Process Organization
- Group related processes under common supervisors
- Use dynamic supervisors for runtime process management
- Implement circuit breakers for external service connections
- Consider using `PartitionSupervisor` for high-concurrency scenarios

### Error Handling
- Design for failure - expect processes to crash
- Use specific restart strategies for different failure modes
- Implement proper logging and monitoring
- Test supervisor behavior under various failure conditions

### Performance
- Balance between fault tolerance and resource usage
- Use appropriate supervision strategies for your use case
- Monitor supervisor restart frequency
- Consider process pooling for high-throughput scenarios

## References

- [Supervisor Documentation](https://hexdocs.pm/elixir/Supervisor.html)
- [DynamicSupervisor Documentation](https://hexdocs.pm/elixir/DynamicSupervisor.html)
- [PartitionSupervisor Documentation](https://hexdocs.pm/elixir/PartitionSupervisor.html)
- [OTP Design Principles](https://www.erlang.org/doc/design_principles/des_princ.html)