# Application Module Recipe

## Introduction

The Application module is the entry point for your Phoenix application. It defines how your application starts, what processes it supervises, and how it handles configuration changes. This module is crucial for organizing your application's supervision tree and ensuring proper startup and shutdown behavior.

## Basic Phoenix Application

```elixir
defmodule MyApp.Application do
  @moduledoc false

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

## Application with Background Jobs

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core Phoenix components
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch},
      
      # Background job processing
      {Oban, Application.fetch_env!(:my_app, Oban)},
      
      # Custom supervisors
      MyApp.CacheSupervisor,
      MyApp.ServiceSupervisor,
      
      # Registry for dynamic processes
      {Registry, keys: :unique, name: MyApp.ProcessRegistry},
      
      # Dynamic supervisor for user sessions
      {DynamicSupervisor, name: MyApp.SessionSupervisor, strategy: :one_for_one},
      
      # Periodic tasks
      MyApp.PeriodicTasks,
      
      # External service monitors
      MyApp.ExternalServiceMonitor,
      
      # Web endpoint (should be last)
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

## Application with Clustering

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Setup clustering if configured
    setup_clustering()
    
    children = [
      # Core components
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch},
      
      # Clustering components
      {Cluster.Supervisor, [topologies(), [name: MyApp.ClusterSupervisor]]},
      
      # Distributed cache
      {Cachex, name: :distributed_cache, options: [
        expiration: [default: :timer.hours(1)],
        limit: [size: 1000, reclaim: 0.5]
      ]},
      
      # Leader election for singleton processes
      {MyApp.LeaderElection, []},
      
      # Application-specific supervisors
      MyApp.ServiceSupervisor,
      MyApp.WorkerSupervisor,
      
      # Web endpoint
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp setup_clustering do
    case Application.get_env(:my_app, :clustering_enabled) do
      true ->
        # Set up node name and cookie
        node_name = System.get_env("NODE_NAME") || "my_app@localhost"
        cookie = System.get_env("ERLANG_COOKIE") || :my_app_cookie
        
        Node.set_cookie(cookie)
        
        # Start distribution if not already started
        unless Node.alive?() do
          case Node.start(String.to_atom(node_name)) do
            {:ok, _} -> :ok
            {:error, reason} -> 
              IO.puts("Failed to start node: #{reason}")
          end
        end
        
      _ ->
        :ok
    end
  end

  defp topologies do
    Application.get_env(:my_app, :cluster_topologies, [])
  end
end
```

