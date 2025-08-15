# Component Implementation - Practical Patterns and Examples

## Breaking Down Monolithic Pages

This guide shows practical examples of transforming monolithic page templates into well-structured component compositions.

---

## Part 1: Before and After Examples

### Before: Monolithic Contact Page

```elixir
# ❌ Bad: Everything in one giant template
defmodule MyAppWeb.ContactLive.Show do
  use MyAppWeb, :live_view
  alias MyApp.Contacts

  def mount(%{"id" => id}, _session, socket) do
    contact = Contacts.get_contact!(id)
    activities = Contacts.get_activities(contact)
    notes = Contacts.get_notes(contact)
    
    {:ok,
     socket
     |> assign(:contact, contact)
     |> assign(:activities, activities)
     |> assign(:notes, notes)
     |> assign(:editing, false)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center py-6">
            <div class="flex items-center">
              <.link navigate={~p"/contacts"} class="text-gray-500 hover:text-gray-700">
                <svg class="w-5 h-5" fill="none" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
                </svg>
              </.link>
              <h1 class="ml-4 text-2xl font-bold text-gray-900">
                <%= @contact.name %>
              </h1>
            </div>
            <div class="flex space-x-3">
              <button type="button" phx-click="edit" class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm bg-white text-sm font-medium text-gray-700 hover:bg-gray-50">
                Edit
              </button>
              <button type="button" phx-click="delete" class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm bg-red-600 text-sm font-medium text-white hover:bg-red-700">
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Contact Info -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-lg font-medium text-gray-900 mb-4">Contact Information</h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700">Name</label>
                  <p class="mt-1 text-sm text-gray-900"><%= @contact.name %></p>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700">Email</label>
                  <p class="mt-1 text-sm text-gray-900"><%= @contact.email %></p>
                </div>
                <!-- More fields... -->
              </div>
            </div>

            <!-- Activity Feed -->
            <div class="mt-8 bg-white shadow rounded-lg p-6">
              <h2 class="text-lg font-medium text-gray-900 mb-4">Recent Activity</h2>
              <div class="space-y-4">
                <%= for activity <- @activities do %>
                  <div class="flex items-start space-x-3">
                    <div class="flex-shrink-0">
                      <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                        <svg class="w-4 h-4 text-blue-600" fill="currentColor">
                          <!-- Activity icon -->
                        </svg>
                      </div>
                    </div>
                    <div class="flex-1">
                      <p class="text-sm text-gray-900"><%= activity.description %></p>
                      <p class="text-xs text-gray-500"><%= activity.inserted_at %></p>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Sidebar -->
          <div class="lg:col-span-1">
            <!-- Quick Actions -->
            <div class="bg-white shadow rounded-lg p-6 mb-6">
              <h3 class="text-lg font-medium text-gray-900 mb-4">Quick Actions</h3>
              <div class="space-y-3">
                <button type="button" class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700">
                  Send Email
                </button>
                <button type="button" class="w-full flex justify-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50">
                  Schedule Call
                </button>
                <button type="button" class="w-full flex justify-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50">
                  Add Note
                </button>
              </div>
            </div>

            <!-- Notes -->
            <div class="bg-white shadow rounded-lg p-6">
              <h3 class="text-lg font-medium text-gray-900 mb-4">Notes</h3>
              <div class="space-y-3">
                <%= for note <- @notes do %>
                  <div class="p-3 bg-gray-50 rounded-md">
                    <p class="text-sm text-gray-900"><%= note.content %></p>
                    <p class="text-xs text-gray-500 mt-1"><%= note.inserted_at %></p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ... 20 more event handlers
end
```

### After: Componentized Contact Page

```elixir
# ✅ Good: Composed of focused components
defmodule MyAppWeb.ContactLive.Show do
  use MyAppWeb, :live_view
  alias MyApp.Contacts

  def mount(%{"id" => id}, _session, socket) do
    contact = Contacts.get_contact!(id)
    
    {:ok,
     socket
     |> assign(:contact, contact)
     |> assign(:editing, false)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <.contact_header contact={@contact} />
      
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div class="lg:col-span-2">
            <.contact_information contact={@contact} />
            <.live_component 
              module={ActivityFeedComponent} 
              id="activity-feed" 
              contact={@contact} 
            />
          </div>
          
          <div class="lg:col-span-1">
            <.contact_sidebar contact={@contact} />
          </div>
        </div>
      </main>
    </div>
    """
  end

  # Only page-level event handlers here
  def handle_event("edit", _, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("delete", _, socket) do
    # Handle deletion
    {:noreply, socket}
  end
end
```

#### Individual Components

