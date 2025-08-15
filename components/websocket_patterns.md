# WebSocket Patterns Recipe

## Introduction

WebSockets enable real-time, bidirectional communication between clients and servers. While Phoenix Channels provide the foundation, this recipe covers advanced patterns for building scalable, robust real-time applications including presence tracking, collaborative editing, and efficient data protocols.

## When to Use Advanced WebSocket Patterns

**Use Presence tracking when:**
- Users need to see who else is online
- Building collaborative features (chat, editing)
- Creating social awareness in your app

**Use real-time collaboration when:**
- Multiple users edit shared documents
- Building multiplayer games or experiences
- Users need immediate feedback on others' actions

**Use connection management when:**
- Supporting thousands of concurrent users
- Network conditions are unreliable
- You need graceful degradation

**Use binary protocols when:**
- Sending large amounts of data (audio, video, game state)
- Bandwidth is limited
- Protocol efficiency matters for performance

## Presence Tracking Fundamentals

Phoenix Presence tracks user activity across distributed nodes, perfect for showing who's online or active in specific areas of your application.

```elixir
defmodule MyAppWeb.Presence do
  use Phoenix.Presence,
    otp_app: :my_app,
    pubsub_server: MyApp.PubSub

  def track_user(socket, user_id, metadata \\ %{}) do
    default_meta = %{
      joined_at: System.system_time(:second),
      typing: false,
      status: "online"
    }

    track(socket, user_id, Map.merge(default_meta, metadata))
  end

  def update_user_status(socket, user_id, status) do
    update(socket, user_id, fn meta ->
      Map.put(meta, :status, status)
    end)
  end

  def get_online_users(topic) do
    list(topic)
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      %{
        user_id: user_id,
        name: meta.name,
        status: meta.status,
        joined_at: meta.joined_at
      }
    end)
  end
end
```

**Why this works:** Presence automatically handles user tracking across clustered nodes, providing conflict-free replicated data types (CRDTs) for consistent state. Metadata lets you track additional user state beyond just online/offline.

**When to use:** Any time you need to show user activity, online status, or create social awareness. Essential for collaborative features.

## Real-Time Multi-User Chat

Building chat requires handling multiple users, message persistence, and typing indicators efficiently.

```elixir
defmodule MyAppWeb.RoomChannel do
  use MyAppWeb, :channel
  alias MyAppWeb.Presence

  def join("room:" <> room_id, %{"token" => token}, socket) do
    case verify_room_access(token, room_id) do
      {:ok, user} ->
        socket = 
          socket
          |> assign(:user, user)
          |> assign(:room_id, room_id)

        # Track user presence with metadata
        Presence.track_user(socket, user.id, %{
          name: user.name,
          avatar: user.avatar
        })

        send(self(), :after_join)
        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  def handle_info(:after_join, socket) do
    # Send room state to new user
    push(socket, "room_state", %{
      messages: get_recent_messages(socket.assigns.room_id),
      users: Presence.get_online_users("room:#{socket.assigns.room_id}")
    })

    # Notify others of new user
    broadcast_from!(socket, "user_joined", %{
      user: socket.assigns.user,
      online_count: Presence.user_count("room:#{socket.assigns.room_id}")
    })

    {:noreply, socket}
  end

  def handle_in("new_message", %{"body" => body}, socket) do
    case create_message(socket.assigns.room_id, socket.assigns.user.id, body) do
      {:ok, message} ->
        message_data = format_message(message, socket.assigns.user)
        broadcast!(socket, "new_message", message_data)
        {:reply, {:ok, message_data}, socket}

      {:error, changeset} ->
        {:reply, {:error, format_errors(changeset)}, socket}
    end
  end

  def handle_in("typing", %{"typing" => typing}, socket) do
    Presence.update_user_status(socket, socket.assigns.user.id, 
      if typing, do: "typing", else: "online")

    broadcast_from!(socket, "user_typing", %{
      user_id: socket.assigns.user.id,
      typing: typing
    })

    # Auto-stop typing after 3 seconds
    if typing do
      Process.send_after(self(), :stop_typing, 3000)
    end

    {:noreply, assign(socket, :typing, typing)}
  end

  def handle_info(:stop_typing, socket) do
    if socket.assigns[:typing] do
      Presence.update_user_status(socket, socket.assigns.user.id, "online")
      broadcast_from!(socket, "user_typing", %{
        user_id: socket.assigns.user.id,
        typing: false
      })
    end

    {:noreply, assign(socket, :typing, false)}
  end
end
```

