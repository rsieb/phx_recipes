# WebSocket Patterns Recipe

## Introduction

WebSockets enable real-time, bidirectional communication between clients and servers. This recipe covers advanced WebSocket patterns beyond basic Phoenix Channels, including Presence tracking, real-time collaboration, connection management, rate limiting, and binary protocols following Phoenix best practices.

## Advanced Channel Patterns

### Multi-Room Channel Management

```elixir
defmodule MyAppWeb.RoomChannel do
  use MyAppWeb, :channel
  require Logger

  # Join multiple rooms per socket
  def join("room:" <> room_id, %{"token" => token}, socket) do
    case verify_room_access(token, room_id) do
      {:ok, user} ->
        socket = 
          socket
          |> assign(:user, user)
          |> assign(:room_id, room_id)
          |> track_user_presence()

        send(self(), :after_join)
        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  def handle_info(:after_join, socket) do
    # Broadcast user joined event
    broadcast!(socket, "user_joined", %{
      user: socket.assigns.user,
      online_count: get_online_count(socket)
    })

    # Send room state to new user
    push(socket, "room_state", get_room_state(socket.assigns.room_id))
    
    {:noreply, socket}
  end

  # Handle real-time messaging
  def handle_in("new_message", %{"body" => body}, socket) do
    user = socket.assigns.user
    room_id = socket.assigns.room_id

    case create_message(room_id, user.id, body) do
      {:ok, message} ->
        message_data = %{
          id: message.id,
          body: message.body,
          user: %{id: user.id, name: user.name},
          inserted_at: message.inserted_at
        }

        broadcast!(socket, "new_message", message_data)
        {:reply, {:ok, message_data}, socket}

      {:error, changeset} ->
        {:reply, {:error, format_errors(changeset)}, socket}
    end
  end

  # Handle typing indicators
  def handle_in("typing", %{"typing" => typing}, socket) do
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
      broadcast_from!(socket, "user_typing", %{
        user_id: socket.assigns.user.id,
        typing: false
      })
      
      socket = assign(socket, :typing, false)
    end

    {:noreply, socket}
  end

  # Clean up on disconnect
  def terminate(_reason, socket) do
    if socket.assigns[:user] do
      broadcast!(socket, "user_left", %{
        user: socket.assigns.user,
        online_count: get_online_count(socket) - 1
      })
    end

    :ok
  end

  defp verify_room_access(token, room_id) do
    # Implement token verification and room access logic
    case MyApp.Auth.verify_token(token) do
      {:ok, user} ->
        if MyApp.Rooms.user_can_access?(user, room_id) do
          {:ok, user}
        else
          {:error, "access_denied"}
        end

      {:error, _} ->
        {:error, "invalid_token"}
    end
  end

  defp track_user_presence(socket) do
    user = socket.assigns.user
    
    MyAppWeb.Presence.track(socket, user.id, %{
      name: user.name,
      avatar: user.avatar,
      joined_at: System.system_time(:second)
    })

    socket
  end

  defp get_online_count(socket) do
    MyAppWeb.Presence.list(socket)
    |> Map.keys()
    |> length()
  end

  defp get_room_state(room_id) do
    %{
      recent_messages: MyApp.Messages.get_recent_messages(room_id, 50),
      room_info: MyApp.Rooms.get_room!(room_id)
    }
  end

  defp create_message(room_id, user_id, body) do
    MyApp.Messages.create_message(%{
      room_id: room_id,
      user_id: user_id,
      body: body
    })
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end
end
```

### Presence Tracking

