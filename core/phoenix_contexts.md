# Phoenix Contexts Recipe

## Prerequisites & Related Recipes

### Prerequisites
- Basic understanding of Elixir modules and functions
- Familiarity with Ecto schemas and database operations
- Understanding of Phoenix application structure

### Related Recipes
- **Foundation**: [Ecto Schema Basics](../data/ecto_schema_basics.md) - Understanding schemas before building contexts
- **Testing**: [Comprehensive Testing Guide](../testing/comprehensive_testing_guide.md) - Testing context functions
- **Web Layer**: [Phoenix LiveView Basics](../components/phoenix_liveview_basics.md) - Using contexts in LiveView
- **Advanced Patterns**: [Database Performance](../data/database_performance.md) - Optimizing context queries
- **TDD Approach**: [Phoenix TDD Recipe](../workflows/phoenix_tdd_recipe.md) - Test-driven context development

## Introduction

Contexts are Phoenix's way of organizing related functionality and creating boundaries between different parts of your application. They act as dedicated modules that expose and group related functionality, serving as the API layer between your web interface and your data layer.

## Basic Context Structure

```elixir
defmodule MyApp.Accounts do
  @moduledoc """
  The Accounts context handles user management and authentication.
  """

  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Accounts.User

  @doc """
  Returns the list of users.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.
  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
```

## Context with Business Logic

```elixir
defmodule MyApp.Accounts do
  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Accounts.{User, Profile}

  # Authentication functions
  def authenticate_user(email, password) do
    case get_user_by_email(email) do
      %User{} = user ->
        if verify_password(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end
      nil ->
        # Still run password verification to prevent timing attacks
        verify_password(password, "dummy_hash")
        {:error, :invalid_credentials}
    end
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        send_welcome_email(user)
        {:ok, user}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def activate_user(%User{} = user) do
    user
    |> User.activation_changeset()
    |> Repo.update()
    |> case do
      {:ok, user} ->
        send_activation_email(user)
        {:ok, user}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def deactivate_user(%User{} = user) do
    user
    |> User.deactivation_changeset()
    |> Repo.update()
  end

  # User profile management
  def get_user_profile(%User{} = user) do
    Repo.get_by(Profile, user_id: user.id)
  end

  def create_or_update_profile(%User{} = user, attrs) do
    case get_user_profile(user) do
      %Profile{} = profile ->
        update_profile(profile, attrs)
      nil ->
        create_profile(user, attrs)
    end
  end

  defp create_profile(%User{} = user, attrs) do
    %Profile{}
    |> Profile.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  defp update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
  end

  # Query functions
  def list_active_users do
    User
    |> where([u], u.active == true)
    |> order_by([u], u.name)
    |> Repo.all()
  end

  def search_users(query) do
    User
    |> where([u], ilike(u.name, ^"%#{query}%") or ilike(u.email, ^"%#{query}%"))
    |> limit(10)
    |> Repo.all()
  end

  def get_users_by_role(role) do
    User
    |> where([u], u.role == ^role)
    |> Repo.all()
  end

  # Private helper functions
  defp verify_password(password, hash) do
    # Use your preferred password hashing library
    :crypto.hash(:sha256, password) == hash
  end

  defp send_welcome_email(%User{} = user) do
    # Send welcome email logic
    {:ok, "email_sent"}
  end

  defp send_activation_email(%User{} = user) do
    # Send activation email logic
    {:ok, "activation_email_sent"}
  end
end
```

## Context with Complex Queries

