# Phoenix `conn` vs `socket` Error Troubleshooting Guide

## Common Errors You'll See

```
** (ArgumentError) expected a %Plug.Conn{} but got a %Phoenix.LiveView.Socket{}
** (ArgumentError) expected a %Phoenix.LiveView.Socket{} but got a %Plug.Conn{}
** (Phoenix.Router.NoRouteError) no route found for GET /some/path (no conn available)
** (ArgumentError) cannot use url/2 without a %Plug.Conn{}
```

## Root Cause: Context Mismatch

Phoenix has two different rendering contexts that **cannot be mixed**:

- **Controller Templates** → Have access to `@conn` (HTTP request/response)
- **LiveView Templates** → Have access to `@socket` (WebSocket connection)

**The Problem:** Your component is using context-specific helpers in the wrong environment.

---

## Quick Diagnosis

### Step 1: Identify Your Current Context

```elixir
# Add this to your template to see what context you're in:
<%= inspect(assigns) %>
```

**Look for these keys:**
- If you see `conn: %Plug.Conn{}` → You're in a **controller template**
- If you see `socket: %Phoenix.LiveView.Socket{}` → You're in a **LiveView template**

### Step 2: Check Your Component Usage

```elixir
# In your component, add debugging:
def problematic_component(assigns) do
  IO.inspect(assigns, label: "Component assigns")
  
  ~H"""
  <!-- Your component content -->
  """
end
```

---

## Common Patterns & Fixes

### Error 1: Using `url()` in LiveView

#### ❌ Broken Code
```elixir
def navigation_component(assigns) do
  ~H"""
  <nav>
    <.link href={url(~p"/contacts")}>Contacts</.link>
  </nav>
  """
end

# Error: cannot use url/2 without a %Plug.Conn{}
```

#### ✅ Fixed Code
```elixir
def navigation_component(assigns) do
  ~H"""
  <nav>
    <.link navigate={~p"/contacts"}>Contacts</.link>
  </nav>
  """
end

# navigate/1 works in both contexts
```

### Error 2: Using `phx-*` in Controller Templates

#### ❌ Broken Code
```elixir
def contact_form(assigns) do
  ~H"""
  <.simple_form for={@form} phx-submit="save">
    <.input field={@form[:name]} />
  </.simple_form>
  """
end

# Error: phx-submit requires LiveView context
```

#### ✅ Fixed Code
```elixir
def contact_form(assigns) do
  assigns = assign_new(assigns, :action, fn -> nil end)
  
  ~H"""
  <.simple_form 
    for={@form} 
    action={@action}
    phx-submit={if assigns[:socket], do: "save", else: nil}
  >
    <.input field={@form[:name]} />
  </.simple_form>
  """
end

# Usage in controller: <.contact_form form={@form} action={~p"/contacts"} />
# Usage in LiveView: <.contact_form form={@form} />
```

### Error 3: LiveView Components in Controller Templates

#### ❌ Broken Code
```elixir
# In controller template (.html.heex):
<.live_component module={MyComponent} id="test" />

# Error: live_component requires LiveView context
```

#### ✅ Fixed Code
```elixir
# Option 1: Convert to function component
def my_display_component(assigns) do
  ~H"""
  <!-- Static display logic here -->
  """
end

# Option 2: Use in LiveView instead
# Move the functionality to a LiveView page
```

### Error 4: Core Components Expecting Wrong Context

#### ❌ Broken Code
```elixir
# Using Phoenix.Component link helper incorrectly
def sidebar_links(assigns) do
  ~H"""
  <.link href={Routes.contact_path(@conn, :index)}>Contacts</.link>
  """
end

# Error when used in LiveView: @conn not available
```

#### ✅ Fixed Code
```elixir
def sidebar_links(assigns) do
  ~H"""
  <.link navigate={~p"/contacts"}>Contacts</.link>
  """
end

# Works in both contexts
```

---

## Context-Safe Component Patterns

### Pattern 1: Context Detection

```elixir
def adaptive_button(assigns) do
  ~H"""
  <%= if assigns[:socket] do %>
    <!-- LiveView context -->
    <button phx-click={@action} phx-target={@target} class={@class}>
      <%= @label %>
    </button>
  <% else %>
    <!-- Controller context -->
    <.link href={@href} class={@class}>
      <%= @label %>
    </.link>
  <% end %>
  """
end
```

### Pattern 2: Delegation to Parent