```elixir
defmodule MyAppWeb.Presence do
  use Phoenix.Presence,
    otp_app: :my_app,
    pubsub_server: MyApp.PubSub

  # Custom presence tracking
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

  def set_user_typing(socket, user_id, typing) do
    update(socket, user_id, fn meta ->
      Map.put(meta, :typing, typing)
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

  def get_typing_users(topic) do
    list(topic)
    |> Enum.filter(fn {_user_id, %{metas: [meta | _]}} ->
      meta.typing == true
    end)
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      %{user_id: user_id, name: meta.name}
    end)
  end

  def user_count(topic) do
    list(topic)
    |> Map.keys()
    |> length()
  end
end

# Presence-aware channel
defmodule MyAppWeb.CollaborationChannel do
  use MyAppWeb, :channel
  alias MyAppWeb.Presence

  def join("collaboration:" <> document_id, _params, socket) do
    send(self(), :after_join)
    
    socket = 
      socket
      |> assign(:document_id, document_id)
      |> assign(:user, socket.assigns.current_user)

    {:ok, socket}
  end

  def handle_info(:after_join, socket) do
    user = socket.assigns.user
    document_id = socket.assigns.document_id

    # Track user presence
    Presence.track_user(socket, user.id, %{
      name: user.name,
      cursor_position: nil,
      selection: nil
    })

    # Send current presence list to new user
    presence_list = Presence.get_online_users("collaboration:#{document_id}")
    push(socket, "presence_state", %{users: presence_list})

    {:noreply, socket}
  end

  def handle_in("cursor_move", %{"position" => position}, socket) do
    user_id = socket.assigns.user.id
    
    Presence.update(socket, user_id, fn meta ->
      Map.put(meta, :cursor_position, position)
    end)

    {:noreply, socket}
  end

  def handle_in("text_selection", %{"selection" => selection}, socket) do
    user_id = socket.assigns.user.id
    
    Presence.update(socket, user_id, fn meta ->
      Map.put(meta, :selection, selection)
    end)

    {:noreply, socket}
  end
end
```

## Real-Time Collaboration

### Operational Transform for Document Editing

```elixir
defmodule MyApp.OperationalTransform do
  @moduledoc """
  Implements operational transformation for real-time collaborative editing.
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

  def transform(op1, op2) when op1.type == :insert and op2.type == :insert do
    cond do
      op1.position <= op2.position ->
        {op1, %{op2 | position: op2.position + op1.length}}

      op1.position > op2.position ->
        {%{op1 | position: op1.position + op2.length}, op2}
    end
  end

  def transform(op1, op2) when op1.type == :delete and op2.type == :delete do
    cond do
      op1.position + op1.length <= op2.position ->
        {op1, %{op2 | position: op2.position - op1.length}}

      op2.position + op2.length <= op1.position ->
        {%{op1 | position: op1.position - op2.length}, op2}

      # Overlapping deletes - more complex logic needed
      true ->
        transform_overlapping_deletes(op1, op2)
    end
  end

  def transform(op1, op2) when op1.type == :insert and op2.type == :delete do
    cond do
      op1.position <= op2.position ->
        {op1, %{op2 | position: op2.position + op1.length}}

      op1.position > op2.position + op2.length ->
        {%{op1 | position: op1.position - op2.length}, op2}

      true ->
        {%{op1 | position: op2.position}, op2}
    end
  end

  def transform(op1, op2) when op1.type == :delete and op2.type == :insert do
    {op2_prime, op1_prime} = transform(op2, op1)
    {op1_prime, op2_prime}
  end

  defp transform_overlapping_deletes(op1, op2) do
    # Simplified overlapping delete handling
    # In production, you'd want more sophisticated conflict resolution
    start1 = op1.position
    end1 = op1.position + op1.length
    start2 = op2.position
    end2 = op2.position + op2.length

    new_start = min(start1, start2)
    new_end = max(end1, end2)
    new_length = new_end - new_start

    merged_delete = %{op1 | position: new_start, length: new_length}
    {merged_delete, nil}
  end

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

  def join("document:" <> doc_id, _params, socket) do
    case Documents.get_document(doc_id) do
      {:ok, document} ->
        socket = 
          socket
          |> assign(:document_id, doc_id)
          |> assign(:document, document)
          |> assign(:version, document.version)

        send(self(), :after_join)
        {:ok, socket}

      {:error, :not_found} ->
        {:error, %{reason: "Document not found"}}
    end
  end

  def handle_info(:after_join, socket) do
    # Send current document state
    push(socket, "document_state", %{
      content: socket.assigns.document.content,
      version: socket.assigns.version
    })

    {:noreply, socket}
  end

  def handle_in("operation", %{"op" => op_data, "version" => client_version}, socket) do
    current_version = socket.assigns.version
    document_id = socket.assigns.document_id

    with {:ok, operation} <- parse_operation(op_data),
         {:ok, transformed_op} <- transform_operation(operation, client_version, current_version, document_id),
         {:ok, new_content} <- apply_operation_to_document(transformed_op, document_id),
         {:ok, _document} <- Documents.update_document_content(document_id, new_content, current_version + 1) do

      # Broadcast operation to other clients
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

  defp parse_operation(%{"type" => "insert", "position" => pos, "content" => content}) do
    {:ok, OperationalTransform.new_insert(pos, content)}
  end

  defp parse_operation(%{"type" => "delete", "position" => pos, "length" => length}) do
    {:ok, OperationalTransform.new_delete(pos, length)}
  end

  defp parse_operation(_), do: {:error, "Invalid operation"}

  defp transform_operation(op, client_version, server_version, document_id) when client_version == server_version do
    {:ok, op}
  end

  defp transform_operation(op, client_version, server_version, document_id) when client_version < server_version do
    # Get operations between client and server version
    operations = Documents.get_operations_since_version(document_id, client_version)
    
    transformed_op = 
      Enum.reduce(operations, op, fn server_op, acc_op ->
        {transformed, _} = OperationalTransform.transform(acc_op, server_op)
        transformed
      end)

    {:ok, transformed_op}
  end

  defp transform_operation(_, _, _, _), do: {:error, "Version conflict"}

  defp apply_operation_to_document(operation, document_id) do
    case Documents.get_document(document_id) do
      {:ok, document} ->
        new_content = OperationalTransform.apply_operation(document.content, operation)
        {:ok, new_content}

      error ->
        error
    end
  end

  defp serialize_operation(%{type: type, position: pos, content: content, length: length}) do
    %{
      type: type,
      position: pos,
      content: content,
      length: length
    }
  end
end
```

