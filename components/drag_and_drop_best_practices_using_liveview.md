# Drag-and-Drop with Phoenix LiveView Recipe

---
Phoenix Version: 1.7+
Complexity: Intermediate
Time to Implement: 1-2 hours
Prerequisites: Phoenix LiveView basics, JavaScript hooks understanding, DOM events knowledge
---

## Prerequisites & Related Recipes

### Prerequisites
- Understanding of Phoenix LiveView event handling
- Basic JavaScript and DOM manipulation knowledge
- Familiarity with Phoenix hooks system
- Understanding of LiveView's server-side state management

### Related Recipes
- **Foundation**: [Phoenix LiveView Basics](phoenix_liveview_basics.md) - Core LiveView concepts and patterns
- **Components**: [Phoenix Components](phoenix_components.md) - Building reusable UI components
- **Testing**: [Comprehensive Testing Guide](../testing/comprehensive_testing_guide.md) - Testing LiveView interactions
- **Alternative**: [Phoenix Prefer Traditional Use LiveView Sparingly](phoenix_prefer_traditional_use_liveview_sparingly.md) - When NOT to use LiveView

## Introduction

This recipe demonstrates how to implement drag-and-drop functionality in Phoenix LiveView using minimal JavaScript while leveraging server-side state management. This approach provides a reactive, real-time drag-and-drop experience without complex client-side frameworks.

### When to Use This Pattern
- Reordering lists or cards
- Moving items between containers
- Visual workflow builders
- Kanban boards or task management interfaces
- File upload zones with visual feedback

### Key Benefits
- Server-side state management keeps logic simple
- Minimal JavaScript reduces complexity
- Real-time updates across connected clients
- Testable with standard LiveView testing tools
- No external JavaScript dependencies

## Basic Examples

### Simple List Reordering

The most common use case - dragging items to reorder them in a list.

```elixir
defmodule MyAppWeb.SortableLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    items = [
      %{id: "item-1", content: "First task", position: 0},
      %{id: "item-2", content: "Second task", position: 1},
      %{id: "item-3", content: "Third task", position: 2}
    ]
    
    {:ok, 
     assign(socket,
       items: items,
       dragging: nil  # Track what's being dragged
     )}
  end

  @impl true
  def handle_event("drag-start", %{"id" => id}, socket) do
    # User started dragging an item
    {:noreply, assign(socket, dragging: id)}
  end

  @impl true
  def handle_event("drag-end", _params, socket) do
    # Drag operation completed
    {:noreply, assign(socket, dragging: nil)}
  end

  @impl true
  def handle_event("drop", %{"drag-id" => drag_id, "drop-id" => drop_id}, socket) do
    # Reorder items when dropped
    items = reorder_items(socket.assigns.items, drag_id, drop_id)
    {:noreply, assign(socket, items: items, dragging: nil)}
  end

  defp reorder_items(items, drag_id, drop_id) when drag_id != drop_id do
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
  
  defp reorder_items(items, _same_id, _same_id), do: items
end
```

### Template with Draggable Items

```heex
<div id="sortable-list" phx-hook="Sortable">
  <%= for item <- @items do %>
    <div
      id={item.id}
      class={[
        "draggable-item",
        @dragging == item.id && "opacity-50"
      ]}
      draggable="true"
      data-id={item.id}
    >
      <span class="drag-handle">⋮⋮</span>
      <%= item.content %>
    </div>
  <% end %>
</div>
```

### Minimal JavaScript Hook