**Why this works:** Presence handles user state distribution. Broadcasting separates local user actions from updates sent to others. Automatic typing timeouts prevent stuck "typing" indicators.

**When to use:** For any multi-user real-time communication where you need to track user activity and provide immediate feedback.

## Collaborative Document Editing

Real-time collaborative editing requires conflict resolution when multiple users edit simultaneously. Operational Transformation provides a solution.

```elixir
defmodule MyApp.OperationalTransform do
  @moduledoc """
  Handles conflict resolution for simultaneous edits.
  """

  defstruct [:type, :position, :content, :length]

  def new_insert(position, content) do
    %__MODULE__{
      type: :insert,
      position: position,
      content: content,
      length: String.length(content)
    }
  end

  def new_delete(position, length) do
    %__MODULE__{
      type: :delete,
      position: position,
      length: length
    }
  end

  # Transform two operations that happened concurrently
  def transform(op1, op2) when op1.type == :insert and op2.type == :insert do
    if op1.position <= op2.position do
      {op1, %{op2 | position: op2.position + op1.length}}
    else
      {%{op1 | position: op1.position + op2.length}, op2}
    end
  end

  # Apply operation to text
  def apply_operation(text, %{type: :insert, position: pos, content: content}) do
    {before, after} = String.split_at(text, pos)
    before <> content <> after
  end

  def apply_operation(text, %{type: :delete, position: pos, length: length}) do
    {before, rest} = String.split_at(text, pos)
    {_deleted, after} = String.split_at(rest, length)
    before <> after
  end
end

defmodule MyAppWeb.DocumentChannel do
  use MyAppWeb, :channel
  alias MyApp.{Documents, OperationalTransform}

  def handle_in("operation", %{"op" => op_data, "version" => client_version}, socket) do
    current_version = socket.assigns.version
    document_id = socket.assigns.document_id

    with {:ok, operation} <- parse_operation(op_data),
         {:ok, transformed_op} <- transform_operation(operation, client_version, current_version),
         {:ok, new_content} <- apply_and_save_operation(transformed_op, document_id) do

      # Broadcast to other clients
      broadcast_from!(socket, "operation", %{
        op: serialize_operation(transformed_op),
        version: current_version + 1,
        user_id: socket.assigns.current_user.id
      })

      socket = assign(socket, :version, current_version + 1)
      {:reply, {:ok, %{version: current_version + 1}}, socket}

    else
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
```

**Why this works:** Operational Transform ensures that concurrent edits result in the same final document state on all clients. Each operation is transformed relative to concurrent operations before being applied.

**When to use:** For collaborative text editing, code editors, or any scenario where multiple users modify shared content simultaneously.

## Connection Management and Recovery

Production WebSocket applications need robust connection handling for unreliable networks and server restarts.