## Connection Management

### Connection Health Monitoring

```elixir
defmodule MyAppWeb.ConnectionManager do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Monitor connections every 30 seconds
    :timer.send_interval(30_000, :check_connections)
    
    state = %{
      connections: %{},
      connection_count: 0,
      last_check: System.system_time(:second)
    }

    {:ok, state}
  end

  def track_connection(socket_id, metadata) do
    GenServer.cast(__MODULE__, {:track_connection, socket_id, metadata})
  end

  def untrack_connection(socket_id) do
    GenServer.cast(__MODULE__, {:untrack_connection, socket_id})
  end

  def get_connection_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def handle_cast({:track_connection, socket_id, metadata}, state) do
    connection_data = Map.merge(metadata, %{
      connected_at: System.system_time(:second),
      last_ping: System.system_time(:second)
    })

    new_connections = Map.put(state.connections, socket_id, connection_data)
    
    {:noreply, %{state | 
      connections: new_connections,
      connection_count: map_size(new_connections)
    }}
  end

  def handle_cast({:untrack_connection, socket_id}, state) do
    new_connections = Map.delete(state.connections, socket_id)
    
    {:noreply, %{state | 
      connections: new_connections,
      connection_count: map_size(new_connections)
    }}
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_connections: state.connection_count,
      connections_by_topic: group_by_topic(state.connections),
      avg_connection_duration: avg_connection_duration(state.connections),
      oldest_connection: oldest_connection(state.connections)
    }

    {:reply, stats, state}
  end

  def handle_info(:check_connections, state) do
    # Log connection statistics
    Logger.info("Active WebSocket connections: #{state.connection_count}")
    
    # Clean up stale connections (older than 1 hour without ping)
    current_time = System.system_time(:second)
    stale_threshold = current_time - 3600 # 1 hour

    fresh_connections = 
      Enum.filter(state.connections, fn {_id, conn} ->
        conn.last_ping > stale_threshold
      end)
      |> Enum.into(%{})

    new_state = %{state | 
      connections: fresh_connections,
      connection_count: map_size(fresh_connections),
      last_check: current_time
    }

    {:noreply, new_state}
  end

  defp group_by_topic(connections) do
    Enum.group_by(connections, fn {_id, conn} -> conn.topic end)
    |> Enum.map(fn {topic, conns} -> {topic, length(conns)} end)
    |> Enum.into(%{})
  end

  defp avg_connection_duration(connections) do
    if map_size(connections) == 0 do
      0
    else
      current_time = System.system_time(:second)
      
      total_duration = 
        Enum.reduce(connections, 0, fn {_id, conn}, acc ->
          acc + (current_time - conn.connected_at)
        end)

      total_duration / map_size(connections)
    end
  end

  defp oldest_connection(connections) do
    connections
    |> Enum.min_by(fn {_id, conn} -> conn.connected_at end, fn -> nil end)
  end
end

# Connection tracking in channels
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", MyAppWeb.RoomChannel
  channel "document:*", MyAppWeb.DocumentChannel

  def connect(%{"token" => token}, socket, _connect_info) do
    case MyApp.Auth.verify_socket_token(token) do
      {:ok, user} ->
        socket = 
          socket
          |> assign(:user, user)
          |> assign(:socket_id, generate_socket_id())

        # Track connection
        MyAppWeb.ConnectionManager.track_connection(socket.assigns.socket_id, %{
          user_id: user.id,
          topic: nil
        })

        {:ok, socket}

      {:error, _} ->
        :error
    end
  end

  def id(socket), do: "user_socket:#{socket.assigns.user.id}"

  defp generate_socket_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
```