```elixir
defmodule MyApp.Blog do
  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Blog.{Post, Comment}
  alias MyApp.Accounts.User

  @doc """
  Lists published posts with pagination and preloading.
  """
  def list_published_posts(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)
    preload = Keyword.get(opts, :preload, [])

    Post
    |> where([p], p.status == :published)
    |> where([p], p.published_at <= ^DateTime.utc_now())
    |> order_by([p], desc: p.published_at)
    |> preload(^preload)
    |> paginate(page, per_page)
    |> Repo.all()
  end

  @doc """
  Gets posts by author with statistics.
  """
  def list_posts_by_author(%User{} = author, opts \\ []) do
    include_drafts = Keyword.get(opts, :include_drafts, false)
    
    query = 
      Post
      |> where([p], p.author_id == ^author.id)
      |> order_by([p], desc: p.inserted_at)

    query = if include_drafts do
      query
    else
      where(query, [p], p.status == :published)
    end

    Repo.all(query)
  end

  @doc """
  Gets post statistics for dashboard.
  """
  def get_post_statistics(%User{} = author) do
    base_query = Post |> where([p], p.author_id == ^author.id)

    %{
      total_posts: Repo.aggregate(base_query, :count),
      published_posts: base_query |> where([p], p.status == :published) |> Repo.aggregate(:count),
      draft_posts: base_query |> where([p], p.status == :draft) |> Repo.aggregate(:count),
      total_views: base_query |> Repo.aggregate(:sum, :view_count) || 0
    }
  end

  @doc """
  Searches posts with full-text search.
  """
  def search_posts(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    
    Post
    |> where([p], p.status == :published)
    |> where([p], fragment("? @@ plainto_tsquery(?)", p.search_vector, ^query))
    |> order_by([p], fragment("ts_rank(?, plainto_tsquery(?)) DESC", p.search_vector, ^query))
    |> limit(^limit)
    |> preload([:author])
    |> Repo.all()
  end

  @doc """
  Gets popular posts based on views and comments.
  """
  def list_popular_posts(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    limit = Keyword.get(opts, :limit, 10)
    since = DateTime.utc_now() |> DateTime.add(-days, :day)

    Post
    |> join(:left, [p], c in Comment, on: c.post_id == p.id)
    |> where([p], p.status == :published)
    |> where([p], p.published_at >= ^since)
    |> group_by([p], p.id)
    |> order_by([p, c], desc: fragment("? + COUNT(?)", p.view_count, c.id))
    |> limit(^limit)
    |> preload([:author])
    |> Repo.all()
  end

  defp paginate(query, page, per_page) do
    offset = (page - 1) * per_page
    
    query
    |> limit(^per_page)
    |> offset(^offset)
  end
end
```

## Context with Business Rules

