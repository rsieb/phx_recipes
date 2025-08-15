# Phoenix LiveView Basics Recipe

## Introduction

Phoenix LiveView enables rich, real-time user experiences with server-rendered HTML. LiveView processes live on the server and push HTML diff updates to the client over WebSocket connections, providing interactive features without requiring client-side JavaScript frameworks.

## Basic LiveView Structure

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def handle_event("decrement", _params, socket) do
    {:noreply, update(socket, :count, &(&1 - 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="counter">
      <h1>Counter: <%= @count %></h1>
      <button phx-click="increment">+</button>
      <button phx-click="decrement">-</button>
    </div>
    """
  end
end
```

## LiveView with Form Handling

```elixir
defmodule MyAppWeb.UserFormLive do
  use MyAppWeb, :live_view

  alias MyApp.Accounts
  alias MyApp.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_user(%User{})
    
    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:user, %User{})
    
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user(user_params)
      |> Map.put(:action, :validate)
    
    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        socket =
          socket
          |> put_flash(:info, "User created successfully!")
          |> push_navigate(to: ~p"/users/#{user}")
        
        {:noreply, socket}
      
      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="user-form">
      <h1>Create User</h1>
      
      <.form 
        for={@changeset} 
        phx-change="validate" 
        phx-submit="save"
        class="space-y-4"
      >
        <div>
          <.label for={@changeset[:name].field}>Name</.label>
          <.input field={@changeset[:name]} type="text" required />
          <.error for={@changeset[:name]} />
        </div>
        
        <div>
          <.label for={@changeset[:email].field}>Email</.label>
          <.input field={@changeset[:email]} type="email" required />
          <.error for={@changeset[:email]} />
        </div>
        
        <div>
          <.label for={@changeset[:age].field}>Age</.label>
          <.input field={@changeset[:age]} type="number" />
          <.error for={@changeset[:age]} />
        </div>
        
        <div>
          <.button type="submit" disabled={!@changeset.valid?}>
            Create User
          </.button>
        </div>
      </.form>
    </div>
    """
  end
end
```

## LiveView with Real-time Updates

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  alias MyApp.Chat
  alias MyApp.Chat.Message

  @impl true
  def mount(%{"room_id" => room_id}, _session, socket) do
    room = Chat.get_room!(room_id)
    messages = Chat.list_messages(room)
    
    if connected?(socket) do
      Chat.subscribe(room_id)
    end
    
    socket =
      socket
      |> assign(:room, room)
      |> assign(:messages, messages)
      |> assign(:message_form, to_form(Chat.change_message(%Message{})))
    
    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message_params}, socket) do
    message_params = Map.put(message_params, "room_id", socket.assigns.room.id)
    
    case Chat.create_message(message_params) do
      {:ok, message} ->
        # Broadcast to all users in the room
        Chat.broadcast_message(socket.assigns.room.id, message)
        
        # Clear the form
        form = to_form(Chat.change_message(%Message{}))
        {:noreply, assign(socket, :message_form, form)}
      
      {:error, changeset} ->
        form = to_form(changeset)
        {:noreply, assign(socket, :message_form, form)}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    messages = [message | socket.assigns.messages]
    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-room">
      <h1>Room: <%= @room.name %></h1>
      
      <div class="messages" id="messages" phx-update="append">
        <%= for message <- @messages do %>
          <div class="message" id={"message-#{message.id}"}>
            <strong><%= message.user.name %>:</strong>
            <%= message.content %>
            <span class="timestamp">
              <%= Calendar.strftime(message.inserted_at, "%H:%M") %>
            </span>
          </div>
        <% end %>
      </div>
      
      <.form for={@message_form} phx-submit="send_message" class="message-form">
        <.input 
          field={@message_form[:content]} 
          type="text" 
          placeholder="Type your message..." 
          autocomplete="off"
        />
        <.button type="submit">Send</.button>
      </.form>
    </div>
    """
  end
end
```

## LiveView with Pagination

```elixir
defmodule MyAppWeb.PostListLive do
  use MyAppWeb, :live_view

  alias MyApp.Blog

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:per_page, 10)
      |> assign(:search, "")
      |> load_posts()
    
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    search = params["search"] || ""
    
    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> load_posts()
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> assign(:page, 1)
      |> push_patch(to: ~p"/posts?search=#{search}")
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    next_page = socket.assigns.page + 1
    
    socket =
      socket
      |> assign(:page, next_page)
      |> load_more_posts()
    
    {:noreply, socket}
  end

  defp load_posts(socket) do
    posts = Blog.list_posts(
      page: socket.assigns.page,
      per_page: socket.assigns.per_page,
      search: socket.assigns.search
    )
    
    assign(socket, :posts, posts)
  end

  defp load_more_posts(socket) do
    new_posts = Blog.list_posts(
      page: socket.assigns.page,
      per_page: socket.assigns.per_page,
      search: socket.assigns.search
    )
    
    existing_posts = socket.assigns.posts
    all_posts = existing_posts ++ new_posts
    
    socket
    |> assign(:posts, all_posts)
    |> assign(:has_more, length(new_posts) == socket.assigns.per_page)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="post-list">
      <h1>Blog Posts</h1>
      
      <form phx-change="search" class="search-form">
        <input 
          type="text" 
          name="search" 
          value={@search}
          placeholder="Search posts..."
        />
      </form>
      
      <div class="posts">
        <%= for post <- @posts do %>
          <div class="post">
            <h2><%= post.title %></h2>
            <p><%= post.excerpt %></p>
            <.link navigate={~p"/posts/#{post}"}>Read more</.link>
          </div>
        <% end %>
      </div>
      
      <%= if @has_more do %>
        <button phx-click="load_more" class="load-more">
          Load More
        </button>
      <% end %>
    </div>
    """
  end
end
```

## LiveView with Components

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  alias MyApp.{Analytics, Accounts}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    
    if connected?(socket) do
      :timer.send_interval(5000, self(), :update_stats)
    end
    
    socket =
      socket
      |> assign(:user, user)
      |> assign(:selected_metric, "users")
      |> load_dashboard_data()
    
    {:ok, socket}
  end

  @impl true
  def handle_event("select_metric", %{"metric" => metric}, socket) do
    socket =
      socket
      |> assign(:selected_metric, metric)
      |> load_dashboard_data()
    
    {:noreply, socket}
  end

  @impl true
  def handle_info(:update_stats, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  defp load_dashboard_data(socket) do
    stats = Analytics.get_dashboard_stats()
    recent_users = Accounts.list_recent_users(limit: 5)
    
    socket
    |> assign(:stats, stats)
    |> assign(:recent_users, recent_users)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <h1>Dashboard</h1>
      
      <div class="metrics">
        <.metric_card 
          title="Total Users" 
          value={@stats.total_users}
          change={@stats.user_change}
          selected={@selected_metric == "users"}
          phx-click="select_metric"
          phx-value-metric="users"
        />
        
        <.metric_card 
          title="Active Sessions" 
          value={@stats.active_sessions}
          change={@stats.session_change}
          selected={@selected_metric == "sessions"}
          phx-click="select_metric"
          phx-value-metric="sessions"
        />
        
        <.metric_card 
          title="Revenue" 
          value={@stats.revenue}
          change={@stats.revenue_change}
          selected={@selected_metric == "revenue"}
          phx-click="select_metric"
          phx-value-metric="revenue"
        />
      </div>
      
      <div class="recent-activity">
        <h2>Recent Users</h2>
        <.user_list users={@recent_users} />
      </div>
    </div>
    """
  end
end

defmodule MyAppWeb.DashboardLive.Components do
  use Phoenix.Component

  def metric_card(assigns) do
    ~H"""
    <div class={["metric-card", @selected && "selected"]} {@rest}>
      <h3><%= @title %></h3>
      <div class="value"><%= @value %></div>
      <div class={["change", change_class(@change)]}>
        <%= format_change(@change) %>
      </div>
    </div>
    """
  end

  def user_list(assigns) do
    ~H"""
    <div class="user-list">
      <%= for user <- @users do %>
        <div class="user-item">
          <img src={user.avatar} alt={user.name} class="avatar" />
          <div class="user-info">
            <div class="name"><%= user.name %></div>
            <div class="email"><%= user.email %></div>
          </div>
          <div class="joined">
            <%= Calendar.strftime(user.inserted_at, "%b %d") %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp change_class(change) when change > 0, do: "positive"
  defp change_class(change) when change < 0, do: "negative"
  defp change_class(_), do: "neutral"

  defp format_change(change) when change > 0, do: "+#{change}%"
  defp format_change(change) when change < 0, do: "#{change}%"
  defp format_change(_), do: "0%"
end
```

## LiveView with Presence

```elixir
defmodule MyAppWeb.CollaborativeLive do
  use MyAppWeb, :live_view

  alias MyApp.Presence

  @impl true
  def mount(%{"document_id" => document_id}, _session, socket) do
    document = MyApp.Documents.get_document!(document_id)
    topic = "document:#{document_id}"
    
    if connected?(socket) do
      MyAppWeb.Endpoint.subscribe(topic)
      
      Presence.track(self(), topic, socket.assigns.current_user.id, %{
        name: socket.assigns.current_user.name,
        avatar: socket.assigns.current_user.avatar,
        joined_at: :os.system_time(:second)
      })
    end
    
    presences = Presence.list(topic)
    
    socket =
      socket
      |> assign(:document, document)
      |> assign(:topic, topic)
      |> assign(:presences, presences)
      |> assign(:content, document.content)
    
    {:ok, socket}
  end

  @impl true
  def handle_event("content_changed", %{"content" => content}, socket) do
    # Broadcast content change to other users
    MyAppWeb.Endpoint.broadcast(socket.assigns.topic, "content_update", %{
      content: content,
      user_id: socket.assigns.current_user.id
    })
    
    {:noreply, assign(socket, :content, content)}
  end

  @impl true
  def handle_event("save_document", _params, socket) do
    case MyApp.Documents.update_document(socket.assigns.document, %{content: socket.assigns.content}) do
      {:ok, document} ->
        socket =
          socket
          |> assign(:document, document)
          |> put_flash(:info, "Document saved!")
        
        {:noreply, socket}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save document")}
    end
  end

  @impl true
  def handle_info(%{event: "content_update", payload: %{content: content, user_id: user_id}}, socket) do
    # Only update if the change came from another user
    if user_id != socket.assigns.current_user.id do
      {:noreply, assign(socket, :content, content)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    presences = Presence.merge(socket.assigns.presences, diff)
    {:noreply, assign(socket, :presences, presences)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="collaborative-editor">
      <div class="header">
        <h1><%= @document.title %></h1>
        <div class="collaborators">
          <%= for {_user_id, presence} <- @presences do %>
            <div class="collaborator" title={presence.name}>
              <img src={presence.avatar} alt={presence.name} class="avatar" />
            </div>
          <% end %>
        </div>
        <button phx-click="save_document" class="save-btn">Save</button>
      </div>
      
      <textarea
        phx-change="content_changed"
        phx-value-content={@content}
        class="editor"
        rows="20"
      ><%= @content %></textarea>
    </div>
    """
  end
end
```

## Tips & Best Practices

### LiveView Lifecycle
- Use `mount/3` for initial setup and assign default values
- Use `handle_params/3` for handling URL parameters and navigation
- Use `handle_event/3` for user interactions
- Use `handle_info/2` for handling messages and real-time updates

### State Management
- Keep socket assigns minimal and focused
- Use `assign/3` for single values, `assign/2` for multiple values
- Use `update/3` for updating existing assigns
- Avoid storing large data structures in assigns

### Real-time Features
- Use `Phoenix.PubSub` for broadcasting updates
- Subscribe to topics in `mount/3` after checking `connected?/1`
- Use `Phoenix.Presence` for tracking user presence
- Handle disconnections gracefully

### Performance
- Use `phx-update="append"` for growing lists
- Implement pagination for large datasets
- Use `phx-debounce` for search inputs
- Minimize the number of assigns updated per event

### Forms and Validation
- Use `phx-change` for real-time validation
- Always validate on the server side
- Use `to_form/2` for proper form handling
- Handle both success and error cases

### Testing
- Test LiveView interactions with `Phoenix.LiveViewTest`
- Test real-time features with multiple connected clients
- Mock external dependencies for reliable tests

## References

- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [LiveView Assigns and HEEx](https://hexdocs.pm/phoenix_live_view/assigns-eex.html)
- [LiveView Testing](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)
- [Phoenix PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)