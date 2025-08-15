# GenServer Basics Recipe

## Introduction

GenServer is a behavior module for implementing stateful server processes in Elixir. It provides a standardized way to build concurrent, fault-tolerant processes that can maintain state, handle requests, and integrate seamlessly with supervision trees.

## Basic GenServer

```elixir
defmodule MyApp.Counter do
  use GenServer

  # Client API
  def start_link(initial_value) do
    GenServer.start_link(__MODULE__, initial_value, name: __MODULE__)
  end

  def get_value do
    GenServer.call(__MODULE__, :get_value)
  end

  def increment do
    GenServer.call(__MODULE__, :increment)
  end

  def decrement do
    GenServer.call(__MODULE__, :decrement)
  end

  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  # Server Callbacks
  @impl true
  def init(initial_value) do
    {:ok, initial_value}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:increment, _from, state) do
    new_state = state + 1
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call(:decrement, _from, state) do
    new_state = state - 1
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_cast(:reset, _state) do
    {:noreply, 0}
  end
end

# Usage:
# {:ok, _pid} = MyApp.Counter.start_link(0)
# MyApp.Counter.increment()  # => 1
# MyApp.Counter.get_value()  # => 1
# MyApp.Counter.reset()      # => :ok
```

## GenServer with Complex State

```elixir
defmodule MyApp.UserCache do
  use GenServer

  defstruct users: %{}, ttl: 300_000, timers: %{}

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_user(user_id) do
    GenServer.call(__MODULE__, {:get_user, user_id})
  end

  def put_user(user_id, user_data) do
    GenServer.call(__MODULE__, {:put_user, user_id, user_data})
  end

  def delete_user(user_id) do
    GenServer.call(__MODULE__, {:delete_user, user_id})
  end

  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    ttl = Keyword.get(opts, :ttl, 300_000)  # 5 minutes default
    
    state = %__MODULE__{
      users: %{},
      ttl: ttl,
      timers: %{}
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:get_user, user_id}, _from, state) do
    case Map.get(state.users, user_id) do
      nil ->
        {:reply, :not_found, state}
      user_data ->
        {:reply, {:ok, user_data}, state}
    end
  end

  @impl true
  def handle_call({:put_user, user_id, user_data}, _from, state) do
    # Cancel existing timer if any
    state = cancel_timer(state, user_id)
    
    # Set new timer for expiration
    timer_ref = Process.send_after(self(), {:expire_user, user_id}, state.ttl)
    
    new_state = %{state |
      users: Map.put(state.users, user_id, user_data),
      timers: Map.put(state.timers, user_id, timer_ref)
    }
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:delete_user, user_id}, _from, state) do
    state = cancel_timer(state, user_id)
    
    new_state = %{state |
      users: Map.delete(state.users, user_id),
      timers: Map.delete(state.timers, user_id)
    }
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_users: map_size(state.users),
      ttl: state.ttl,
      active_timers: map_size(state.timers)
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    # Cancel all timers
    Enum.each(state.timers, fn {_user_id, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)
    
    new_state = %{state |
      users: %{},
      timers: %{}
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:expire_user, user_id}, state) do
    new_state = %{state |
      users: Map.delete(state.users, user_id),
      timers: Map.delete(state.timers, user_id)
    }
    
    {:noreply, new_state}
  end

  defp cancel_timer(state, user_id) do
    case Map.get(state.timers, user_id) do
      nil -> state
      timer_ref ->
        Process.cancel_timer(timer_ref)
        %{state | timers: Map.delete(state.timers, user_id)}
    end
  end
end
```

## GenServer with External API Integration