```elixir
defmodule MyApp.Billing do
  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Billing.{Subscription, Payment, Invoice}
  alias MyApp.Accounts.User

  @doc """
  Creates a subscription with business rules validation.
  """
  def create_subscription(%User{} = user, plan_id, payment_method) do
    with :ok <- validate_subscription_eligibility(user),
         :ok <- validate_plan_availability(plan_id),
         {:ok, payment} <- process_payment(user, plan_id, payment_method),
         {:ok, subscription} <- create_subscription_record(user, plan_id, payment) do
      
      # Send confirmation and setup account
      send_subscription_confirmation(user, subscription)
      setup_subscription_features(user, subscription)
      
      {:ok, subscription}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels a subscription with proper cleanup.
  """
  def cancel_subscription(%User{} = user, reason \\ nil) do
    with {:ok, subscription} <- get_active_subscription(user),
         :ok <- validate_cancellation_eligibility(subscription),
         {:ok, updated_subscription} <- cancel_subscription_record(subscription, reason) do
      
      # Handle cancellation side effects
      schedule_data_deletion(user, updated_subscription)
      send_cancellation_confirmation(user, updated_subscription)
      
      {:ok, updated_subscription}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upgrades or downgrades a subscription.
  """
  def change_subscription_plan(%User{} = user, new_plan_id) do
    with {:ok, current_subscription} <- get_active_subscription(user),
         :ok <- validate_plan_change(current_subscription, new_plan_id),
         {:ok, proration} <- calculate_proration(current_subscription, new_plan_id),
         {:ok, payment} <- process_proration_payment(user, proration),
         {:ok, updated_subscription} <- update_subscription_plan(current_subscription, new_plan_id) do
      
      # Handle plan change side effects
      update_user_features(user, updated_subscription)
      send_plan_change_confirmation(user, updated_subscription)
      
      {:ok, updated_subscription}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Business rule validation functions
  defp validate_subscription_eligibility(%User{} = user) do
    cond do
      has_active_subscription?(user) ->
        {:error, :already_subscribed}
      
      has_payment_issues?(user) ->
        {:error, :payment_issues}
      
      is_banned?(user) ->
        {:error, :user_banned}
      
      true ->
        :ok
    end
  end

  defp validate_plan_availability(plan_id) do
    case get_plan(plan_id) do
      %{active: true} = _plan -> :ok
      %{active: false} -> {:error, :plan_not_available}
      nil -> {:error, :plan_not_found}
    end
  end

  defp validate_cancellation_eligibility(subscription) do
    case subscription.status do
      :active -> :ok
      :past_due -> :ok
      :cancelled -> {:error, :already_cancelled}
      _ -> {:error, :invalid_status}
    end
  end

  # Helper functions
  defp get_active_subscription(%User{} = user) do
    case Repo.get_by(Subscription, user_id: user.id, status: :active) do
      %Subscription{} = subscription -> {:ok, subscription}
      nil -> {:error, :no_active_subscription}
    end
  end

  defp has_active_subscription?(%User{} = user) do
    Repo.exists?(
      from s in Subscription,
      where: s.user_id == ^user.id and s.status == :active
    )
  end

  defp has_payment_issues?(%User{} = user) do
    Repo.exists?(
      from p in Payment,
      where: p.user_id == ^user.id and p.status == :failed,
      where: p.inserted_at >= ago(30, "day")
    )
  end

  defp is_banned?(%User{} = user) do
    user.status == :banned
  end

  # Implementation stubs (would contain actual business logic)
  defp process_payment(_user, _plan_id, _payment_method), do: {:ok, %Payment{}}
  defp create_subscription_record(_user, _plan_id, _payment), do: {:ok, %Subscription{}}
  defp send_subscription_confirmation(_user, _subscription), do: :ok
  defp setup_subscription_features(_user, _subscription), do: :ok
  defp cancel_subscription_record(_subscription, _reason), do: {:ok, %Subscription{}}
  defp schedule_data_deletion(_user, _subscription), do: :ok
  defp send_cancellation_confirmation(_user, _subscription), do: :ok
  defp validate_plan_change(_subscription, _new_plan_id), do: :ok
  defp calculate_proration(_subscription, _new_plan_id), do: {:ok, %{}}
  defp process_proration_payment(_user, _proration), do: {:ok, %Payment{}}
  defp update_subscription_plan(_subscription, _new_plan_id), do: {:ok, %Subscription{}}
  defp update_user_features(_user, _subscription), do: :ok
  defp send_plan_change_confirmation(_user, _subscription), do: :ok
  defp get_plan(_plan_id), do: %{active: true}
end
```

## Context with Cross-Context Communication