```javascript
// assets/js/hooks/sortable.js
export const Sortable = {
  mounted() {
    this.container = this.el
    this.setupDragHandlers()
  },

  setupDragHandlers() {
    this.container.addEventListener("dragstart", (e) => {
      if (e.target.classList.contains("draggable-item")) {
        e.dataTransfer.effectAllowed = "move"
        e.dataTransfer.setData("text/plain", e.target.dataset.id)
        this.pushEvent("drag-start", {id: e.target.dataset.id})
      }
    })

    this.container.addEventListener("dragover", (e) => {
      e.preventDefault() // Allow drop
      e.dataTransfer.dropEffect = "move"
    })

    this.container.addEventListener("drop", (e) => {
      e.preventDefault()
      const dragId = e.dataTransfer.getData("text/plain")
      const dropTarget = e.target.closest(".draggable-item")
      
      if (dropTarget && dragId !== dropTarget.dataset.id) {
        this.pushEvent("drop", {
          "drag-id": dragId,
          "drop-id": dropTarget.dataset.id
        })
      }
    })

    this.container.addEventListener("dragend", (e) => {
      this.pushEvent("drag-end", {})
    })
  }
}

// Register the hook in app.js
import {Sortable} from "./hooks/sortable"

let Hooks = {Sortable}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})
```

## Advanced Examples

### Drag Between Multiple Containers (Kanban Board)

```elixir
defmodule MyAppWeb.KanbanLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    columns = %{
      "todo" => %{
        id: "todo",
        title: "To Do",
        items: [
          %{id: "task-1", content: "Design mockups"},
          %{id: "task-2", content: "Write tests"}
        ]
      },
      "doing" => %{
        id: "doing", 
        title: "In Progress",
        items: [
          %{id: "task-3", content: "Implement feature"}
        ]
      },
      "done" => %{
        id: "done",
        title: "Done",
        items: []
      }
    }
    
    {:ok, assign(socket, columns: columns, dragging: nil)}
  end

  @impl true
  def handle_event("drop-in-column", params, socket) do
    %{
      "item-id" => item_id,
      "from-column" => from_col,
      "to-column" => to_col
    } = params
    
    columns = move_item_between_columns(
      socket.assigns.columns,
      item_id,
      from_col,
      to_col
    )
    
    {:noreply, assign(socket, columns: columns)}
  end

  defp move_item_between_columns(columns, item_id, from, to) do
    # Find and remove item from source column
    {item, updated_from} = extract_item(columns[from], item_id)
    
    # Add item to destination column
    updated_to = add_item(columns[to], item)
    
    columns
    |> Map.put(from, updated_from)
    |> Map.put(to, updated_to)
  end
end
```

### With Visual Feedback and Animation

```elixir
defmodule MyAppWeb.DragDropLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       items: generate_items(),
       dragging: nil,
       drag_over: nil,  # Track hover state
       preview_position: nil  # Show drop preview
     )}
  end

  @impl true
  def handle_event("drag-over", %{"id" => id}, socket) do
    # Provide visual feedback during drag
    {:noreply, assign(socket, drag_over: id)}
  end

  @impl true
  def handle_event("drag-leave", _params, socket) do
    {:noreply, assign(socket, drag_over: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="drag-area" phx-hook="DragDrop">
      <%= for item <- @items do %>
        <div
          id={item.id}
          class={[
            "drag-item",
            @dragging == item.id && "dragging",
            @drag_over == item.id && "drag-over"
          ]}
          draggable="true"
          data-id={item.id}
        >
          <%= if @drag_over == item.id do %>
            <div class="drop-indicator"></div>
          <% end %>
          <%= item.content %>
        </div>
      <% end %>
    </div>
    
    <style>
      .drag-item {
        padding: 1rem;
        margin: 0.5rem;
        background: white;
        border: 2px solid #e5e7eb;
        border-radius: 0.5rem;
        cursor: move;
        transition: all 0.2s;
      }
      
      .dragging {
        opacity: 0.4;
        transform: scale(0.95);
      }
      
      .drag-over {
        border-color: #3b82f6;
        background: #eff6ff;
      }
      
      .drop-indicator {
        height: 3px;
        background: #3b82f6;
        margin: -1rem -1rem 0.5rem -1rem;
        animation: pulse 1s infinite;
      }
      
      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
      }
    </style>
    """
  end
end
```

## Pattern Comparison

### When to Use Each Approach