```elixir
defmodule MyApp.WeatherService do
  use GenServer
  require Logger

  defstruct api_key: nil, base_url: nil, cache: %{}, last_updated: nil

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_weather(city) do
    GenServer.call(__MODULE__, {:get_weather, city}, 10_000)
  end

  def refresh_cache do
    GenServer.cast(__MODULE__, :refresh_cache)
  end

  def get_cache_info do
    GenServer.call(__MODULE__, :get_cache_info)
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    base_url = Keyword.get(opts, :base_url, "https://api.openweathermap.org/data/2.5")
    
    state = %__MODULE__{
      api_key: api_key,
      base_url: base_url,
      cache: %{},
      last_updated: nil
    }
    
    # Schedule periodic cache refresh
    schedule_cache_refresh()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:get_weather, city}, _from, state) do
    case Map.get(state.cache, city) do
      nil ->
        # Not in cache, fetch from API
        case fetch_weather_from_api(city, state) do
          {:ok, weather_data} ->
            new_cache = Map.put(state.cache, city, weather_data)
            new_state = %{state | cache: new_cache}
            {:reply, {:ok, weather_data}, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      cached_weather ->
        {:reply, {:ok, cached_weather}, state}
    end
  end

  @impl true
  def handle_call(:get_cache_info, _from, state) do
    info = %{
      cached_cities: Map.keys(state.cache),
      cache_size: map_size(state.cache),
      last_updated: state.last_updated
    }
    
    {:reply, info, state}
  end

  @impl true
  def handle_cast(:refresh_cache, state) do
    Logger.info("Refreshing weather cache...")
    
    # Clear cache and update timestamp
    new_state = %{state |
      cache: %{},
      last_updated: DateTime.utc_now()
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refresh_cache, state) do
    # Periodic cache refresh
    GenServer.cast(__MODULE__, :refresh_cache)
    
    # Schedule next refresh
    schedule_cache_refresh()
    
    {:noreply, state}
  end

  defp fetch_weather_from_api(city, state) do
    url = "#{state.base_url}/weather"
    
    params = [
      q: city,
      appid: state.api_key,
      units: "metric"
    ]
    
    case HTTPoison.get(url, [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            weather_data = %{
              temperature: data["main"]["temp"],
              description: data["weather"] |> List.first() |> Map.get("description"),
              humidity: data["main"]["humidity"],
              timestamp: DateTime.utc_now()
            }
            {:ok, weather_data}
          
          {:error, _} ->
            {:error, :invalid_response}
        end
      
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :city_not_found}
      
      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :unauthorized}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp schedule_cache_refresh do
    # Refresh cache every hour
    Process.send_after(self(), :refresh_cache, 3_600_000)
  end
end
```

## GenServer with Registry

```elixir
defmodule MyApp.GameRoom do
  use GenServer

  defstruct room_id: nil, players: [], game_state: :waiting, max_players: 4

  # Client API
  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  def join_room(room_id, player) do
    GenServer.call(via_tuple(room_id), {:join_room, player})
  end

  def leave_room(room_id, player_id) do
    GenServer.call(via_tuple(room_id), {:leave_room, player_id})
  end

  def get_room_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_room_state)
  end

  def start_game(room_id) do
    GenServer.call(via_tuple(room_id), :start_game)
  end

  def make_move(room_id, player_id, move) do
    GenServer.call(via_tuple(room_id), {:make_move, player_id, move})
  end

  # Registry helpers
  defp via_tuple(room_id) do
    {:via, Registry, {MyApp.GameRegistry, room_id}}
  end

  def list_active_rooms do
    Registry.select(MyApp.GameRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  def get_room_count do
    Registry.count(MyApp.GameRegistry)
  end

  # Server Callbacks
  @impl true
  def init(room_id) do
    state = %__MODULE__{
      room_id: room_id,
      players: [],
      game_state: :waiting,
      max_players: 4
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:join_room, player}, _from, state) do
    cond do
      length(state.players) >= state.max_players ->
        {:reply, {:error, :room_full}, state}
      
      player_already_in_room?(player.id, state.players) ->
        {:reply, {:error, :already_in_room}, state}
      
      state.game_state != :waiting ->
        {:reply, {:error, :game_in_progress}, state}
      
      true ->
        new_players = [player | state.players]
        new_state = %{state | players: new_players}
        
        # Broadcast to other players
        broadcast_to_players(new_state, {:player_joined, player})
        
        {:reply, {:ok, serialize_state(new_state)}, new_state}
    end
  end

  @impl true
  def handle_call({:leave_room, player_id}, _from, state) do
    case find_player(player_id, state.players) do
      nil ->
        {:reply, {:error, :player_not_found}, state}
      
      player ->
        new_players = List.delete(state.players, player)
        new_state = %{state | players: new_players}
        
        # If no players left, stop the room
        if Enum.empty?(new_players) do
          {:stop, :normal, :ok, new_state}
        else
          # Broadcast to remaining players
          broadcast_to_players(new_state, {:player_left, player_id})
          
          # If game was in progress, reset to waiting
          new_state = if state.game_state == :playing do
            %{new_state | game_state: :waiting}
          else
            new_state
          end
          
          {:reply, :ok, new_state}
        end
    end
  end

  @impl true
  def handle_call(:get_room_state, _from, state) do
    {:reply, serialize_state(state), state}
  end

  @impl true
  def handle_call(:start_game, _from, state) do
    cond do
      length(state.players) < 2 ->
        {:reply, {:error, :not_enough_players}, state}
      
      state.game_state != :waiting ->
        {:reply, {:error, :game_already_started}, state}
      
      true ->
        new_state = %{state | game_state: :playing}
        
        # Broadcast game start to all players
        broadcast_to_players(new_state, :game_started)
        
        {:reply, {:ok, serialize_state(new_state)}, new_state}
    end
  end

  @impl true
  def handle_call({:make_move, player_id, move}, _from, state) do
    if state.game_state == :playing do
      case find_player(player_id, state.players) do
        nil ->
          {:reply, {:error, :player_not_found}, state}
        
        _player ->
          # Process move (simplified)
          broadcast_to_players(state, {:move_made, player_id, move})
          {:reply, :ok, state}
      end
    else
      {:reply, {:error, :game_not_started}, state}
    end
  end

  # Helper functions
  defp player_already_in_room?(player_id, players) do
    Enum.any?(players, fn player -> player.id == player_id end)
  end

  defp find_player(player_id, players) do
    Enum.find(players, fn player -> player.id == player_id end)
  end

  defp broadcast_to_players(state, message) do
    Enum.each(state.players, fn player ->
      send(player.pid, message)
    end)
  end

  defp serialize_state(state) do
    %{
      room_id: state.room_id,
      players: Enum.map(state.players, fn player ->
        %{id: player.id, name: player.name}
      end),
      game_state: state.game_state,
      max_players: state.max_players
    }
  end
end
```