```elixir
# lib/my_app_web/components/contact_components.ex
defmodule MyAppWeb.ContactComponents do
  use Phoenix.Component
  
  @doc """
  Renders the contact page header with navigation and actions.
  """
  attr :contact, :map, required: true
  
  def contact_header(assigns) do
    ~H"""
    <div class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between items-center py-6">
          <div class="flex items-center">
            <.back_button navigate={~p"/contacts"} />
            <h1 class="ml-4 text-2xl font-bold text-gray-900">
              <%= @contact.name %>
            </h1>
          </div>
          <.contact_actions contact={@contact} />
        </div>
      </div>
    </div>
    """
  end
  
  @doc """
  Renders contact information in a card layout.
  """
  attr :contact, :map, required: true
  
  def contact_information(assigns) do
    ~H"""
    <.card header="Contact Information">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.field label="Name" value={@contact.name} />
        <.field label="Email" value={@contact.email} />
        <.field label="Phone" value={@contact.phone} />
        <.field label="Company" value={@contact.company} />
      </div>
    </.card>
    """
  end
  
  @doc """
  Renders the contact sidebar with quick actions and notes.
  """
  attr :contact, :map, required: true
  
  def contact_sidebar(assigns) do
    ~H"""
    <div class="space-y-6">
      <.quick_actions contact={@contact} />
      <.live_component 
        module={NotesComponent} 
        id="notes" 
        contact={@contact} 
      />
    </div>
    """
  end
  
  # Helper components
  defp back_button(assigns) do
    ~H"""
    <.link navigate={@navigate} class="text-gray-500 hover:text-gray-700">
      <svg class="w-5 h-5" fill="none" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
      </svg>
    </.link>
    """
  end
  
  defp contact_actions(assigns) do
    ~H"""
    <div class="flex space-x-3">
      <.button variant="secondary" phx-click="edit">Edit</.button>
      <.button variant="danger" phx-click="delete">Delete</.button>
    </div>
    """
  end
  
  defp quick_actions(assigns) do
    ~H"""
    <.card header="Quick Actions">
      <div class="space-y-3">
        <.button variant="primary" class="w-full" phx-click="send_email">
          Send Email
        </.button>
        <.button variant="secondary" class="w-full" phx-click="schedule_call">
          Schedule Call
        </.button>
        <.button variant="secondary" class="w-full" phx-click="add_note">
          Add Note
        </.button>
      </div>
    </.card>
    """
  end
  
  defp field(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700"><%= @label %></label>
      <p class="mt-1 text-sm text-gray-900"><%= @value %></p>
    </div>
    """
  end
end
```

---

## Part 2: LiveView Dashboard Example

### Before: Monolithic Dashboard

```elixir
# ❌ Bad: Everything in render/1
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Navigation -->
      <nav class="bg-white shadow-sm">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <h1 class="text-xl font-semibold">Dashboard</h1>
            </div>
            <div class="flex items-center space-x-4">
              <div class="relative">
                <select class="form-select" phx-change="filter_changed">
                  <option value="all">All Time</option>
                  <option value="week">This Week</option>
                  <option value="month">This Month</option>
                </select>
              </div>
              <div class="flex items-center space-x-2">
                <img src={@current_user.avatar} class="w-8 h-8 rounded-full" />
                <span class="text-sm text-gray-700"><%= @current_user.name %></span>
              </div>
            </div>
          </div>
        </div>
      </nav>

      <!-- Main Content -->
      <main class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <!-- Stats -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="p-5">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <svg class="h-6 w-6 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                  <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">Total Contacts</dt>
                    <dd class="text-lg font-medium text-gray-900"><%= @stats.total_contacts %></dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
          <!-- 3 more similar stat cards... -->
        </div>

        <!-- Charts Section -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900">Contact Growth</h3>
              <div class="mt-5">
                <!-- Chart component would go here -->
                <div class="h-64 bg-gray-100 rounded flex items-center justify-center">
                  <span class="text-gray-500">Contact Growth Chart</span>
                </div>
              </div>
            </div>
          </div>
          
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900">Activity Overview</h3>
              <div class="mt-5">
                <!-- Chart component would go here -->
                <div class="h-64 bg-gray-100 rounded flex items-center justify-center">
                  <span class="text-gray-500">Activity Chart</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Recent Activity -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Recent Activity</h3>
            <div class="space-y-4">
              <%= for activity <- @recent_activities do %>
                <div class="flex items-start space-x-3">
                  <div class="flex-shrink-0">
                    <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                      <svg class="w-4 h-4 text-blue-600" fill="currentColor">
                        <!-- Activity icon -->
                      </svg>
                    </div>
                  </div>
                  <div class="flex-1">
                    <p class="text-sm text-gray-900"><%= activity.description %></p>
                    <p class="text-xs text-gray-500"><%= activity.inserted_at %></p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # ... many event handlers
end
```

### After: Componentized Dashboard

```elixir
# ✅ Good: Clean composition
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view
  alias MyApp.Dashboard

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:filter, "all")
     |> load_dashboard_data()}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <.dashboard_header 
        current_user={@current_user} 
        filter={@filter} 
      />
      
      <main class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <.dashboard_stats stats={@stats} />
        <.dashboard_charts stats={@stats} />
        <.live_component 
          module={RecentActivityComponent} 
          id="recent-activity" 
          activities={@recent_activities} 
        />
      </main>
    </div>
    """
  end

  def handle_event("filter_changed", %{"value" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> load_dashboard_data()}
  end

  defp load_dashboard_data(socket) do
    filter = socket.assigns.filter
    
    socket
    |> assign(:stats, Dashboard.get_stats(filter))
    |> assign(:recent_activities, Dashboard.get_recent_activities(filter))
  end
end
```

#### Dashboard Components

```elixir
# lib/my_app_web/components/dashboard_components.ex
defmodule MyAppWeb.DashboardComponents do
  use Phoenix.Component
  
  @doc """
  Renders the dashboard header with user info and filters.
  """
  attr :current_user, :map, required: true
  attr :filter, :string, required: true
  
  def dashboard_header(assigns) do
    ~H"""
    <nav class="bg-white shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex items-center">
            <h1 class="text-xl font-semibold">Dashboard</h1>
          </div>
          <div class="flex items-center space-x-4">
            <.filter_dropdown current_filter={@filter} />
            <.user_menu user={@current_user} />
          </div>
        </div>
      </div>
    </nav>
    """
  end
  
  @doc """
  Renders dashboard statistics cards.
  """
  attr :stats, :map, required: true
  
  def dashboard_stats(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
      <.stat_card 
        title="Total Contacts" 
        value={@stats.total_contacts} 
        icon="users" 
      />
      <.stat_card 
        title="New This Month" 
        value={@stats.new_contacts} 
        icon="user-plus" 
      />
      <.stat_card 
        title="Active Deals" 
        value={@stats.active_deals} 
        icon="currency-dollar" 
      />
      <.stat_card 
        title="Conversion Rate" 
        value="#{@stats.conversion_rate}%" 
        icon="chart-bar" 
      />
    </div>
    """
  end
  
  @doc """
  Renders dashboard charts section.
  """
  attr :stats, :map, required: true
  
  def dashboard_charts(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
      <.chart_card title="Contact Growth">
        <.live_component 
          module={ContactGrowthChart} 
          id="contact-growth-chart" 
          data={@stats.growth_data} 
        />
      </.chart_card>
      
      <.chart_card title="Activity Overview">
        <.live_component 
          module={ActivityOverviewChart} 
          id="activity-overview-chart" 
          data={@stats.activity_data} 
        />
      </.chart_card>
    </div>
    """
  end
  
  # Helper components
  defp filter_dropdown(assigns) do
    ~H"""
    <div class="relative">
      <select class="form-select" phx-change="filter_changed">
        <option value="all" selected={@current_filter == "all"}>All Time</option>
        <option value="week" selected={@current_filter == "week"}>This Week</option>
        <option value="month" selected={@current_filter == "month"}>This Month</option>
      </select>
    </div>
    """
  end
  
  defp user_menu(assigns) do
    ~H"""
    <div class="flex items-center space-x-2">
      <.user_avatar user={@user} size="sm" />
      <span class="text-sm text-gray-700"><%= @user.name %></span>
    </div>
    """
  end
  
  defp stat_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <.icon name={@icon} class="h-6 w-6 text-gray-400" />
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate"><%= @title %></dt>
            <dd class="text-lg font-medium text-gray-900"><%= @value %></dd>
          </dl>
        </div>
      </div>
    </.card>
    """
  end
  
  defp chart_card(assigns) do
    ~H"""
    <.card>
      <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
        <%= @title %>
      </h3>
      <div class="mt-5">
        <%= render_slot(@inner_block) %>
      </div>
    </.card>
    """
  end
end
```

---

## Part 3: Testing Componentized Pages

### Testing Strategy

1. **Unit test individual components** in isolation
2. **Integration test page composition** with components
3. **End-to-end test user workflows** across composed pages

### Component Unit Tests