```elixir
defmodule MyApp.Orders do
  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Orders.{Order, OrderItem}
  alias MyApp.Accounts
  alias MyApp.Inventory
  alias MyApp.Billing

  @doc """
  Creates an order with inventory checks and billing integration.
  """
  def create_order(%{user_id: user_id, items: items} = attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:user, fn _repo, _changes ->
      case Accounts.get_user(user_id) do
        %Accounts.User{} = user -> {:ok, user}
        nil -> {:error, :user_not_found}
      end
    end)
    |> Ecto.Multi.run(:validate_items, fn _repo, _changes ->
      validate_order_items(items)
    end)
    |> Ecto.Multi.run(:reserve_inventory, fn _repo, %{validate_items: items} ->
      Inventory.reserve_items(items)
    end)
    |> Ecto.Multi.insert(:order, fn %{user: user} ->
      Order.changeset(%Order{}, Map.put(attrs, :user_id, user.id))
    end)
    |> Ecto.Multi.run(:create_items, fn _repo, %{order: order, validate_items: items} ->
      create_order_items(order, items)
    end)
    |> Ecto.Multi.run(:process_payment, fn _repo, %{order: order, user: user} ->
      Billing.charge_order(user, order)
    end)
    |> Ecto.Multi.run(:confirm_order, fn _repo, %{order: order, process_payment: payment} ->
      confirm_order(order, payment)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{confirm_order: order}} ->
        # Send confirmation email
        send_order_confirmation(order)
        {:ok, order}
      
      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Updates order status with side effects.
  """
  def update_order_status(%Order{} = order, new_status) do
    with {:ok, updated_order} <- update_order(order, %{status: new_status}),
         :ok <- handle_status_change(updated_order, order.status, new_status) do
      {:ok, updated_order}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_order_items(items) do
    # Validate item structure and availability
    validated_items = Enum.map(items, fn item ->
      case Inventory.get_product(item.product_id) do
        %Inventory.Product{} = product ->
          %{product: product, quantity: item.quantity}
        nil ->
          {:error, "Product #{item.product_id} not found"}
      end
    end)

    case Enum.find(validated_items, &match?({:error, _}, &1)) do
      nil -> {:ok, validated_items}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_order_items(order, items) do
    order_items = Enum.map(items, fn %{product: product, quantity: quantity} ->
      %OrderItem{
        order_id: order.id,
        product_id: product.id,
        quantity: quantity,
        price: product.price,
        name: product.name
      }
    end)

    case Repo.insert_all(OrderItem, order_items, returning: true) do
      {_count, items} -> {:ok, items}
      error -> error
    end
  end

  defp confirm_order(order, payment) do
    order
    |> Order.changeset(%{status: :confirmed, payment_id: payment.id})
    |> Repo.update()
  end

  defp handle_status_change(order, old_status, new_status) do
    case {old_status, new_status} do
      {:pending, :confirmed} ->
        # Inventory was already reserved, confirm it
        Inventory.confirm_reservation(order.id)
        
      {:confirmed, :shipped} ->
        # Start tracking and send shipping notification
        start_shipping_tracking(order)
        send_shipping_notification(order)
        
      {:shipped, :delivered} ->
        # Complete the order and handle rewards
        complete_order(order)
        
      {:confirmed, :cancelled} ->
        # Release inventory and process refund
        Inventory.release_reservation(order.id)
        Billing.refund_order(order)
        
      _ ->
        :ok
    end
  end

  # Implementation stubs
  defp send_order_confirmation(_order), do: :ok
  defp start_shipping_tracking(_order), do: :ok
  defp send_shipping_notification(_order), do: :ok
  defp complete_order(_order), do: :ok
end
```

## Tips & Best Practices

### Context Organization
- Keep contexts focused on a single domain or business capability
- Use descriptive names that reflect business concepts, not technical ones
- Organize related schemas within the same context directory

### Function Design
- Make functions return consistent patterns (`{:ok, result}` or `{:error, reason}`)
- Use descriptive function names that indicate their purpose
- Keep functions focused on single responsibilities

### Cross-Context Communication
- Use public functions to communicate between contexts
- Avoid direct database access between contexts
- Use `Ecto.Multi` for operations that span multiple contexts

### Query Organization
- Keep simple queries in context functions
- Use private functions for complex query building
- Consider using query modules for very complex queries

### Error Handling
- Use consistent error tuples throughout your context
- Provide meaningful error messages that help users understand what went wrong
- Handle edge cases gracefully

### Testing
- Test context functions independently of web layer
- Use data factories for consistent test data
- Mock external dependencies when testing business logic

## References

- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [Thinking Elixir: Contexts](https://thinkingelixir.com/contexts/)
- [Ecto Query Documentation](https://hexdocs.pm/ecto/Ecto.Query.html)
- [Phoenix Testing Contexts](https://hexdocs.pm/phoenix/testing_contexts.html)