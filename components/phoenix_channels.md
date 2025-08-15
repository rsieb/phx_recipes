# Phoenix Channels Recipe

## Introduction

Phoenix Channels enable real-time bidirectional communication between clients and servers using WebSockets. Channels are perfect for chat applications, live updates, collaborative features, and any scenario requiring real-time data synchronization across multiple connected clients.

## Basic Channel Setup

```elixir
# Socket definition
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  ## Channels
  channel "room:*", MyAppWeb.RoomChannel
  channel "user:*", MyAppWeb.UserChannel
  
  # Socket authentication
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(MyAppWeb.Endpoint, "user socket", token, max_age: 86400) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}
      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

# Basic channel
defmodule MyAppWeb.RoomChannel do
  use MyAppWeb, :channel

  @impl true
  def join("room:lobby", _payload, socket) do
    {:ok, socket}
  end

  def join("room:" <> room_id, payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("new_msg", %{"body" => body}, socket) do
    broadcast(socket, "new_msg", %{body: body})
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  defp authorized?(_payload) do
    true
  end
end
```

## Chat Channel with Presence

```elixir
defmodule MyAppWeb.ChatChannel do
  use MyAppWeb, :channel

  alias MyApp.{Chat, Presence}

  @impl true
  def join("chat:" <> room_id, %{"token" => token}, socket) do
    case verify_user_token(token) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:user, user)
          |> assign(:room_id, room_id)
        
        send(self(), :after_join)
        {:ok, socket}
      
      {:error, _} ->
        {:error, %{reason: "invalid_token"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track user presence
    {:ok, _} = Presence.track(socket, socket.assigns.user.id, %{
      name: socket.assigns.user.name,
      avatar: socket.assigns.user.avatar,
      online_at: inspect(System.system_time(:second))
    })
    
    # Send presence list to user
    push(socket, "presence_state", Presence.list(socket))
    
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_message", %{"message" => message}, socket) do
    user = socket.assigns.user
    room_id = socket.assigns.room_id
    
    case Chat.create_message(%{
      content: message,
      user_id: user.id,
      room_id: room_id
    }) do
      {:ok, message} ->
        # Load message with user for broadcasting
        message = Chat.get_message_with_user(message.id)
        
        broadcast(socket, "new_message", %{
          id: message.id,
          content: message.content,
          user: %{
            id: message.user.id,
            name: message.user.name,
            avatar: message.user.avatar
          },
          inserted_at: message.inserted_at
        })
        
        {:noreply, socket}
      
      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset.errors}}, socket}
    end
  end

  @impl true
  def handle_in("typing", %{"typing" => typing}, socket) do
    broadcast_from(socket, "user_typing", %{
      user_id: socket.assigns.user.id,
      typing: typing
    })
    
    {:noreply, socket}
  end

  @impl true
  def handle_in("delete_message", %{"message_id" => message_id}, socket) do
    case Chat.delete_message(message_id, socket.assigns.user.id) do
      {:ok, _} ->
        broadcast(socket, "message_deleted", %{message_id: message_id})
        {:noreply, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  defp verify_user_token(token) do
    case Phoenix.Token.verify(MyAppWeb.Endpoint, "user socket", token, max_age: 86400) do
      {:ok, user_id} ->
        case MyApp.Accounts.get_user(user_id) do
          nil -> {:error, "user_not_found"}
          user -> {:ok, user}
        end
      
      {:error, _} ->
        {:error, "invalid_token"}
    end
  end
end
```

## Game Channel with State Management