```elixir
defmodule MyAppWeb.DashboardComponentsTest do
  use MyAppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import MyAppWeb.DashboardComponents

  describe "dashboard_stats/1" do
    test "renders all stat cards" do
      stats = %{
        total_contacts: 150,
        new_contacts: 12,
        active_deals: 8,
        conversion_rate: 15.5
      }
      
      html = rendered_to_string(~H"""
      <.dashboard_stats stats={stats} />
      """)
      
      assert html =~ "Total Contacts"
      assert html =~ "150"
      assert html =~ "New This Month"
      assert html =~ "12"
      assert html =~ "15.5%"
    end
  end

  describe "filter_dropdown/1" do
    test "shows current filter as selected" do
      assigns = %{current_filter: "week"}
      
      html = rendered_to_string(~H"""
      <.filter_dropdown current_filter={@current_filter} />
      """)
      
      assert html =~ ~s(selected="selected")
      assert html =~ "This Week"
    end
  end
end
```

### Page Composition Tests

```elixir
defmodule MyAppWeb.DashboardLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders all dashboard sections", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    
    # Test that all main components are rendered
    assert has_element?(view, "[data-test='dashboard-header']")
    assert has_element?(view, "[data-test='dashboard-stats']")
    assert has_element?(view, "[data-test='dashboard-charts']")
    assert has_element?(view, "[data-test='recent-activity']")
  end

  test "filter changes update stats", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    
    # Change filter
    view
    |> form("select[phx-change='filter_changed']")
    |> render_change(%{"value" => "week"})
    
    # Verify stats component receives updated data
    assert has_element?(view, "[data-test='stat-card']")
    # Assert specific stat values changed
  end
end
```

### Cross-component Integration Tests

```elixir
defmodule MyAppWeb.ContactPageIntegrationTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  test "contact actions flow through components", %{conn: conn} do
    contact = insert(:contact)
    {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")
    
    # Action in header component
    view |> element("[data-test='edit-button']") |> render_click()
    
    # Should affect main content component
    assert has_element?(view, "[data-test='contact-form']")
    
    # Form submission should update info component
    view
    |> form("#contact-form")
    |> render_submit(%{contact: %{name: "Updated Name"}})
    
    assert has_element?(view, "[data-test='contact-name']", "Updated Name")
  end
end
```

---

## Part 4: Migration Strategy

### Step 1: Identify Component Boundaries

```elixir
# Audit existing pages and mark component boundaries
def render(assigns) do
  ~H"""
  <div class="page">
    <!-- COMPONENT: page_header -->
    <header>...</header>
    
    <!-- COMPONENT: main_content -->
    <main>
      <!-- COMPONENT: stats_section -->
      <section class="stats">...</section>
      
      <!-- COMPONENT: data_table -->
      <div class="table-container">...</div>
    </main>
    
    <!-- COMPONENT: sidebar -->
    <aside>...</aside>
  </div>
  """
end
```

### Step 2: Extract Components Gradually

```elixir
# Start with leaf components (no dependencies)
def page_header(assigns) do
  ~H"""
  <header class="...">
    <h1><%= @title %></h1>
    <.user_menu user={@current_user} />
  </header>
  """
end

# Then extract container components
def main_content(assigns) do
  ~H"""
  <main class="...">
    <.stats_section stats={@stats} />
    <.data_table data={@data} />
  </main>
  """
end

# Finally, compose the page
def render(assigns) do
  ~H"""
  <div class="page">
    <.page_header title={@title} current_user={@current_user} />
    <.main_content stats={@stats} data={@data} />
    <.sidebar items={@sidebar_items} />
  </div>
  """
end
```

### Step 3: Refactor Tests

```elixir
# Update tests to work with new component structure
test "page displays all sections" do
  # Test composition rather than HTML details
  {:ok, view, _html} = live(conn, ~p"/dashboard")
  
  assert has_element?(view, "[data-test='page-header']")
  assert has_element?(view, "[data-test='main-content']")
  assert has_element?(view, "[data-test='sidebar']")
end
```

---

## Summary

The examples in this guide demonstrate how to transform monolithic page templates into maintainable, testable component compositions. Key takeaways:

1. **Start with clear boundaries** - Identify distinct functional areas
2. **Extract gradually** - Begin with leaf components, then containers
3. **Test at multiple levels** - Unit tests for components, integration tests for composition
4. **Keep pages simple** - LiveView modules should focus on data management and event handling

This approach leads to better maintainability, easier testing, and more reusable code across your Phoenix application.

---

## Related Files

For architectural guidance, see:
- [Component Architecture Guide](./component_architecture.md) - Patterns and organization principles
- [Phoenix Components Recipe](./phoenix_components_recipe.md) - Basic component usage