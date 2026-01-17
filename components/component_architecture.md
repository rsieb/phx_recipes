# Component Architecture - Patterns and Composition

## Component Selection Priority

When building UI, always check for existing components in this order:

### 1. PetalComponents (first choice)
Located in `deps/petal_components/lib/petal_components/`

Available components:
- **Layout**: `<.container>`
- **Typography**: `<.h1>`, `<.h2>`, `<.h3>`, `<.h4>`, `<.p>`
- **Buttons**: `<.button>`, `<.button_group>`
- **Forms**: `<.form>`, `<.field>`, `<.input>`
- **Data Display**: `<.table>`, `<.card>`, `<.badge>`, `<.avatar>`
- **Feedback**: `<.alert>`, `<.progress>`, `<.skeleton>`, `<.loading>`
- **Navigation**: `<.tabs>`, `<.breadcrumbs>`, `<.pagination>`, `<.stepper>`
- **Overlays**: `<.modal>`, `<.dropdown>`, `<.slide_over>`
- **Other**: `<.accordion>`, `<.rating>`, `<.marquee>`, `<.icon>`

Documentation: https://petal.build/components

### 2. PetalPro Components (second choice)
Located in `lib/<app>_web/components/pro_components/`

Available components:
- `data_table/` - Advanced data tables with sorting, filtering, pagination
- `sidebar_layout.ex`, `sidebar_menu.ex` - App shell layouts
- `navbar.ex` - Navigation bars
- `flash.ex` - Toast notifications
- `combo_box.ex` - Searchable select
- `content_editor.ex` - Rich text editing
- `color_scheme_switch.ex` - Dark/light mode toggle
- `social_button.ex` - OAuth login buttons

### 3. Custom Components (last resort)
Only build custom when PetalComponents and PetalPro don't cover the use case.

### Usage Examples

```heex
<!-- ❌ Don't write raw HTML -->
<button class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
  Submit
</button>

<!-- ✅ Use PetalComponents -->
<.button>Submit</.button>
```

```heex
<!-- ❌ Don't write raw HTML -->
<span class="inline-block px-2 py-1 text-xs rounded bg-green-100 text-green-800">
  Active
</span>

<!-- ✅ Use PetalComponents -->
<.badge color="success">Active</.badge>
```

---

## core_components.ex Guidelines

**Keep it lean.** This file should contain base UI primitives only.

### What belongs in core_components.ex:
- Phoenix-required components (flash, modal from generators)
- True primitives used across many features
- Components that wrap PetalComponents with app-specific defaults

### What does NOT belong:
- Feature-specific components → put in `<feature>_components.ex`
- Complex components (>50 lines) → put in dedicated file
- One-off visualizations → put near the feature that uses them

### Example structure:
```
lib/my_app_web/components/
├── core_components.ex          # Base primitives only
├── layouts.ex                  # Layout components
├── decoder_components.ex       # Decoder-specific
├── proposal_components.ex      # Proposal-specific
└── pro_components/             # PetalPro components
```

---

## Philosophy: Pages as Component Compositions

Every page should be a composition of small, focused components rather than a monolithic template with inline logic. This approach improves maintainability, testability, and reusability.

### Golden Rule
**If a section of your page has distinct functionality or can be conceptually separated, it should be a component.**

---

## Part 1: Identifying Components

### Component Identification Checklist

#### ✅ Should be a component:
- **Repeatable UI patterns** (cards, buttons, forms, modals)
- **Distinct functional areas** (navigation, sidebar, footer, search bar)
- **Data display sections** (user profiles, product listings, statistics)
- **Interactive elements** (forms, filters, toggles, dropdowns)
- **Conditional content** (error messages, loading states, empty states)
- **Anything with its own styling scope** (headers, panels, widgets)

#### ❌ Probably not a component:
- **Single-use text** (one-off paragraphs, unique headlines)
- **Simple wrappers** (basic divs without logic)
- **Page-specific layout containers** (unless reused across pages)

### Component Size Guidelines