```elixir
defmodule MyAppWeb.GameChannel do
  use MyAppWeb, :channel

  alias MyApp.Games

  @impl true
  def join("game:" <> game_id, %{"player_token" => token}, socket) do
    case verify_player_token(token) do
      {:ok, player} ->
        case Games.join_game(game_id, player) do
          {:ok, game} ->
            socket =
              socket
              |> assign(:game_id, game_id)
              |> assign(:player, player)
              |> assign(:game, game)
            
            # Notify other players
            broadcast_from(socket, "player_joined", %{
              player: %{
                id: player.id,
                name: player.name,
                avatar: player.avatar
              }
            })
            
            {:ok, %{game: serialize_game(game)}, socket}
          
          {:error, reason} ->
            {:error, %{reason: reason}}
        end
      
      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl true
  def handle_in("make_move", %{"move" => move}, socket) do
    game_id = socket.assigns.game_id
    player = socket.assigns.player
    
    case Games.make_move(game_id, player.id, move) do
      {:ok, game} ->
        # Update socket state
        socket = assign(socket, :game, game)
        
        # Broadcast move to all players
        broadcast(socket, "move_made", %{
          player_id: player.id,
          move: move,
          game: serialize_game(game)
        })
        
        # Check for game end
        if Games.game_finished?(game) do
          broadcast(socket, "game_finished", %{
            winner: Games.get_winner(game),
            final_score: Games.get_score(game)
          })
        end
        
        {:noreply, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("request_game_state", _payload, socket) do
    {:reply, {:ok, %{game: serialize_game(socket.assigns.game)}}, socket}
  end

  @impl true
  def handle_in("send_chat", %{"message" => message}, socket) do
    player = socket.assigns.player
    
    broadcast(socket, "chat_message", %{
      player: %{
        id: player.id,
        name: player.name
      },
      message: message,
      timestamp: System.system_time(:second)
    })
    
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:game_id] && socket.assigns[:player] do
      Games.leave_game(socket.assigns.game_id, socket.assigns.player.id)
      
      broadcast_from(socket, "player_left", %{
        player_id: socket.assigns.player.id
      })
    end
    
    :ok
  end

  defp serialize_game(game) do
    %{
      id: game.id,
      status: game.status,
      players: Enum.map(game.players, fn player ->
        %{
          id: player.id,
          name: player.name,
          score: player.score
        }
      end),
      current_turn: game.current_turn,
      board: game.board,
      created_at: game.inserted_at
    }
  end

  defp verify_player_token(token) do
    case Phoenix.Token.verify(MyAppWeb.Endpoint, "player", token, max_age: 3600) do
      {:ok, player_id} ->
        case MyApp.Accounts.get_user(player_id) do
          nil -> {:error, "player_not_found"}
          player -> {:ok, player}
        end
      
      {:error, _} ->
        {:error, "invalid_token"}
    end
  end
end
```

## Channel with Authentication and Authorization

```elixir
defmodule MyAppWeb.AdminChannel do
  use MyAppWeb, :channel

  @impl true
  def join("admin:dashboard", _payload, socket) do
    if authorized_admin?(socket) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("admin:users", _payload, socket) do
    if authorized_admin?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Send initial dashboard data
    push(socket, "dashboard_data", get_dashboard_data())
    
    # Schedule periodic updates
    schedule_update()
    
    {:noreply, socket}
  end

  @impl true
  def handle_info(:update_dashboard, socket) do
    push(socket, "dashboard_update", get_dashboard_data())
    schedule_update()
    {:noreply, socket}
  end

  @impl true
  def handle_in("ban_user", %{"user_id" => user_id}, socket) do
    case MyApp.Accounts.ban_user(user_id) do
      {:ok, user} ->
        # Broadcast user banned to all admin channels
        MyAppWeb.Endpoint.broadcast("admin:users", "user_banned", %{
          user_id: user.id,
          banned_by: socket.assigns.user_id
        })
        
        {:reply, {:ok, %{status: "banned"}}, socket}
      
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("get_user_details", %{"user_id" => user_id}, socket) do
    case MyApp.Accounts.get_user_with_details(user_id) do
      nil ->
        {:reply, {:error, %{reason: "user_not_found"}}, socket}
      
      user ->
        {:reply, {:ok, serialize_user(user)}, socket}
    end
  end

  defp authorized_admin?(socket) do
    case MyApp.Accounts.get_user(socket.assigns.user_id) do
      %{role: "admin"} -> true
      _ -> false
    end
  end

  defp get_dashboard_data do
    %{
      total_users: MyApp.Accounts.count_users(),
      active_users: MyApp.Accounts.count_active_users(),
      revenue: MyApp.Billing.get_revenue_today(),
      system_health: MyApp.Monitoring.get_system_health()
    }
  end

  defp schedule_update do
    Process.send_after(self(), :update_dashboard, 30_000)  # 30 seconds
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      last_login: user.last_login,
      created_at: user.inserted_at
    }
  end
end
```