### Graceful Disconnection Handling

```elixir
defmodule MyAppWeb.GracefulChannel do
  use MyAppWeb, :channel
  require Logger

  def join(topic, params, socket) do
    # Set up disconnect timer
    socket = 
      socket
      |> assign(:disconnect_timer, nil)
      |> assign(:reconnect_attempts, 0)

    {:ok, socket}
  end

  def handle_in("heartbeat", _params, socket) do
    # Cancel any pending disconnect
    if socket.assigns.disconnect_timer do
      Process.cancel_timer(socket.assigns.disconnect_timer)
    end

    # Reset reconnect attempts on successful heartbeat
    socket = assign(socket, :reconnect_attempts, 0)
    
    {:reply, {:ok, %{timestamp: System.system_time(:millisecond)}}, socket}
  end

  def handle_in("prepare_disconnect", _params, socket) do
    # Client is preparing to disconnect gracefully
    Logger.info("Client preparing graceful disconnect")
    
    # Save any pending state
    save_client_state(socket)
    
    {:reply, {:ok, %{message: "Ready for disconnect"}}, socket}
  end

  def handle_info(:disconnect_warning, socket) do
    # Warn client about impending disconnect
    push(socket, "disconnect_warning", %{
      timeout: 30_000,
      message: "Connection will be closed in 30 seconds due to inactivity"
    })

    # Set final disconnect timer
    timer = Process.send_after(self(), :force_disconnect, 30_000)
    socket = assign(socket, :disconnect_timer, timer)

    {:noreply, socket}
  end

  def handle_info(:force_disconnect, socket) do
    Logger.info("Force disconnecting inactive client")
    
    # Save state before closing
    save_client_state(socket)
    
    # Close the socket
    {:stop, :normal, socket}
  end

  def terminate(reason, socket) do
    Logger.info("Channel terminated: #{inspect(reason)}")
    
    # Clean up resources
    cleanup_resources(socket)
    
    # Update presence
    if socket.assigns[:user] do
      MyAppWeb.Presence.untrack(socket, socket.assigns.user.id)
    end

    # Notify other clients
    broadcast_from!(socket, "user_disconnected", %{
      user_id: socket.assigns[:user]&.id,
      reason: reason
    })

    :ok
  end

  defp save_client_state(socket) do
    if socket.assigns[:user] do
      # Save any important client state
      MyApp.UserSessions.save_session_state(socket.assigns.user.id, %{
        last_activity: System.system_time(:second),
        disconnect_reason: :graceful
      })
    end
  end

  defp cleanup_resources(socket) do
    # Clean up any allocated resources
    if socket.assigns[:resource_locks] do
      Enum.each(socket.assigns.resource_locks, &MyApp.ResourceManager.release_lock/1)
    end
  end
end
```

## Rate Limiting

### Connection-Level Rate Limiting

```elixir
defmodule MyAppWeb.RateLimiter do
  use GenServer
  require Logger

  defstruct [:max_requests, :window_ms, :requests, :cleanup_timer]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    max_requests = Keyword.get(opts, :max_requests, 100)
    window_ms = Keyword.get(opts, :window_ms, 60_000) # 1 minute

    state = %__MODULE__{
      max_requests: max_requests,
      window_ms: window_ms,
      requests: %{},
      cleanup_timer: schedule_cleanup(window_ms)
    }

    {:ok, state}
  end

  def check_rate_limit(client_id) do
    GenServer.call(__MODULE__, {:check_rate_limit, client_id})
  end

  def handle_call({:check_rate_limit, client_id}, _from, state) do
    current_time = System.system_time(:millisecond)
    window_start = current_time - state.window_ms

    # Get current requests for this client
    client_requests = Map.get(state.requests, client_id, [])
    
    # Filter out old requests
    recent_requests = Enum.filter(client_requests, &(&1 > window_start))
    
    if length(recent_requests) >= state.max_requests do
      {:reply, {:error, :rate_limited}, state}
    else
      # Add new request timestamp
      new_requests = [current_time | recent_requests]
      updated_requests = Map.put(state.requests, client_id, new_requests)
      
      {:reply, :ok, %{state | requests: updated_requests}}
    end
  end

  def handle_info(:cleanup, state) do
    current_time = System.system_time(:millisecond)
    window_start = current_time - state.window_ms

    # Clean up old requests
    cleaned_requests = 
      Enum.reduce(state.requests, %{}, fn {client_id, requests}, acc ->
        recent_requests = Enum.filter(requests, &(&1 > window_start))
        
        if recent_requests != [] do
          Map.put(acc, client_id, recent_requests)
        else
          acc
        end
      end)

    new_timer = schedule_cleanup(state.window_ms)
    
    {:noreply, %{state | requests: cleaned_requests, cleanup_timer: new_timer}}
  end

  defp schedule_cleanup(window_ms) do
    # Clean up every half window
    Process.send_after(self(), :cleanup, div(window_ms, 2))
  end
end

# Rate limiting middleware for channels
defmodule MyAppWeb.RateLimitedChannel do
  use MyAppWeb, :channel
  alias MyAppWeb.RateLimiter

  def handle_in(event, params, socket) do
    client_id = get_client_id(socket)
    
    case RateLimiter.check_rate_limit(client_id) do
      :ok ->
        handle_event(event, params, socket)

      {:error, :rate_limited} ->
        push(socket, "rate_limited", %{
          message: "Too many requests. Please slow down.",
          retry_after: 60
        })
        
        {:noreply, socket}
    end
  end

  defp handle_event("message", params, socket) do
    # Handle the actual message
    broadcast!(socket, "new_message", params)
    {:noreply, socket}
  end

  defp get_client_id(socket) do
    # Use user ID or socket ID for rate limiting
    socket.assigns[:user]&.id || socket.assigns[:socket_id] || "anonymous"
  end
end
```

## Binary Protocols

### Efficient Binary Message Handling

```elixir
defmodule MyAppWeb.BinaryChannel do
  use MyAppWeb, :channel
  require Logger

  def join("binary:" <> room_id, _params, socket) do
    socket = assign(socket, :room_id, room_id)
    {:ok, socket}
  end

  # Handle binary data (e.g., file uploads, images)
  def handle_in("upload_chunk", %{"chunk" => chunk_binary, "metadata" => metadata}, socket) when is_binary(chunk_binary) do
    case process_binary_chunk(chunk_binary, metadata, socket) do
      {:ok, result} ->
        {:reply, {:ok, result}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle audio/video streaming
  def handle_in("audio_data", audio_binary, socket) when is_binary(audio_binary) do
    # Process audio data
    case process_audio_stream(audio_binary, socket) do
      {:ok, processed_audio} ->
        # Broadcast to other clients
        broadcast_from!(socket, "audio_stream", processed_audio)
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # Handle compressed data
  def handle_in("compressed_data", compressed_binary, socket) when is_binary(compressed_binary) do
    try do
      decompressed = :zlib.uncompress(compressed_binary)
      data = :erlang.binary_to_term(decompressed)
      
      # Process decompressed data
      handle_decompressed_data(data, socket)
    rescue
      _ ->
        push(socket, "error", %{message: "Invalid compressed data"})
        {:noreply, socket}
    end
  end

  # Binary protocol for game state
  def handle_in("game_state", state_binary, socket) when is_binary(state_binary) do
    case decode_game_state(state_binary) do
      {:ok, game_state} ->
        # Validate and broadcast game state
        case validate_game_state(game_state, socket) do
          :ok ->
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

  defp process_binary_chunk(chunk, metadata, socket) do
    upload_id = metadata["upload_id"]
    chunk_index = metadata["chunk_index"]
    total_chunks = metadata["total_chunks"]

    # Store chunk
    case MyApp.Uploads.store_chunk(upload_id, chunk_index, chunk) do
      {:ok, _} ->
        # Check if upload is complete
        if chunk_index + 1 == total_chunks do
          case MyApp.Uploads.assemble_file(upload_id) do
            {:ok, file_path} ->
              {:ok, %{upload_complete: true, file_path: file_path}}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:ok, %{upload_complete: false, chunks_received: chunk_index + 1}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_audio_stream(audio_binary, socket) do
    user_id = socket.assigns.user.id
    
    # Apply audio processing (noise reduction, compression, etc.)
    processed_audio = 
      audio_binary
      |> apply_noise_reduction()
      |> compress_audio()

    {:ok, %{
      user_id: user_id,
      audio_data: processed_audio,
      timestamp: System.system_time(:millisecond)
    }}
  end

  defp handle_decompressed_data(data, socket) do
    case data do
      %{"type" => "bulk_update", "updates" => updates} ->
        process_bulk_updates(updates, socket)

      %{"type" => "file_transfer", "file_data" => file_data} ->
        process_file_transfer(file_data, socket)

      _ ->
        push(socket, "error", %{message: "Unknown data type"})
    end

    {:noreply, socket}
  end

  # Game state encoding/decoding for efficient transmission
  defp encode_game_state(%{player_positions: positions, game_objects: objects}) do
    # Pack positions as binary for efficiency
    position_binary = 
      Enum.reduce(positions, <<>>, fn {player_id, {x, y}}, acc ->
        acc <> <<player_id::32, x::float-32, y::float-32>>
      end)

    objects_binary = encode_game_objects(objects)
    
    # Header: position_count (4 bytes) + objects_count (4 bytes)
    position_count = map_size(positions)
    objects_count = length(objects)
    
    <<position_count::32, objects_count::32, position_binary::binary, objects_binary::binary>>
  end

  defp decode_game_state(<<position_count::32, objects_count::32, rest::binary>>) do
    case decode_positions(rest, position_count, %{}) do
      {:ok, positions, remaining} ->
        case decode_game_objects(remaining, objects_count, []) do
          {:ok, objects, _} ->
            {:ok, %{player_positions: positions, game_objects: objects}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_positions(binary, 0, acc), do: {:ok, acc, binary}
  
  defp decode_positions(<<player_id::32, x::float-32, y::float-32, rest::binary>>, count, acc) do
    new_acc = Map.put(acc, player_id, {x, y})
    decode_positions(rest, count - 1, new_acc)
  end

  defp decode_positions(_, _, _), do: {:error, "Invalid position data"}

  defp encode_game_objects(objects) do
    Enum.reduce(objects, <<>>, fn object, acc ->
      object_binary = encode_game_object(object)
      object_size = byte_size(object_binary)
      acc <> <<object_size::32, object_binary::binary>>
    end)
  end

  defp encode_game_object(%{type: type, x: x, y: y, data: data}) do
    data_binary = :erlang.term_to_binary(data)
    type_binary = Atom.to_string(type)
    type_size = byte_size(type_binary)
    
    <<type_size::16, type_binary::binary, x::float-32, y::float-32, data_binary::binary>>
  end

  defp decode_game_objects(binary, 0, acc), do: {:ok, Enum.reverse(acc), binary}
  
  defp decode_game_objects(<<object_size::32, object_data::binary-size(object_size), rest::binary>>, count, acc) do
    case decode_game_object(object_data) do
      {:ok, object} ->
        decode_game_objects(rest, count - 1, [object | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_game_objects(_, _, _), do: {:error, "Invalid objects data"}

  defp decode_game_object(<<type_size::16, type_binary::binary-size(type_size), x::float-32, y::float-32, data_binary::binary>>) do
    try do
      type = String.to_existing_atom(type_binary)
      data = :erlang.binary_to_term(data_binary)
      
      {:ok, %{type: type, x: x, y: y, data: data}}
    rescue
      _ -> {:error, "Invalid object data"}
    end
  end

  defp decode_game_object(_), do: {:error, "Malformed object"}

  defp validate_game_state(_game_state, _socket) do
    # Implement game state validation logic
    :ok
  end

  defp apply_noise_reduction(audio_binary) do
    # Implement audio processing
    audio_binary
  end

  defp compress_audio(audio_binary) do
    # Implement audio compression
    audio_binary
  end

  defp process_bulk_updates(_updates, _socket) do
    # Process bulk updates
    :ok
  end

  defp process_file_transfer(_file_data, _socket) do
    # Process file transfer
    :ok
  end
end
```

This comprehensive WebSocket patterns recipe provides production-ready patterns for advanced real-time communication in Phoenix applications, including presence tracking, collaborative editing, connection management, rate limiting, and efficient binary protocols.