```elixir
# ✅ Good: Focused, single responsibility
def user_avatar(assigns) do
  ~H"""
  <div class="relative">
    <img src={@user.avatar_url} alt={@user.name} class="w-10 h-10 rounded-full" />
    <div :if={@show_status} class="absolute -bottom-1 -right-1">
      <.status_indicator status={@user.status} />
    </div>
  </div>
  """
end

# ❌ Bad: Too large, multiple responsibilities
def user_profile_page(assigns) do
  ~H"""
  <div class="min-h-screen bg-gray-50">
    <nav class="bg-white shadow-sm">
      <!-- 50 lines of navigation -->
    </nav>
    <main class="max-w-7xl mx-auto py-6">
      <div class="px-4 sm:px-6 lg:px-8">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <!-- 100 lines of profile content -->
        </div>
        <div class="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-2">
          <!-- 80 lines of activity feed -->
        </div>
      </div>
    </main>
  </div>
  """
end
```

---

## Part 2: Component Organization Patterns

### The Phoenix Approach: Grouped vs. Individual Files

Phoenix components are typically organized differently than other frameworks (React, Vue, etc.). Here's why and when to deviate:

#### ✅ Phoenix Convention: Group Related Components

```
lib/my_app_web/
├── components/
│   ├── core_components.ex          # Base UI components (button, input, card)
│   ├── layout_components.ex        # Layout-specific components
│   ├── contact_components.ex       # Domain-specific components
│   ├── dashboard_components.ex     # Page-specific components
│   └── form_components.ex          # Form-related components
├── live/
│   ├── components/                 # LiveComponents (individual files)
│   │   ├── activity_feed_component.ex
│   │   ├── notes_component.ex
│   │   └── chart_components/
│   │       ├── contact_growth_chart.ex
│   │       └── activity_overview_chart.ex
│   ├── contact_live/
│   │   ├── show.ex                 # Minimal page composition
│   │   ├── index.ex                # Minimal page composition
│   │   └── form.ex                 # Minimal page composition
│   └── dashboard_live.ex           # Minimal page composition
```

#### Technical Reasons for Phoenix's Approach

**1. Elixir's Module System**
```elixir
# ✅ Efficient: One module compilation, shared private functions
defmodule MyAppWeb.ContactComponents do
  use Phoenix.Component
  
  def contact_header(assigns), do: ~H"..."
  def contact_info(assigns), do: ~H"..."
  def contact_actions(assigns), do: ~H"..."
  
  # Shared private helpers
  defp format_phone(phone), do: ...
  defp contact_status_class(status), do: ...
end

# ❌ Less efficient: Multiple modules, duplicated helpers
defmodule MyAppWeb.ContactHeader do
  use Phoenix.Component
  def contact_header(assigns), do: ~H"..."
  defp format_phone(phone), do: ...  # Duplicated
end

defmodule MyAppWeb.ContactInfo do
  use Phoenix.Component
  def contact_info(assigns), do: ~H"..."
  defp format_phone(phone), do: ...  # Duplicated
end
```

**2. Import/Alias Efficiency**
```elixir
# ✅ One import for related components
defmodule MyAppWeb.ContactLive.Show do
  use MyAppWeb, :live_view
  import MyAppWeb.ContactComponents
  
  def render(assigns) do
    ~H"""
    <.contact_header contact={@contact} />
    <.contact_info contact={@contact} />
    <.contact_actions contact={@contact} />
    """
  end
end

# ❌ Multiple imports
defmodule MyAppWeb.ContactLive.Show do
  use MyAppWeb, :live_view
  import MyAppWeb.ContactHeader
  import MyAppWeb.ContactInfo
  import MyAppWeb.ContactActions
  # ... more imports
end
```

**3. Compilation Efficiency**
```elixir
# Elixir compiles modules, not individual functions
# Fewer modules = faster compilation
# Related components often change together anyway
```

#### When to Use Individual Files

**✅ Individual files for:**

1. **LiveComponents** (they're stateful and complex)
```elixir
# lib/my_app_web/live/components/activity_feed_component.ex
defmodule MyAppWeb.ActivityFeedComponent do
  use MyAppWeb, :live_component
  
  # Complex state management, event handling
  def render(assigns), do: ~H"..."
  def handle_event(...), do: ...
  def update(...), do: ...
end
```

2. **Large, complex function components** (50+ lines)
```elixir
# lib/my_app_web/components/complex_table_component.ex
defmodule MyAppWeb.ComplexTableComponent do
  use Phoenix.Component
  
  def data_table(assigns) do
    # 100+ lines of complex table logic
  end
  
  # Many private helper functions
  defp sort_column(...), do: ...
  defp filter_rows(...), do: ...
  defp paginate_results(...), do: ...
end
```

3. **Highly reusable components** used across domains
```elixir
# lib/my_app_web/components/charts/line_chart_component.ex
defmodule MyAppWeb.Charts.LineChartComponent do
  use Phoenix.Component
  
  def line_chart(assigns) do
    # Complex charting logic used everywhere
  end
end
```

#### Hybrid Approach: Best of Both Worlds

```
lib/my_app_web/
├── components/
│   ├── core_components.ex          # Simple, related UI components
│   ├── contact_components.ex       # Simple contact-related components
│   ├── dashboard_components.ex     # Simple dashboard components
│   └── complex/                    # Individual complex components
│       ├── advanced_table_component.ex
│       ├── rich_text_editor_component.ex
│       └── file_upload_component.ex
├── live/
│   ├── components/                 # All LiveComponents individual
│   │   ├── activity_feed_component.ex
│   │   ├── real_time_chat_component.ex
│   │   └── data_visualization_component.ex
│   └── pages/                      # LiveView pages
│       ├── contact_live/
│       └── dashboard_live.ex
```

#### Decision Matrix

| Component Type | File Organization | Reasoning |
|---|---|---|
| Simple UI components (button, card, badge) | Grouped in modules | Related, share styling helpers |
| Domain components (contact_header, user_profile) | Grouped by domain | Often used together, share logic |
| Complex function components (50+ lines) | Individual files | Easier to maintain, test, review |
| LiveComponents | Individual files | Stateful, complex, often large |
| Cross-domain utilities (charts, editors) | Individual files | Reused across many contexts |

#### Migration Strategy

**Start with grouped approach:**
```elixir
# lib/my_app_web/components/contact_components.ex
defmodule MyAppWeb.ContactComponents do
  use Phoenix.Component
  
  def contact_header(assigns), do: ~H"..."
  def contact_info(assigns), do: ~H"..."
  def contact_sidebar(assigns), do: ~H"..."
end
```

**Split when components become complex:**
```elixir
# When contact_sidebar grows to 50+ lines and has complex logic
# Extract to: lib/my_app_web/components/contact_sidebar_component.ex
defmodule MyAppWeb.ContactSidebarComponent do
  use Phoenix.Component
  
  def contact_sidebar(assigns) do
    # Complex sidebar logic
  end
  
  # Many private helpers
  defp calculate_score(...), do: ...
  defp format_timeline(...), do: ...
  defp determine_actions(...), do: ...
end
```

#### Testing Considerations

**Grouped components:**
```elixir
# test/my_app_web/components/contact_components_test.exs
defmodule MyAppWeb.ContactComponentsTest do
  use MyAppWeb.ConnCase, async: true
  import MyAppWeb.ContactComponents
  
  describe "contact_header/1" do
    test "renders contact name" do
      # Test contact_header
    end
  end
  
  describe "contact_info/1" do
    test "displays contact details" do
      # Test contact_info
    end
  end
end
```

**Individual components:**
```elixir
# test/my_app_web/components/contact_sidebar_component_test.exs
defmodule MyAppWeb.ContactSidebarComponentTest do
  use MyAppWeb.ConnCase, async: true
  import MyAppWeb.ContactSidebarComponent
  
  describe "contact_sidebar/1" do
    test "calculates contact score correctly" do
      # Focused tests for complex logic
    end
  end
end
```

### Component Naming Conventions

```elixir
# ✅ Good: Clear, descriptive names
def contact_header(assigns)          # Domain + function
def user_avatar(assigns)             # Entity + representation
def stat_card(assigns)               # Type + container
def filter_dropdown(assigns)         # Function + UI element

# ❌ Bad: Vague or overly generic names
def header(assigns)                  # Too generic
def card(assigns)                    # Too generic without context
def component(assigns)               # Meaningless
def contact_thing(assigns)           # Vague
```

### Component Composition Patterns

#### Pattern 1: Hierarchical Composition

```elixir
def contact_page(assigns) do
  ~H"""
  <.page_layout>
    <.contact_header contact={@contact} />
    <.page_content>
      <.contact_main_content contact={@contact} />
      <.contact_sidebar contact={@contact} />
    </.page_content>
  </.page_layout>
  """
end
```

#### Pattern 2: Slot-based Composition

```elixir
def dashboard_layout(assigns) do
  ~H"""
  <div class="min-h-screen bg-gray-50">
    <.dashboard_header>
      <%= render_slot(@header) %>
    </.dashboard_header>
    
    <main class="max-w-7xl mx-auto py-6">
      <%= render_slot(@inner_block) %>
    </main>
    
    <aside :if={@sidebar}>
      <%= render_slot(@sidebar) %>
    </aside>
  </div>
  """
end

# Usage
def render(assigns) do
  ~H"""
  <.dashboard_layout>
    <:header>
      <.user_menu user={@current_user} />
    </:header>
    
    <:sidebar>
      <.dashboard_sidebar />
    </:sidebar>
    
    <.dashboard_stats stats={@stats} />
    <.dashboard_charts stats={@stats} />
  </.dashboard_layout>
  """
end
```

#### Pattern 3: Data-driven Composition

```elixir
def contact_fields(assigns) do
  ~H"""
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
    <%= for field <- @fields do %>
      <.field 
        label={field.label} 
        value={field.value} 
        type={field.type} 
      />
    <% end %>
  </div>
  """
end

# Usage in LiveView
def mount(_params, _session, socket) do
  fields = [
    %{label: "Name", value: contact.name, type: :text},
    %{label: "Email", value: contact.email, type: :email},
    %{label: "Status", value: contact.status, type: :badge}
  ]
  
  {:ok, assign(socket, :fields, fields)}
end
```

---

## Part 3: Best Practices & Anti-patterns

### ✅ Best Practices

1. **Single Responsibility**: Each component should have one clear purpose
2. **Consistent Naming**: Use domain + function naming pattern
3. **Prop Drilling Limit**: Keep component trees shallow to avoid excessive prop passing
4. **Testable Components**: Each component should be testable in isolation
5. **Reusable Design**: Build components that can be used across different contexts

### ❌ Anti-patterns

1. **Mega Components**: Components that try to do too much
2. **Prop Drilling**: Passing props through multiple levels unnecessarily
3. **Tight Coupling**: Components that depend on specific parent structure
4. **Inline Styles**: Hardcoded styling that can't be customized
5. **Missing Documentation**: Components without clear usage examples

### Code Review Checklist

- [ ] Is each component focused on a single responsibility?
- [ ] Are component names descriptive and consistent?
- [ ] Can components be tested in isolation?
- [ ] Are there any sections that should be further componentized?
- [ ] Do components accept appropriate props and use proper defaults?
- [ ] Are data attributes used for test selectors?
- [ ] Is the page composition easy to understand?

---

## Summary

Componentizing pages leads to:

- **Better maintainability** through focused, single-purpose components
- **Improved testability** with isolated unit tests
- **Enhanced reusability** across different pages and contexts
- **Cleaner code organization** with clear separation of concerns
- **Easier debugging** when issues are isolated to specific components

The key is to think of pages as **compositions of focused components** rather than monolithic templates. Start with identifying natural boundaries, extract components gradually, and always prioritize clarity and maintainability over premature optimization.

---

## Related Files

For practical implementation details, see:
- [Component Implementation Guide](./component_implementation.md) - Detailed examples and patterns
- [Phoenix Components Recipe](./phoenix_components_recipe.md) - Basic component usage