## Channel Testing

```elixir
defmodule MyAppWeb.RoomChannelTest do
  use MyAppWeb.ChannelCase

  setup do
    user = MyApp.AccountsFixtures.user_fixture()
    token = Phoenix.Token.sign(MyAppWeb.Endpoint, "user socket", user.id)
    
    {:ok, socket} = connect(MyAppWeb.UserSocket, %{"token" => token})
    {:ok, socket: socket, user: user}
  end

  test "joins room:lobby", %{socket: socket} do
    {:ok, _, socket} = subscribe_and_join(socket, MyAppWeb.RoomChannel, "room:lobby")
    assert socket.assigns.user_id
  end

  test "broadcasts new messages", %{socket: socket} do
    {:ok, _, socket} = subscribe_and_join(socket, MyAppWeb.RoomChannel, "room:lobby")
    
    ref = push(socket, "new_msg", %{"body" => "Hello World"})
    assert_reply ref, :ok
    assert_broadcast "new_msg", %{body: "Hello World"}
  end

  test "requires authentication for private rooms", %{socket: socket} do
    assert {:error, %{reason: "unauthorized"}} = 
      subscribe_and_join(socket, MyAppWeb.RoomChannel, "room:private")
  end

  test "handles presence updates", %{socket: socket, user: user} do
    {:ok, _, socket} = subscribe_and_join(socket, MyAppWeb.ChatChannel, "chat:general")
    
    # User should be tracked in presence
    assert_push "presence_state", %{^user.id => %{name: user.name}}
  end

  test "validates message content", %{socket: socket} do
    {:ok, _, socket} = subscribe_and_join(socket, MyAppWeb.ChatChannel, "chat:general")
    
    ref = push(socket, "new_message", %{"message" => ""})
    assert_reply ref, :error, %{errors: _}
  end

  test "handles disconnection cleanup", %{socket: socket} do
    {:ok, _, socket} = subscribe_and_join(socket, MyAppWeb.GameChannel, "game:123")
    
    # Simulate disconnection
    close(socket)
    
    # Verify cleanup happened
    assert_broadcast "player_left", %{player_id: _}
  end
end
```

## Channel Interceptors

```elixir
defmodule MyAppWeb.LoggingChannel do
  use MyAppWeb, :channel

  intercept ["new_message", "user_joined", "user_left"]

  @impl true
  def handle_out("new_message", payload, socket) do
    # Log message for analytics
    MyApp.Analytics.log_message(payload, socket.assigns.user_id)
    
    push(socket, "new_message", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_out("user_joined", payload, socket) do
    # Only send to users who are not the joining user
    if payload.user_id != socket.assigns.user_id do
      push(socket, "user_joined", payload)
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_out("user_left", payload, socket) do
    # Add timestamp to leave events
    payload_with_timestamp = Map.put(payload, :left_at, System.system_time(:second))
    
    push(socket, "user_left", payload_with_timestamp)
    {:noreply, socket}
  end
end
```

## Tips & Best Practices

### Channel Design
- Use specific channel topics for different features
- Implement proper authentication in socket connects
- Handle disconnections gracefully with cleanup
- Use presence tracking for user awareness

### Performance
- Batch updates when possible to reduce message volume
- Use interceptors for common message processing
- Implement rate limiting for channels
- Monitor channel memory usage

### Security
- Always validate user permissions before joining channels
- Sanitize all incoming messages
- Use tokens with appropriate expiration times
- Implement proper authorization for sensitive operations

### Testing
- Test both success and failure scenarios
- Test channel authentication and authorization
- Test presence tracking and cleanup
- Use channel case helpers for consistent testing

### Error Handling
- Provide meaningful error messages
- Handle network disconnections gracefully
- Implement retry logic for critical operations
- Log errors for debugging and monitoring

## References

- [Phoenix Channels Documentation](https://hexdocs.pm/phoenix/channels.html)
- [Phoenix.Socket Documentation](https://hexdocs.pm/phoenix/Phoenix.Socket.html)
- [Phoenix.Presence Documentation](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
- [Phoenix Channel Testing](https://hexdocs.pm/phoenix/Phoenix.ChannelTest.html)