```elixir
def contact_card(assigns) do
  ~H"""
  <div class="bg-white rounded-lg shadow p-4">
    <h3><%= @contact.name %></h3>
    <p><%= @contact.email %></p>
    
    <!-- Let parent handle context-specific actions -->
    <div class="mt-4">
      <%= render_slot(@actions, @contact) %>
    </div>
  </div>
  """
end

# Usage in controller:
~H"""
<.contact_card contact={@contact}>
  <:actions :let={contact}>
    <.link href={~p"/contacts/#{contact.id}"} class="btn">View</.link>
  </:actions>
</.contact_card>
"""

# Usage in LiveView:
~H"""
<.contact_card contact={@contact}>
  <:actions :let={contact}>
    <button phx-click="view" phx-value-id={contact.id} class="btn">View</button>
  </:actions>
</.contact_card>
"""
```

### Pattern 3: Explicit Context Props

```elixir
def smart_link(assigns) do
  assigns = assign_new(assigns, :context, fn -> :auto end)
  
  ~H"""
  <%= cond do %>
    <% @context == :liveview or assigns[:socket] -> %>
      <button phx-click={@action} class={@class}>
        <%= @label %>
      </button>
    
    <% @context == :controller or assigns[:conn] -> %>
      <.link href={@href} class={@class}>
        <%= @label %>
      </.link>
    
    <% true -> %>
      <span class={@class}><%= @label %></span>
  <% end %>
  """
end

# Explicit usage:
# <.smart_link context={:liveview} action="click" label="Button" />
# <.smart_link context={:controller} href="/path" label="Link" />
```

---

## Quick Fixes Reference

| Problem | Quick Fix |
|---------|-----------|
| `url()` in LiveView | Replace with `navigate={~p"/path"}` |
| `phx-*` in controller | Add `action` attribute for forms, remove phx events |
| `@conn` not available | Use `~p` paths instead of `Routes.*_path(@conn, ...)` |
| `live_component` in controller | Convert to function component or use LiveView |
| Routes helper error | Replace `Routes.path(@conn, :action)` with `~p"/path"` |

---

## Testing Both Contexts

```elixir
defmodule MyAppWeb.MyComponentTest do
  use MyAppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "in controller context" do
    test "renders correctly" do
      assigns = %{contact: %{name: "John"}}
      
      html = rendered_to_string(~H"""
      <.my_component {assigns} />
      """)
      
      assert html =~ "John"
      refute html =~ "phx-"  # No LiveView attributes
    end
  end

  describe "in LiveView context" do
    test "renders correctly", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive,
        session: %{"contact" => %{name: "John"}}
      )
      
      assert has_element?(view, "[data-test='my-component']")
    end
  end
end

# Test LiveView wrapper
defmodule MyAppWeb.TestLive do
  use MyAppWeb, :live_view
  
  def mount(_params, session, socket) do
    {:ok, assign(socket, :contact, session["contact"])}
  end
  
  def render(assigns) do
    ~H"""
    <.my_component contact={@contact} />
    """
  end
end
```

---

## Migration Checklist

When converting components to be context-safe:

- [ ] Replace `url()` calls with `~p` sigil or `navigate`
- [ ] Replace `Routes.*_path(@conn, ...)` with `~p"/path"`
- [ ] Remove `phx-*` attributes or make them conditional
- [ ] Replace `@conn` references with context-agnostic alternatives
- [ ] Add context detection where needed
- [ ] Test in both controller templates and LiveView
- [ ] Update component documentation to specify context requirements

---

## Advanced: Creating Context-Agnostic Components

```elixir
defmodule MyAppWeb.ContextSafeComponents do
  use Phoenix.Component
  
  @doc """
  Renders a link that works in both controller and LiveView contexts.
  
  ## Examples
  
      # In controller template:
      <.smart_link to="/contacts" label="Contacts" />
      
      # In LiveView:
      <.smart_link to="/contacts" label="Contacts" />
  """
  attr :to, :string, required: true
  attr :label, :string, required: true
  attr :class, :string, default: ""
  attr :method, :string, default: "get"
  
  def smart_link(assigns) do
    ~H"""
    <.link navigate={@to} class={@class} method={@method}>
      <%= @label %>
    </.link>
    """
  end
  
  @doc """
  Renders a form that works in both contexts.
  """
  attr :for, :any, required: true
  attr :action, :string, default: nil
  attr :phx_submit, :string, default: nil
  slot :inner_block, required: true
  
  def universal_form(assigns) do
    # Auto-detect context and set appropriate attributes
    assigns = 
      assigns
      |> assign_new(:is_liveview, fn -> not is_nil(assigns[:socket]) end)
      |> assign_new(:form_action, fn -> 
        if assigns.is_liveview, do: nil, else: assigns.action 
      end)
      |> assign_new(:form_phx_submit, fn ->
        if assigns.is_liveview, do: assigns.phx_submit, else: nil
      end)
    
    ~H"""
    <.simple_form 
      for={@for}
      action={@form_action}
      phx-submit={@form_phx_submit}
    >
      <%= render_slot(@inner_block) %>
    </.simple_form>
    """
  end
end
```

This guide should resolve most `conn` vs `socket` context errors you encounter in Phoenix applications.