```elixir
defmodule MyAppWeb.ResilientChannel do
  use MyAppWeb, :channel
  require Logger

  def join(topic, params, socket) do
    # Set up heartbeat monitoring
    socket = 
      socket
      |> assign(:heartbeat_timer, nil)
      |> assign(:reconnect_attempts, 0)
      |> schedule_heartbeat()

    {:ok, socket}
  end

  def handle_in("heartbeat", _params, socket) do
    # Reset heartbeat timer on successful ping
    socket = 
      socket
      |> cancel_heartbeat_timer()
      |> assign(:reconnect_attempts, 0)
      |> schedule_heartbeat()
    
    {:reply, {:ok, %{timestamp: System.system_time(:millisecond)}}, socket}
  end

  def handle_in("reconnect", %{"last_seen" => last_seen}, socket) do
    # Send missed events since last_seen timestamp
    missed_events = get_missed_events(socket.assigns.topic, last_seen)
    
    push(socket, "catch_up", %{events: missed_events})
    {:noreply, socket}
  end

  def handle_info(:heartbeat_timeout, socket) do
    Logger.warn("Heartbeat timeout for socket #{socket.id}")
    
    push(socket, "disconnect_warning", %{
      timeout: 30_000,
      message: "Connection unstable. Reconnecting..."
    })

    # Give client 30 seconds to respond before closing
    Process.send_after(self(), :force_disconnect, 30_000)
    {:noreply, socket}
  end

  def handle_info(:force_disconnect, socket) do
    Logger.info("Force disconnecting unresponsive client")
    {:stop, :normal, socket}
  end

  def terminate(reason, socket) do
    # Save state before disconnect
    save_client_state(socket)
    
    # Notify other users of disconnect
    broadcast_from!(socket, "user_disconnected", %{
      user_id: socket.assigns[:user]&.id,
      reason: reason
    })

    :ok
  end

  defp schedule_heartbeat(socket) do
    timer = Process.send_after(self(), :heartbeat_timeout, 60_000)
    assign(socket, :heartbeat_timer, timer)
  end

  defp cancel_heartbeat_timer(socket) do
    if timer = socket.assigns.heartbeat_timer do
      Process.cancel_timer(timer)
    end
    assign(socket, :heartbeat_timer, nil)
  end
end
```

**Why this works:** Heartbeat monitoring detects connection issues early. State persistence allows clients to resume seamlessly after reconnection. Graceful degradation maintains user experience during network issues.

**When to use:** For mission-critical real-time features where connection reliability is essential, or when supporting mobile clients with unreliable networks.

## Rate Limiting for Abuse Prevention

Prevent abuse and maintain performance by limiting message rates per user or connection.

```elixir
defmodule MyAppWeb.RateLimitedChannel do
  use MyAppWeb, :channel
  
  @rate_limit 10 # messages per minute
  @rate_window 60_000 # 1 minute in milliseconds

  def handle_in(event, params, socket) do
    case check_rate_limit(socket) do
      :ok ->
        handle_event(event, params, socket)

      {:error, :rate_limited} ->
        push(socket, "rate_limited", %{
          message: "Too many messages. Please slow down.",
          retry_after: calculate_retry_after(socket)
        })
        
        {:noreply, socket}
    end
  end

  defp check_rate_limit(socket) do
    user_id = socket.assigns.user.id
    current_time = System.system_time(:millisecond)
    window_start = current_time - @rate_window

    # Get recent messages from this user
    recent_count = count_recent_messages(user_id, window_start)

    if recent_count >= @rate_limit do
      {:error, :rate_limited}
    else
      # Track this message
      track_message(user_id, current_time)
      :ok
    end
  end

  defp handle_event("message", params, socket) do
    # Process the actual message
    broadcast!(socket, "new_message", params)
    {:noreply, socket}
  end
end
```

**Why this works:** Rate limiting prevents spam and abuse while maintaining good user experience for normal usage. Sliding window rate limiting is more user-friendly than fixed windows.

**When to use:** For any public-facing real-time features, especially chat, comments, or user-generated content.

## Binary Protocol for Game State

For applications that send frequent updates or large amounts of data, binary protocols are much more efficient than JSON.