| Pattern | Use When | Avoid When | Complexity |
|---------|----------|------------|------------|
| **Simple Reorder** | Single list sorting | Multiple containers needed | Low |
| **Kanban Style** | Moving between columns | Complex nesting required | Medium |
| **With Preview** | Visual feedback critical | Performance is concern | Medium |
| **Touch + Mouse** | Mobile support needed | Desktop-only app | High |
| **Auto-scroll** | Long lists/pages | Simple fixed lists | High |

## Anti-patterns

### ❌ Over-Relying on Client State

```javascript
// Bad: Managing state in JavaScript
Hooks.BadDragDrop = {
  mounted() {
    this.items = [] // Don't store state here!
    
    this.el.addEventListener("drop", (e) => {
      // Reordering in JavaScript instead of server
      this.items = this.reorderLocally(this.items)
      this.updateDOM() // Manually updating DOM
    })
  }
}
```

### ✅ Server-Side State Management

```javascript
// Good: Let LiveView manage state
Hooks.GoodDragDrop = {
  mounted() {
    this.el.addEventListener("drop", (e) => {
      // Just send event to server
      this.pushEvent("drop", {
        from: e.dataTransfer.getData("text/plain"),
        to: e.target.dataset.id
      })
      // LiveView handles state and DOM updates
    })
  }
}
```

### ❌ Complex JavaScript Logic

```javascript
// Bad: Business logic in JavaScript
Hooks.ComplexDragDrop = {
  canDrop(dragItem, dropTarget) {
    // Complex validation in JS
    if (dragItem.type === "folder" && dropTarget.type === "file") {
      return false
    }
    // More complex rules...
  }
}
```

### ✅ Server-Side Validation

```elixir
# Good: Validation in LiveView
def handle_event("drop", params, socket) do
  if valid_drop?(params, socket.assigns) do
    # Perform drop
    {:noreply, update_items(socket, params)}
  else
    # Reject with feedback
    {:noreply, put_flash(socket, :error, "Invalid drop location")}
  end
end

defp valid_drop?(params, assigns) do
  # All validation logic on server
  # Easy to test and maintain
end
```

## Testing

### Unit Tests for Reordering Logic

```elixir
defmodule MyAppWeb.DragDropLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "drag and drop" do
    test "reorders items on drop", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/drag-drop")
      
      # Verify initial order
      assert has_element?(view, "#item-1:first-child")
      
      # Simulate drag and drop
      view
      |> element("#item-1")
      |> render_hook("drag-start", %{"id" => "item-1"})
      
      view
      |> element("#item-3")
      |> render_hook("drop", %{
        "drag-id" => "item-1",
        "drop-id" => "item-3"
      })
      
      # Verify new order
      refute has_element?(view, "#item-1:first-child")
    end

    test "handles drag between containers", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/kanban")
      
      # Move task from todo to doing
      view
      |> element("#task-1")
      |> render_hook("drop-in-column", %{
        "item-id" => "task-1",
        "from-column" => "todo",
        "to-column" => "doing"
      })
      
      # Verify task moved
      assert has_element?(view, "#doing #task-1")
      refute has_element?(view, "#todo #task-1")
    end
  end
end
```

### Testing Visual Feedback

```elixir
test "shows visual feedback during drag", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/drag-drop")
  
  # Start dragging
  render_hook(view, "drag-start", %{"id" => "item-1"})
  
  # Check dragging class applied
  assert has_element?(view, "#item-1.dragging")
  
  # Hover over target
  render_hook(view, "drag-over", %{"id" => "item-2"})
  
  # Check hover feedback
  assert has_element?(view, "#item-2.drag-over")
  
  # Complete drag
  render_hook(view, "drag-end", %{})
  
  # Check classes removed
  refute has_element?(view, ".dragging")
  refute has_element?(view, ".drag-over")
end
```

## Common Issues & Solutions

### Issue: Events Not Firing

**Problem**: Drag events not reaching LiveView

**Solution**: Ensure proper hook registration
```javascript
// Check hook is registered
let Hooks = {DragDrop}  // Must match phx-hook="DragDrop"

// Verify element has draggable attribute
<div draggable="true">  // Required for drag events
```

### Issue: Drop Not Working

**Problem**: Drop event not triggering

