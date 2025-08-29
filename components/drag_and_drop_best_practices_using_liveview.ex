## Drag-and-Drop Implementation in Phoenix LiveView

### Prerequisites

Ensure you're using Phoenix LiveView 0.18+ which includes native drag-and-drop support through `phx-hook` and JavaScript interoperability.

### Basic Implementation

#### 1. LiveView Module Setup

```elixir
defmodule MyAppWeb.DragDropLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       items: [
         %{id: "item-1", content: "First item", position: 0},
         %{id: "item-2", content: "Second item", position: 1},
         %{id: "item-3", content: "Third item", position: 2}
       ],
       dragging: nil,
       drag_over: nil
     )}
  end

  @impl true
  def handle_event("drag-start", %{"id" => id}, socket) do
    {:noreply, assign(socket, dragging: id)}
  end

  @impl true
  def handle_event("drag-end", _params, socket) do
    {:noreply, assign(socket, dragging: nil, drag_over: nil)}
  end

  @impl true
  def handle_event("drag-over", %{"id" => id}, socket) do
    {:noreply, assign(socket, drag_over: id)}
  end

  @impl true
  def handle_event("drop", %{"id" => drop_id}, socket) do
    %{items: items, dragging: drag_id} = socket.assigns

    if drag_id && drag_id != drop_id do
      items = reorder_items(items, drag_id, drop_id)
      {:noreply, assign(socket, items: items, dragging: nil, drag_over: nil)}
    else
      {:noreply, socket}
    end
  end

  defp reorder_items(items, drag_id, drop_id) do
    drag_item = Enum.find(items, &(&1.id == drag_id))
    drop_item = Enum.find(items, &(&1.id == drop_id))

    items
    |> Enum.map(fn item ->
      cond do
        item.id == drag_id -> %{item | position: drop_item.position}
        item.id == drop_id -> %{item | position: drag_item.position}
        true -> item
      end
    end)
    |> Enum.sort_by(& &1.position)
  end
end
```

#### 2. Template (HEEX)

```heex
<div id="drag-container" phx-hook="DragDrop">
  <%= for item <- @items do %>
    <div
      id={item.id}
      class={"draggable-item #{if @dragging == item.id, do: "dragging"} #{if @drag_over == item.id, do: "drag-over"}"}
      draggable="true"
      phx-value-id={item.id}
      data-id={item.id}
    >
      <%= item.content %>
    </div>
  <% end %>
</div>

<style>
  .draggable-item {
    padding: 1rem;
    margin: 0.5rem;
    background: #f0f0f0;
    cursor: move;
  }

  .dragging {
    opacity: 0.5;
  }

  .drag-over {
    border-top: 3px solid #4338ca;
  }
</style>
```

#### 3. JavaScript Hook (Minimal)

In `assets/js/app.js`:

```javascript
let Hooks = {}

Hooks.DragDrop = {
  mounted() {
    this.el.addEventListener("dragstart", e => {
      if (e.target.dataset.id) {
        e.dataTransfer.effectAllowed = "move"
        this.pushEvent("drag-start", {id: e.target.dataset.id})
      }
    })

    this.el.addEventListener("dragover", e => {
      e.preventDefault()
      if (e.target.dataset.id) {
        this.pushEvent("drag-over", {id: e.target.dataset.id})
      }
    })

    this.el.addEventListener("drop", e => {
      e.preventDefault()
      if (e.target.dataset.id) {
        this.pushEvent("drop", {id: e.target.dataset.id})
      }
    })

    this.el.addEventListener("dragend", e => {
      this.pushEvent("drag-end", {})
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})
```

### Testing

#### 1. Unit Tests for Reordering Logic

```elixir
defmodule MyAppWeb.DragDropLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  test "reordering items updates positions correctly", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/drag-drop")

    # Simulate drag and drop
    assert view
           |> element("[data-id='item-1']")
           |> render_hook("drag-start", %{"id" => "item-1"})

    assert view
           |> element("[data-id='item-3']")
           |> render_hook("drop", %{"id" => "item-3"})

    # Verify reordering
    html = render(view)
    assert html =~ ~r/item-2.*item-3.*item-1/s
  end

  test "dragging state is set and cleared", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/drag-drop")

    # Start dragging
    render_hook(view, "drag-start", %{"id" => "item-1"})
    assert view.assigns.dragging == "item-1"

    # End dragging
    render_hook(view, "drag-end", %{})
    assert view.assigns.dragging == nil
  end
end
```

#### 2. Integration Tests with Wallaby

```elixir
defmodule MyAppWeb.DragDropIntegrationTest do
  use ExUnit.Case
  use Wallaby.Feature

  import Wallaby.Query

  feature "drag and drop reorders items", %{session: session} do
    session
    |> visit("/drag-drop")
    |> assert_has(css(".draggable-item", count: 3))

    # Wallaby doesn't support native drag events well
    # Consider using execute_script for complex interactions
    session
    |> execute_script("""
      const dragStart = new DragEvent('dragstart', {
        dataTransfer: new DataTransfer(),
        bubbles: true
      });
      document.querySelector('[data-id="item-1"]').dispatchEvent(dragStart);
    """)

    # Verify UI updates
    session
    |> assert_has(css(".dragging"))
  end
end
```

### Debugging Strategies

#### 1. Add Debug Output to LiveView

```elixir
def handle_event(event, params, socket) do
  IO.inspect({event, params}, label: "DragDrop Event")
  # ... rest of handler
end
```

#### 2. Browser Console Debugging

```javascript
Hooks.DragDrop = {
  mounted() {
    // Add console logging
    this.el.addEventListener("dragstart", e => {
      console.log("Drag started:", e.target.dataset.id)
      // ...
    })
  }
}
```

#### 3. LiveView Debug Assigns

```heex
<%= if Application.get_env(:my_app, :env) == :dev do %>
  <div style="position: fixed; bottom: 0; right: 0; background: white; padding: 1rem;">
    <pre><%= inspect(@dragging) %></pre>
    <pre><%= inspect(@drag_over) %></pre>
  </div>
<% end %>
```

### Common Issues and Solutions

**Issue**: Events not firing
- Check `phx-hook` is properly set on the container element
- Verify JavaScript hook is registered in `liveSocket`
- Ensure `draggable="true"` is set on draggable elements

**Issue**: State not updating
- Verify event handlers return `{:noreply, updated_socket}`
- Check that assigns are properly updated in handlers
- Use `IO.inspect` to debug socket state changes

**Issue**: Visual feedback not working
- CSS classes might be getting purged - add them to safelist if using PurgeCSS
- Check browser developer tools for class application
- Verify conditional class logic in template

**Issue**: Touch devices not working
- Native drag events don't work on touch devices
- Consider adding a library like Sortable.js for mobile support or implementing touch event handlers

This approach minimizes JavaScript while leveraging LiveView's server-side state management. The JavaScript hook only handles browser drag events and pushes them to the server, keeping business logic in Elixir.