```elixir
defmodule MyAppWeb.GameChannel do
  use MyAppWeb, :channel

  def handle_in("game_state", state_binary, socket) when is_binary(state_binary) do
    case decode_game_state(state_binary) do
      {:ok, game_state} ->
        case validate_game_state(game_state, socket) do
          :ok ->
            # Broadcast efficient binary format to other players
            encoded_state = encode_game_state(game_state)
            broadcast_from!(socket, "game_update", encoded_state)
            {:noreply, socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: reason}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Encode game state as compact binary format
  defp encode_game_state(%{player_positions: positions, objects: objects}) do
    # Pack positions: player_id (4 bytes) + x,y coordinates (8 bytes each)
    position_binary = 
      Enum.reduce(positions, <<>>, fn {player_id, {x, y}}, acc ->
        acc <> <<player_id::32, x::float-32, y::float-32>>
      end)

    position_count = map_size(positions)
    objects_count = length(objects)
    objects_binary = encode_objects(objects)
    
    # Header + data
    <<position_count::32, objects_count::32, position_binary::binary, objects_binary::binary>>
  end

  defp decode_game_state(<<position_count::32, objects_count::32, rest::binary>>) do
    case decode_positions(rest, position_count, %{}) do
      {:ok, positions, remaining} ->
        case decode_objects(remaining, objects_count, []) do
          {:ok, objects, _} ->
            {:ok, %{player_positions: positions, objects: objects}}
          error -> error
        end
      error -> error
    end
  end

  defp decode_positions(binary, 0, acc), do: {:ok, acc, binary}
  
  defp decode_positions(<<player_id::32, x::float-32, y::float-32, rest::binary>>, count, acc) do
    new_acc = Map.put(acc, player_id, {x, y})
    decode_positions(rest, count - 1, new_acc)
  end
end
```

**Why this works:** Binary encoding reduces bandwidth by 50-80% compared to JSON for structured data. Fixed-size fields enable efficient parsing. This is crucial for real-time games or high-frequency updates.

**When to use:** For games, real-time collaboration with frequent updates, or when bandwidth is limited (mobile, IoT devices).

## Common Pitfalls and Solutions

**Memory Leaks from Presence Tracking**
Always clean up presence when users disconnect. Use `terminate/2` callbacks to ensure cleanup happens even on abnormal disconnections.

**Broadcasting to Too Many Users**
Use topic segmentation (`"room:123"` instead of `"global"`) to limit broadcast scope. Consider using PubSub patterns for efficient routing.

**Overwhelming Clients with Updates**
Implement client-side throttling or server-side message coalescing for high-frequency updates. Not every state change needs immediate broadcasting.

**Ignoring Network Reliability**
Always implement reconnection logic, state synchronization after reconnect, and graceful degradation for poor connections.

## Performance Considerations

**Connection Scaling**
Each WebSocket connection consumes memory (~2KB per connection). Plan for memory usage: 1M connections ≈ 2GB RAM minimum.

**Broadcasting Efficiency**
Phoenix PubSub is highly optimized, but avoid sending large payloads to many users simultaneously. Consider message queuing for heavy broadcasts.

**State Management**
Keep channel state minimal. Store large state in ETS tables or external storage, keeping only references in channel state.

## Decision Criteria

**Use Presence when:**
- Users need social awareness
- Building collaborative features
- Tracking user activity across sessions

**Use real-time collaboration when:**
- Multiple users modify shared content
- Immediate feedback improves user experience
- Conflict resolution is important

**Use binary protocols when:**
- Sending > 1KB per message frequently
- Bandwidth is limited
- Protocol efficiency impacts user experience

**Implement rate limiting when:**
- Supporting public/untrusted users
- Preventing spam or abuse
- Maintaining quality of service

## References

- [Phoenix Presence Guide](https://hexdocs.pm/phoenix/presence.html)
- [Phoenix Channels Documentation](https://hexdocs.pm/phoenix/channels.html)
- [Operational Transform Theory](https://operational-transformation.github.io/)
- [WebSocket Best Practices](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers)