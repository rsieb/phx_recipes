# Building Single-Page Web Apps with Phoenix: A Practical MVP Guide

## Introduction

This recipe provides practical guidance for building modern web applications with Phoenix that feel like single-page apps while using the right tool for each job. The goal is fast development using Phoenix best practices, not architectural purity.

### What Problem This Solves
- Decision paralysis: "Should I use LiveView or a regular controller for this page?"
- Overengineering simple pages with unnecessary LiveView complexity
- Underusing LiveView when it would actually make development faster
- Building apps that feel modern without reinventing the wheel

### Key Principles
1. **Use what's fastest to build and maintain**
2. **Leverage Phoenix's strengths**
3. **Don't fight the framework**
4. **MVP first, optimize later**

## Quick Decision Guide

### Use Regular Controllers When:
- **Static content**: About pages, terms of service, marketing pages
- **Simple forms**: Contact forms, basic CRUD with standard validation
- **List pages**: Blog index, product catalog without real-time features
- **It's faster**: When you can copy/paste from existing controller patterns

### Use LiveView When:
- **Real-time updates**: Chat, notifications, live dashboards
- **Complex forms**: Multi-step forms, dynamic validation, file uploads
- **Interactive widgets**: Search with instant results, filters, modals
- **It's actually easier**: When the alternative requires complex JavaScript

## Basic Patterns

### 1. Standard Controller/View Pattern

```elixir
# lib/my_app_web/controllers/blog_controller.ex
defmodule MyAppWeb.BlogController do
  use MyAppWeb, :controller

  def index(conn, params) do
    posts = MyApp.Blog.list_posts(params)
    render(conn, :index, posts: posts)
  end

  def show(conn, %{"id" => id}) do
    post = MyApp.Blog.get_post!(id)
    render(conn, :show, post: post)
  end

  def new(conn, _params) do
    changeset = MyApp.Blog.change_post(%MyApp.Blog.Post{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"post" => post_params}) do
    case MyApp.Blog.create_post(post_params) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post created successfully.")
        |> redirect(to: ~p"/blog/#{post}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
```

```heex
<!-- lib/my_app_web/templates/blog/index.html.heex -->
<div class="blog-index">
  <div class="header">
    <h1>Blog Posts</h1>
    <.link navigate={~p"/blog/new"} class="btn btn-primary">
      New Post
    </.link>
  </div>

  <div class="posts">
    <%= for post <- @posts do %>
      <article class="post-card">
        <h2>
          <.link navigate={~p"/blog/#{post}"}>
            <%= post.title %>
          </.link>
        </h2>
        <p><%= post.excerpt %></p>
        <time><%= Calendar.strftime(post.inserted_at, "%B %d, %Y") %></time>
      </article>
    <% end %>
  </div>
</div>
```

**Why this works**: Simple, fast to build, SEO-friendly, uses standard Phoenix patterns.

### 2. LiveView for Interactive Features

```elixir
# lib/my_app_web/live/search_live.ex
defmodule MyAppWeb.SearchLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", results: [])}
  end

  def handle_event("search", %{"query" => query}, socket) do
    results = MyApp.Search.search(query)
    {:noreply, assign(socket, query: query, results: results)}
  end

  def render(assigns) do
    ~H"""
    <div class="search-page">
      <form phx-change="search" phx-submit="search">
        <input 
          type="text" 
          name="query" 
          value={@query}
          placeholder="Search..."
          phx-debounce="300"
        />
      </form>

      <div class="results">
        <%= for result <- @results do %>
          <div class="result">
            <.link navigate={result.path}>
              <h3><%= result.title %></h3>
              <p><%= result.excerpt %></p>
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
```

**Why LiveView here**: Instant search without page reloads is much better UX and actually simpler than building AJAX search.

### 3. Hybrid Approach: Controller with LiveView Components