**Solution**: Prevent default on dragover
```javascript
this.el.addEventListener("dragover", (e) => {
  e.preventDefault()  // MUST prevent default
  e.dataTransfer.dropEffect = "move"
})
```

### Issue: Visual Feedback Lag

**Problem**: UI updates feel slow during drag

**Solution**: Use CSS for immediate feedback
```css
.draggable-item:active {
  opacity: 0.5;  /* Instant feedback */
}

/* Let LiveView update state-based classes */
.dragging {
  transform: scale(0.95);
}
```

### Issue: Touch Devices Not Working

**Problem**: Drag-and-drop doesn't work on mobile

**Solution**: Add touch event support
```javascript
// Add touch-to-drag polyfill
import {polyfill} from 'mobile-drag-drop'
polyfill({
  dragImageTranslateOverride: scrollBehaviourDragImageTranslateOverride
})
```

## Performance Optimization

### Debounce Drag-Over Events

```javascript
Hooks.OptimizedDragDrop = {
  mounted() {
    this.dragOverTimeout = null
    
    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      
      // Debounce server events
      clearTimeout(this.dragOverTimeout)
      this.dragOverTimeout = setTimeout(() => {
        this.pushEvent("drag-over", {id: e.target.dataset.id})
      }, 100) // Only send every 100ms
    })
  }
}
```

### Batch Updates for Multiple Items

```elixir
def handle_event("drop-multiple", %{"items" => items}, socket) do
  # Update all at once instead of individual updates
  updated_items = Enum.reduce(items, socket.assigns.items, fn item, acc ->
    update_single_item(acc, item)
  end)
  
  {:noreply, assign(socket, items: updated_items)}
end
```

## File Organization

```
lib/
├── my_app_web/
│   ├── live/
│   │   ├── drag_drop_live.ex
│   │   └── components/
│   │       ├── draggable_list.ex
│   │       └── drop_zone.ex
│   └── hooks/
│       └── drag_drop.js
assets/
├── js/
│   ├── app.js
│   └── hooks/
│       └── sortable.js
└── css/
    └── drag_drop.css
```

## Tips & Best Practices

- **Performance**: Debounce drag-over events to reduce server load
- **Accessibility**: Provide keyboard alternatives for drag operations
- **Mobile**: Consider touch event support for mobile devices
- **Feedback**: Use CSS for immediate visual feedback, LiveView for state
- **Testing**: Test both the LiveView logic and hook integration
- **Error Handling**: Gracefully handle failed drops with user feedback

## Real-World Example: Task Board

```elixir
defmodule MyAppWeb.TaskBoardLive do
  use MyAppWeb, :live_view
  
  alias MyApp.Projects
  
  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    if connected?(socket) do
      Projects.subscribe(project_id)
    end
    
    {:ok,
     socket
     |> assign(:project_id, project_id)
     |> load_board()}
  end
  
  @impl true
  def handle_event("move_task", params, socket) do
    %{
      "task_id" => task_id,
      "to_column" => column,
      "position" => position
    } = params
    
    case Projects.move_task(task_id, column, position) do
      {:ok, _task} ->
        {:noreply, load_board(socket)}
      
      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to move task")}
    end
  end
  
  @impl true
  def handle_info({:task_moved, _task}, socket) do
    # Real-time updates for all connected users
    {:noreply, load_board(socket)}
  end
  
  defp load_board(socket) do
    board = Projects.get_board(socket.assigns.project_id)
    assign(socket, :board, board)
  end
end
```

## References

- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view)
- [MDN Drag and Drop API](https://developer.mozilla.org/en-US/docs/Web/API/HTML_Drag_and_Drop_API)
- [LiveView JavaScript Interop Guide](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- Related Recipes: [Phoenix LiveView Basics](phoenix_liveview_basics.md), [Phoenix Components](phoenix_components.md)

---

### Recipe Metadata

- **Difficulty**: Intermediate
- **Phoenix Version**: 1.7+
- **LiveView Version**: 0.18+
- **Requirements**: Phoenix LiveView, modern browser with drag-and-drop support
- **Last Updated**: 2024