## GenServer with Periodic Tasks

```elixir
defmodule MyApp.HealthChecker do
  use GenServer
  require Logger

  defstruct services: [], check_interval: 60_000, last_check: nil

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_service(service_config) do
    GenServer.call(__MODULE__, {:add_service, service_config})
  end

  def remove_service(service_name) do
    GenServer.call(__MODULE__, {:remove_service, service_name})
  end

  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    services = Keyword.get(opts, :services, [])
    check_interval = Keyword.get(opts, :check_interval, 60_000)
    
    state = %__MODULE__{
      services: services,
      check_interval: check_interval,
      last_check: nil
    }
    
    # Schedule first health check
    schedule_health_check(1000)  # Check after 1 second
    
    {:ok, state}
  end

  @impl true
  def handle_call({:add_service, service_config}, _from, state) do
    new_services = [service_config | state.services]
    new_state = %{state | services: new_services}
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:remove_service, service_name}, _from, state) do
    new_services = Enum.reject(state.services, fn service ->
      service.name == service_name
    end)
    
    new_state = %{state | services: new_services}
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    # Return current health status of all services
    status = Enum.map(state.services, fn service ->
      %{
        name: service.name,
        status: service.last_status || :unknown,
        last_check: service.last_check,
        url: service.url
      }
    end)
    
    {:reply, status, state}
  end

  @impl true
  def handle_cast(:force_check, state) do
    new_state = perform_health_checks(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    Logger.info("Performing scheduled health check...")
    
    new_state = perform_health_checks(state)
    
    # Schedule next check
    schedule_health_check(state.check_interval)
    
    {:noreply, new_state}
  end

  defp perform_health_checks(state) do
    checked_services = Enum.map(state.services, fn service ->
      case check_service_health(service) do
        {:ok, status} ->
          %{service | last_status: status, last_check: DateTime.utc_now()}
        
        {:error, reason} ->
          Logger.error("Health check failed for #{service.name}: #{reason}")
          %{service | last_status: :down, last_check: DateTime.utc_now()}
      end
    end)
    
    %{state | services: checked_services, last_check: DateTime.utc_now()}
  end

  defp check_service_health(service) do
    case HTTPoison.get(service.url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        {:ok, :healthy}
      
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end
end
```