```elixir
# lib/my_app_web/controllers/product_controller.ex
defmodule MyAppWeb.ProductController do
  use MyAppWeb, :controller

  def show(conn, %{"id" => id}) do
    product = MyApp.Catalog.get_product!(id)
    render(conn, :show, product: product)
  end
end
```

```heex
<!-- lib/my_app_web/templates/product/show.html.heex -->
<div class="product-page">
  <div class="product-info">
    <h1><%= @product.name %></h1>
    <p><%= @product.description %></p>
    <div class="price">$<%= @product.price %></div>
  </div>

  <!-- Use LiveView component for the interactive cart -->
  <.live_component 
    module={MyAppWeb.CartButtonComponent} 
    id="cart-button"
    product={@product}
  />

  <!-- Use LiveView component for reviews -->
  <.live_component 
    module={MyAppWeb.ReviewsComponent} 
    id="reviews"
    product_id={@product.id}
  />
</div>
```

```elixir
# lib/my_app_web/live/cart_button_component.ex
defmodule MyAppWeb.CartButtonComponent do
  use MyAppWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="cart-section">
      <button 
        phx-click="add_to_cart" 
        phx-target={@myself}
        class="btn btn-primary"
      >
        Add to Cart
      </button>
      
      <%= if @added do %>
        <p class="success">Added to cart!</p>
      <% end %>
    </div>
    """
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns) |> assign(added: false)}
  end

  def handle_event("add_to_cart", _params, socket) do
    MyApp.Cart.add_item(socket.assigns.product)
    {:noreply, assign(socket, added: true)}
  end
end
```

**Why this works**: Static product info loads fast, interactive features use LiveView where it makes sense.

## Common Patterns and Examples

### 1. Navigation That Feels Like SPA

Use Phoenix's built-in `navigate` attribute for smooth transitions:

```heex
<!-- In your layout -->
<nav>
  <.link navigate={~p"/"}>Home</.link>
  <.link navigate={~p"/blog"}>Blog</.link>
  <.link navigate={~p"/products"}>Products</.link>
  <.link navigate={~p"/contact"}>Contact</.link>
</nav>
```

This gives you smooth page transitions without any custom JavaScript.

### 2. Forms with Better UX

For simple forms, stick with controllers:

```heex
<!-- Regular form - fast to build -->
<.simple_form for={@changeset} action={~p"/contact"}>
  <.input field={@changeset[:name]} label="Name" />
  <.input field={@changeset[:email]} label="Email" />
  <.input field={@changeset[:message]} type="textarea" label="Message" />
  <:actions>
    <.button>Send Message</.button>
  </:actions>
</.simple_form>
```

For complex forms, use LiveView:

```elixir
# Multi-step form or dynamic validation
defmodule MyAppWeb.OnboardingLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, step: 1, user_data: %{})}
  end

  def handle_event("next_step", params, socket) do
    # Validate current step, move to next
    {:noreply, assign(socket, step: socket.assigns.step + 1)}
  end

  def render(assigns) do
    ~H"""
    <div class="onboarding">
      <%= case @step do %>
        <% 1 -> %>
          <!-- Step 1: Basic Info -->
        <% 2 -> %>
          <!-- Step 2: Preferences -->
        <% 3 -> %>
          <!-- Step 3: Confirmation -->
      <% end %>
    </div>
    """
  end
end
```

### 3. Lists with Filters

If filters are simple, use regular controllers with URL params:

```elixir
def index(conn, params) do
  products = MyApp.Catalog.list_products(params)
  render(conn, :index, products: products, filters: params)
end
```

```heex
<form method="get">
  <select name="category">
    <option value="">All Categories</option>
    <%= for category <- @categories do %>
      <option value={category.id} selected={@filters["category"] == category.id}>
        <%= category.name %>
      </option>
    <% end %>
  </select>
  <button type="submit">Filter</button>
</form>
```

If you want instant filtering, use LiveView:

```elixir
def handle_event("filter", %{"category" => category}, socket) do
  products = MyApp.Catalog.list_products(%{"category" => category})
  {:noreply, assign(socket, products: products, selected_category: category)}
end
```

## File Organization for MVPs

Keep it simple:

```
lib/my_app_web/
├── controllers/
│   ├── page_controller.ex          # Static pages
│   ├── blog_controller.ex          # Simple CRUD
│   └── contact_controller.ex       # Forms
├── live/
│   ├── search_live.ex              # Interactive search
│   ├── dashboard_live.ex           # Real-time dashboard  
│   └── components/
│       ├── cart_button_component.ex
│       └── reviews_component.ex
└── templates/
    ├── layout/
    │   └── app.html.heex
    ├── page/
    ├── blog/
    └── contact/
```

## Decision Examples

### Example 1: User Profile Page

**Choose Controller** if it's just displaying/editing user info:
- Simple form
- Standard validation
- Redirect after save

**Choose LiveView** if you need:
- Real-time avatar upload with preview
- Dynamic form fields based on user type
- Live validation as user types

### Example 2: Product Listing

**Choose Controller** for basic listing:
- Simple pagination
- Basic search via URL params
- Static product cards

**Choose LiveView** if you want:
- Instant search as you type
- Real-time filters
- Infinite scroll
- Live inventory updates

### Example 3: Dashboard

**Choose Controller** for simple dashboards:
- Static charts/metrics
- Standard navigation
- Periodic refresh is okay

**Choose LiveView** for interactive dashboards:
- Real-time data updates
- Interactive charts
- Live notifications

## Testing Strategy

### Controller Tests (Fast and Simple)

```elixir
defmodule MyAppWeb.BlogControllerTest do
  use MyAppWeb.ConnCase

  test "lists all posts", %{conn: conn} do
    post = insert(:post)
    conn = get(conn, ~p"/blog")
    assert html_response(conn, 200) =~ post.title
  end

  test "creates post with valid data", %{conn: conn} do
    valid_attrs = %{title: "Test", content: "Content"}
    conn = post(conn, ~p"/blog", post: valid_attrs)
    assert redirected_to(conn) == ~p"/blog/#{Post.last_id()}"
  end
end
```

### LiveView Tests (When You Need Interactivity)

```elixir
defmodule MyAppWeb.SearchLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  test "searches as user types", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search")
    
    view
    |> form("form", %{query: "elixir"})
    |> render_change()

    assert has_element?(view, ".result", "Elixir Guide")
  end
end
```

## Migration Strategy for Existing Apps

### Step 1: Audit Current LiveViews

Ask for each LiveView:
1. Is this actually interactive? → Keep as LiveView
2. Is this just displaying data? → Consider converting to controller
3. Is this a simple form? → Consider converting to controller

### Step 2: Convert Low-Hanging Fruit

Start with:
- Static pages that became LiveViews for no reason
- Simple CRUD that doesn't need real-time features
- Basic forms without complex validation

### Step 3: Optimize the Keepers

For LiveViews you're keeping:
- Make sure they're actually leveraging LiveView features
- Consider breaking large LiveViews into smaller components
- Add proper error handling and loading states

## Real-World MVP Example

```elixir
# A simple blog with some interactive features
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/", MyAppWeb do
    pipe_through :browser

    # Static pages - use controllers
    get "/", PageController, :home
    get "/about", PageController, :about

    # Simple CRUD - use controllers  
    resources "/posts", PostController
    get "/contact", ContactController, :new
    post "/contact", ContactController, :create

    # Interactive features - use LiveView
    live "/search", SearchLive
    live "/dashboard", DashboardLive
  end
end
```

This gives you a modern, fast-loading web app that feels like a SPA without overcomplicating things. Users get smooth navigation between pages, and you get the development speed of using the right tool for each job.

**Remember**: The goal is shipping an MVP quickly while maintaining good user experience. Use Phoenix's strengths, don't fight them.