## Application with Health Checks

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core components
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch},
      
      # Health check system
      MyApp.HealthCheck,
      
      # Metrics collection
      MyApp.MetricsCollector,
      
      # Application services
      MyApp.ServiceSupervisor,
      
      # Web endpoint
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Perform post-startup checks
        post_startup_checks()
        {:ok, pid}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @impl true
  def prep_stop(state) do
    # Graceful shutdown preparation
    IO.puts("Preparing application for shutdown...")
    
    # Stop accepting new connections
    MyAppWeb.Endpoint.stop()
    
    # Wait for ongoing requests to complete
    :timer.sleep(5_000)
    
    # Clean up resources
    cleanup_resources()
    
    state
  end

  @impl true
  def stop(_state) do
    IO.puts("Application stopped")
    :ok
  end

  defp post_startup_checks do
    # Verify database connectivity
    case MyApp.Repo.query("SELECT 1") do
      {:ok, _} -> 
        IO.puts("Database connection verified")
      {:error, reason} -> 
        IO.puts("Database connection failed: #{reason}")
    end
    
    # Verify external services
    spawn(fn -> verify_external_services() end)
    
    # Register health check endpoints
    register_health_checks()
  end

  defp verify_external_services do
    external_services = [
      {"Redis", fn -> MyApp.Redis.ping() end},
      {"Email Service", fn -> MyApp.Email.health_check() end},
      {"Payment API", fn -> MyApp.Payment.health_check() end}
    ]
    
    Enum.each(external_services, fn {name, check_fn} ->
      case check_fn.() do
        :ok -> IO.puts("#{name} is healthy")
        {:error, reason} -> IO.puts("#{name} health check failed: #{reason}")
      end
    end)
  end

  defp register_health_checks do
    MyApp.HealthCheck.register_check(:database, fn ->
      case MyApp.Repo.query("SELECT 1") do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
    
    MyApp.HealthCheck.register_check(:pubsub, fn ->
      case Phoenix.PubSub.local_broadcast(MyApp.PubSub, "health_check", :ping) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp cleanup_resources do
    # Close database connections
    MyApp.Repo.disconnect_all()
    
    # Clear caches
    MyApp.Cache.clear_all()
    
    # Stop background processes
    MyApp.BackgroundWorker.stop()
  end
end
```

## Application with Feature Flags

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Initialize feature flags
    initialize_feature_flags()
    
    children = build_child_specs()

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp initialize_feature_flags do
    # Load feature flags from configuration or external service
    feature_flags = Application.get_env(:my_app, :feature_flags, %{})
    
    # Initialize feature flag store
    :ets.new(:feature_flags, [:set, :public, :named_table])
    
    Enum.each(feature_flags, fn {flag, enabled} ->
      :ets.insert(:feature_flags, {flag, enabled})
    end)
  end

  defp build_child_specs do
    base_children = [
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch}
    ]
    
    # Add optional children based on feature flags
    optional_children = [
      {feature_enabled?(:background_jobs), {Oban, oban_config()}},
      {feature_enabled?(:metrics), MyApp.MetricsCollector},
      {feature_enabled?(:caching), MyApp.CacheManager},
      {feature_enabled?(:real_time), MyApp.RealtimeManager},
      {feature_enabled?(:analytics), MyApp.AnalyticsCollector}
    ]
    
    # Filter and add enabled optional children
    enabled_children = 
      optional_children
      |> Enum.filter(fn {enabled, _child} -> enabled end)
      |> Enum.map(fn {_enabled, child} -> child end)
    
    # Always include the web endpoint
    all_children = base_children ++ enabled_children ++ [MyAppWeb.Endpoint]
    
    all_children
  end

  defp feature_enabled?(flag) do
    case :ets.lookup(:feature_flags, flag) do
      [{^flag, enabled}] -> enabled
      [] -> false
    end
  end

  defp oban_config do
    Application.get_env(:my_app, Oban, [])
  end
end
```

## Application with Environment-Specific Configuration

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Validate environment configuration
    validate_environment()
    
    children = environment_specific_children()

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp validate_environment do
    required_env_vars = [
      "DATABASE_URL",
      "SECRET_KEY_BASE"
    ]
    
    missing_vars = 
      required_env_vars
      |> Enum.filter(fn var -> System.get_env(var) == nil end)
    
    unless Enum.empty?(missing_vars) do
      raise "Missing required environment variables: #{Enum.join(missing_vars, ", ")}"
    end
    
    # Environment-specific validations
    case Mix.env() do
      :prod -> validate_production_config()
      :dev -> validate_development_config()
      :test -> validate_test_config()
    end
  end

  defp environment_specific_children do
    base_children = [
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch}
    ]
    
    env_children = case Mix.env() do
      :prod -> production_children()
      :dev -> development_children()
      :test -> test_children()
    end
    
    base_children ++ env_children ++ [MyAppWeb.Endpoint]
  end

  defp production_children do
    [
      # Production-specific services
      {Oban, Application.fetch_env!(:my_app, Oban)},
      MyApp.MetricsCollector,
      MyApp.HealthMonitor,
      MyApp.LogAggregator,
      
      # SSL certificate management
      MyApp.SSLManager,
      
      # Performance monitoring
      MyApp.PerformanceMonitor
    ]
  end

  defp development_children do
    [
      # Development-specific services
      MyApp.DevTools,
      MyApp.CodeReloader,
      
      # Optional background jobs for development
      if Application.get_env(:my_app, :dev_background_jobs, false) do
        {Oban, Application.fetch_env!(:my_app, Oban)}
      end
    ]
    |> Enum.filter(& &1)  # Remove nil values
  end

  defp test_children do
    [
      # Test-specific services
      MyApp.TestHelper,
      MyApp.DataSeeder
    ]
  end

  defp validate_production_config do
    # Ensure SSL is enabled
    unless Application.get_env(:my_app, MyAppWeb.Endpoint)[:https] do
      raise "HTTPS must be enabled in production"
    end
    
    # Validate database pool size
    pool_size = Application.get_env(:my_app, MyApp.Repo)[:pool_size]
    if pool_size < 10 do
      IO.puts("Warning: Database pool size is quite small for production (#{pool_size})")
    end
  end

  defp validate_development_config do
    # Development-specific validations
    :ok
  end

  defp validate_test_config do
    # Test-specific validations
    :ok
  end
end
```

## Application with Graceful Shutdown

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Setup signal handling for graceful shutdown
    setup_signal_handlers()
    
    children = [
      MyAppWeb.Telemetry,
      MyApp.Repo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Finch, name: MyApp.Finch},
      
      # Graceful shutdown manager
      MyApp.GracefulShutdown,
      
      # Connection drainer
      MyApp.ConnectionDrainer,
      
      # Application services
      MyApp.ServiceSupervisor,
      
      # Web endpoint
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @impl true
  def prep_stop(state) do
    IO.puts("Initiating graceful shutdown...")
    
    # Stop accepting new connections
    MyApp.GracefulShutdown.stop_accepting_connections()
    
    # Wait for existing connections to complete
    MyApp.ConnectionDrainer.drain_connections()
    
    # Stop background workers
    MyApp.BackgroundWorker.stop_all()
    
    # Final cleanup
    MyApp.Cleanup.perform()
    
    state
  end

  defp setup_signal_handlers do
    # Handle SIGTERM gracefully
    spawn(fn ->
      Process.flag(:trap_exit, true)
      receive do
        {:signal, :sigterm} ->
          IO.puts("Received SIGTERM, initiating graceful shutdown")
          System.stop(0)
      end
    end)
  end
end
```

## Application Testing

```elixir
defmodule MyApp.ApplicationTest do
  use ExUnit.Case, async: false
  
  test "application starts successfully" do
    # The application should already be started by the test suite
    # We can verify that key processes are running
    assert Process.whereis(MyApp.Repo) != nil
    assert Process.whereis(MyApp.PubSub) != nil
    assert Process.whereis(MyAppWeb.Endpoint) != nil
  end
  
  test "all supervised children are running" do
    # Get the main supervisor
    supervisor = Process.whereis(MyApp.Supervisor)
    assert supervisor != nil
    
    # Check that all children are running
    children = Supervisor.which_children(supervisor)
    
    Enum.each(children, fn {_id, pid, _type, _modules} ->
      assert Process.alive?(pid)
    end)
  end
  
  test "application handles configuration changes" do
    # Test config_change callback
    result = MyApp.Application.config_change([port: 4001], [], [])
    assert result == :ok
  end
  
  test "health checks are registered" do
    # Verify that health checks are available
    health_checks = MyApp.HealthCheck.list_checks()
    assert Enum.member?(health_checks, :database)
    assert Enum.member?(health_checks, :pubsub)
  end
end
```

## Tips & Best Practices

### Startup Order
- Start infrastructure services first (database, PubSub, cache)
- Start application services in dependency order
- Start the web endpoint last to ensure everything is ready

### Error Handling
- Validate configuration early in the startup process
- Use proper supervisor strategies for different types of processes
- Implement graceful shutdown for stateful processes

### Environment Configuration
- Use environment-specific child specifications
- Validate required environment variables at startup
- Provide sensible defaults for development

### Monitoring and Health Checks
- Implement comprehensive health checks
- Set up proper logging and metrics collection
- Monitor supervisor restart rates

### Testing
- Test the application startup process
- Verify all required processes are running
- Test configuration changes and error scenarios

## References

- [Application Documentation](https://hexdocs.pm/elixir/Application.html)
- [Phoenix Application Structure](https://hexdocs.pm/phoenix/Phoenix.html)
- [Supervisor Documentation](https://hexdocs.pm/elixir/Supervisor.html)
- [OTP Application Design](https://www.erlang.org/doc/design_principles/applications.html)