## GenServer Testing

```elixir
defmodule MyApp.CounterTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = MyApp.Counter.start_link(0)
    {:ok, counter: pid}
  end

  test "initial state is 0", %{counter: _counter} do
    assert MyApp.Counter.get_value() == 0
  end

  test "increment increases the value", %{counter: _counter} do
    assert MyApp.Counter.increment() == 1
    assert MyApp.Counter.increment() == 2
    assert MyApp.Counter.get_value() == 2
  end

  test "decrement decreases the value", %{counter: _counter} do
    MyApp.Counter.increment()
    assert MyApp.Counter.decrement() == 0
    assert MyApp.Counter.decrement() == -1
  end

  test "reset sets value to 0", %{counter: _counter} do
    MyApp.Counter.increment()
    MyApp.Counter.increment()
    MyApp.Counter.reset()
    assert MyApp.Counter.get_value() == 0
  end

  test "handles concurrent operations", %{counter: _counter} do
    # Start multiple processes that increment the counter
    tasks = for _ <- 1..100 do
      Task.async(fn -> MyApp.Counter.increment() end)
    end
    
    # Wait for all tasks to complete
    Task.await_many(tasks)
    
    assert MyApp.Counter.get_value() == 100
  end
end

defmodule MyApp.GameRoomTest do
  use ExUnit.Case, async: true

  setup do
    # Start the registry
    start_supervised!({Registry, keys: :unique, name: MyApp.GameRegistry})
    
    # Create a test room
    room_id = "test_room_#{:rand.uniform(1000)}"
    {:ok, room_pid} = MyApp.GameRoom.start_link(room_id)
    
    {:ok, room_id: room_id, room_pid: room_pid}
  end

  test "players can join and leave room", %{room_id: room_id} do
    player = %{id: 1, name: "Alice", pid: self()}
    
    # Join room
    {:ok, room_state} = MyApp.GameRoom.join_room(room_id, player)
    assert length(room_state.players) == 1
    
    # Leave room
    :ok = MyApp.GameRoom.leave_room(room_id, player.id)
    
    # Room should be empty (or stopped)
    assert catch_exit(MyApp.GameRoom.get_room_state(room_id))
  end

  test "room enforces max players", %{room_id: room_id} do
    # Add max players
    for i <- 1..4 do
      player = %{id: i, name: "Player#{i}", pid: self()}
      {:ok, _} = MyApp.GameRoom.join_room(room_id, player)
    end
    
    # Try to add one more player
    player = %{id: 5, name: "Player5", pid: self()}
    assert {:error, :room_full} = MyApp.GameRoom.join_room(room_id, player)
  end

  test "game can be started with enough players", %{room_id: room_id} do
    # Add two players
    for i <- 1..2 do
      player = %{id: i, name: "Player#{i}", pid: self()}
      {:ok, _} = MyApp.GameRoom.join_room(room_id, player)
    end
    
    # Start game
    {:ok, room_state} = MyApp.GameRoom.start_game(room_id)
    assert room_state.game_state == :playing
  end
end
```

## Tips & Best Practices

### State Management
- Keep state minimal and focused
- Use structs for complex state to ensure consistency
- Avoid large state that could cause memory issues
- Consider breaking large GenServers into smaller ones

### API Design
- Provide clear, consistent client functions
- Use descriptive function names
- Handle errors gracefully and return meaningful error tuples
- Consider timeout values for long-running operations

### Performance
- Use `handle_cast` for fire-and-forget operations
- Avoid blocking operations in handle_call
- Consider using `Task.async` for CPU-intensive work
- Monitor message queue length to detect bottlenecks

### Error Handling
- Implement proper error handling in all callbacks
- Use pattern matching for different error scenarios
- Log errors appropriately for debugging
- Design for graceful degradation

### Testing
- Test both success and failure scenarios
- Use `start_supervised!` in tests for proper cleanup
- Test concurrent access patterns
- Mock external dependencies

## References

- [GenServer Documentation](https://hexdocs.pm/elixir/GenServer.html)
- [OTP GenServer](https://www.erlang.org/doc/man/gen_server.html)
- [Registry Documentation](https://hexdocs.pm/elixir/Registry.html)
- [GenServer Best Practices](https://elixir-lang.org/getting-started/genserver.html)