# Ecto Multi Transaction Recipe

## Introduction

Ecto.Multi provides a way to group multiple database operations into a single transaction. This ensures that either all operations succeed or all fail together, maintaining data consistency. Multi is particularly useful for complex operations that involve multiple tables or when you need to roll back changes if any step fails.

## Basic Multi Transaction

```elixir
defmodule MyApp.Accounts do
  import Ecto.Multi
  alias MyApp.Repo
  alias MyApp.Accounts.{User, Profile}

  def create_user_with_profile(user_attrs, profile_attrs) do
    Multi.new()
    |> Multi.insert(:user, User.changeset(%User{}, user_attrs))
    |> Multi.insert(:profile, fn %{user: user} ->
      profile_attrs = Map.put(profile_attrs, :user_id, user.id)
      Profile.changeset(%Profile{}, profile_attrs)
    end)
    |> Repo.transaction()
  end
end

# Usage:
case MyApp.Accounts.create_user_with_profile(
  %{email: "john@example.com", password: "password123"},
  %{first_name: "John", last_name: "Doe"}
) do
  {:ok, %{user: user, profile: profile}} ->
    # Both user and profile created successfully
    {:ok, user}
    
  {:error, :user, changeset, _changes} ->
    # User creation failed
    {:error, changeset}
    
  {:error, :profile, changeset, _changes} ->
    # Profile creation failed, user creation rolled back
    {:error, changeset}
end
```

## Complex Multi with Conditional Operations

```elixir
defmodule MyApp.Orders do
  import Ecto.Multi
  alias MyApp.Repo
  alias MyApp.{Order, OrderItem, Product, Payment}

  def create_order_with_payment(user_id, items, payment_attrs) do
    Multi.new()
    |> Multi.insert(:order, Order.changeset(%Order{}, %{user_id: user_id, status: :pending}))
    |> Multi.run(:validate_inventory, fn _repo, %{order: order} ->
      validate_inventory(items)
    end)
    |> Multi.run(:create_order_items, fn _repo, %{order: order} ->
      create_order_items(order.id, items)
    end)
    |> Multi.run(:calculate_total, fn _repo, %{create_order_items: order_items} ->
      total = Enum.reduce(order_items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, Decimal.mult(item.price, item.quantity))
      end)
      {:ok, total}
    end)
    |> Multi.update(:finalize_order, fn %{order: order, calculate_total: total} ->
      Order.changeset(order, %{total: total, status: :confirmed})
    end)
    |> Multi.run(:update_inventory, fn _repo, %{create_order_items: order_items} ->
      update_inventory(order_items)
    end)
    |> Multi.run(:process_payment, fn _repo, %{finalize_order: order} ->
      process_payment(order, payment_attrs)
    end)
    |> Multi.run(:send_confirmation, fn _repo, %{finalize_order: order} ->
      send_order_confirmation(order)
    end)
    |> Repo.transaction()
  end

  defp validate_inventory(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case Repo.get(Product, item.product_id) do
        %Product{stock: stock} when stock >= item.quantity ->
          {:cont, {:ok, [item | acc]}}
        %Product{} ->
          {:halt, {:error, "Insufficient stock for product #{item.product_id}"}}
        nil ->
          {:halt, {:error, "Product #{item.product_id} not found"}}
      end
    end)
  end

  defp create_order_items(order_id, items) do
    order_items = Enum.map(items, fn item ->
      product = Repo.get!(Product, item.product_id)
      %OrderItem{
        order_id: order_id,
        product_id: item.product_id,
        quantity: item.quantity,
        price: product.price
      }
    end)

    case Repo.insert_all(OrderItem, order_items, returning: true) do
      {_count, order_items} -> {:ok, order_items}
      error -> error
    end
  end

  defp update_inventory(order_items) do
    Enum.reduce_while(order_items, {:ok, []}, fn item, {:ok, acc} ->
      case Repo.get(Product, item.product_id) do
        %Product{} = product ->
          changeset = Product.changeset(product, %{
            stock: product.stock - item.quantity
          })
          case Repo.update(changeset) do
            {:ok, updated_product} -> {:cont, {:ok, [updated_product | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        nil ->
          {:halt, {:error, "Product not found"}}
      end
    end)
  end

  defp process_payment(order, payment_attrs) do
    payment_attrs = Map.put(payment_attrs, :order_id, order.id)
    changeset = Payment.changeset(%Payment{}, payment_attrs)
    
    case Repo.insert(changeset) do
      {:ok, payment} -> {:ok, payment}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp send_order_confirmation(order) do
    # Send email confirmation (mock implementation)
    # In real app, this might queue a job or send email
    {:ok, "confirmation_sent"}
  end
end
```

## Multi with Rollback Logic

```elixir
defmodule MyApp.Subscriptions do
  import Ecto.Multi
  alias MyApp.Repo
  alias MyApp.{User, Subscription, Payment}

  def upgrade_subscription(user_id, new_plan, payment_method) do
    Multi.new()
    |> Multi.run(:user, fn _repo, _changes ->
      case Repo.get(User, user_id) do
        %User{} = user -> {:ok, user}
        nil -> {:error, :user_not_found}
      end
    end)
    |> Multi.run(:current_subscription, fn _repo, %{user: user} ->
      case Repo.get_by(Subscription, user_id: user.id, active: true) do
        %Subscription{} = subscription -> {:ok, subscription}
        nil -> {:error, :no_active_subscription}
      end
    end)
    |> Multi.run(:validate_upgrade, fn _repo, %{current_subscription: subscription} ->
      if can_upgrade?(subscription, new_plan) do
        {:ok, :valid}
      else
        {:error, :invalid_upgrade}
      end
    end)
    |> Multi.run(:charge_payment, fn _repo, %{current_subscription: subscription} ->
      amount = calculate_upgrade_amount(subscription, new_plan)
      charge_payment_method(payment_method, amount)
    end)
    |> Multi.update(:deactivate_old, fn %{current_subscription: subscription} ->
      Subscription.changeset(subscription, %{active: false, cancelled_at: DateTime.utc_now()})
    end)
    |> Multi.insert(:new_subscription, fn %{user: user} ->
      Subscription.changeset(%Subscription{}, %{
        user_id: user.id,
        plan: new_plan,
        active: true,
        started_at: DateTime.utc_now()
      })
    end)
    |> Multi.run(:update_user_plan, fn _repo, %{user: user, new_subscription: subscription} ->
      changeset = User.changeset(user, %{current_plan: subscription.plan})
      Repo.update(changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, results} ->
        {:ok, results.new_subscription}
      {:error, :charge_payment, payment_error, _changes} ->
        # Payment failed, nothing was committed
        {:error, :payment_failed, payment_error}
      {:error, failed_operation, reason, _changes} ->
        {:error, failed_operation, reason}
    end
  end

  defp can_upgrade?(current_subscription, new_plan) do
    # Business logic to determine if upgrade is valid
    current_subscription.plan != new_plan
  end

  defp calculate_upgrade_amount(current_subscription, new_plan) do
    # Calculate prorated amount for upgrade
    Decimal.new("29.99")
  end

  defp charge_payment_method(payment_method, amount) do
    # Mock payment processing
    case payment_method do
      %{valid: true} -> {:ok, %{transaction_id: "txn_123", amount: amount}}
      _ -> {:error, :payment_declined}
    end
  end
end
```

## Multi with Batch Operations

```elixir
defmodule MyApp.DataImport do
  import Ecto.Multi
  alias MyApp.Repo
  alias MyApp.{User, Product, ImportLog}

  def import_users(users_data) do
    Multi.new()
    |> Multi.insert(:import_log, ImportLog.changeset(%ImportLog{}, %{
      type: "user_import",
      status: "started",
      total_records: length(users_data)
    }))
    |> Multi.run(:validate_users, fn _repo, _changes ->
      validate_users_data(users_data)
    end)
    |> Multi.run(:import_users, fn _repo, %{validate_users: valid_users} ->
      batch_insert_users(valid_users)
    end)
    |> Multi.update(:update_import_log, fn %{import_log: log, import_users: results} ->
      ImportLog.changeset(log, %{
        status: "completed",
        imported_records: length(results),
        errors: []
      })
    end)
    |> Repo.transaction()
  end

  defp validate_users_data(users_data) do
    {valid_users, errors} = 
      users_data
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {user_data, index}, {valid, errors} ->
        changeset = User.changeset(%User{}, user_data)
        if changeset.valid? do
          {[user_data | valid], errors}
        else
          error = %{row: index + 1, errors: changeset.errors}
          {valid, [error | errors]}
        end
      end)

    if errors == [] do
      {:ok, valid_users}
    else
      {:error, errors}
    end
  end

  defp batch_insert_users(users_data) do
    # Insert in batches to avoid overwhelming the database
    batch_size = 1000
    
    users_data
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case Repo.insert_all(User, batch, returning: true) do
        {_count, users} -> {:cont, {:ok, users ++ acc}}
        error -> {:halt, error}
      end
    end)
  end
end
```

## Multi with Nested Transactions

```elixir
defmodule MyApp.Organizations do
  import Ecto.Multi
  alias MyApp.Repo
  alias MyApp.{Organization, User, Membership}

  def create_organization_with_admin(org_attrs, user_attrs) do
    Multi.new()
    |> Multi.insert(:organization, Organization.changeset(%Organization{}, org_attrs))
    |> Multi.merge(fn %{organization: org} ->
      create_admin_user_multi(user_attrs, org.id)
    end)
    |> Multi.run(:setup_defaults, fn _repo, %{organization: org, admin_user: user} ->
      setup_organization_defaults(org, user)
    end)
    |> Repo.transaction()
  end

  defp create_admin_user_multi(user_attrs, org_id) do
    Multi.new()
    |> Multi.insert(:admin_user, User.changeset(%User{}, user_attrs))
    |> Multi.insert(:admin_membership, fn %{admin_user: user} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: org_id,
        role: "admin"
      })
    end)
  end

  defp setup_organization_defaults(org, admin_user) do
    # Set up default organization settings, permissions, etc.
    # This could be another Multi if needed
    {:ok, %{organization: org, admin: admin_user}}
  end
end
```

## Error Handling Patterns

```elixir
defmodule MyApp.TransactionHelpers do
  def handle_transaction_result(result) do
    case result do
      {:ok, changes} ->
        {:ok, changes}
        
      {:error, failed_operation, failed_value, changes_so_far} ->
        # Log the failure context
        Logger.error("""
        Transaction failed at step: #{failed_operation}
        Error: #{inspect(failed_value)}
        Completed steps: #{inspect(Map.keys(changes_so_far))}
        """)
        
        # Return structured error
        {:error, failed_operation, failed_value}
    end
  end

  def rollback_with_reason(reason) do
    Repo.rollback({:custom_error, reason})
  end
end

# Usage in Multi:
defmodule MyApp.ComplexOperation do
  def perform_operation(data) do
    Multi.new()
    |> Multi.run(:step1, fn _repo, _changes ->
      case perform_step1(data) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> 
          MyApp.TransactionHelpers.rollback_with_reason(reason)
      end
    end)
    |> Multi.run(:step2, &perform_step2/2)
    |> Repo.transaction()
    |> MyApp.TransactionHelpers.handle_transaction_result()
  end
end
```

## Tips & Best Practices

### Multi Organization
- Use descriptive names for Multi operations (`:create_user`, `:validate_inventory`)
- Group related operations logically
- Use `Multi.merge/2` to combine separate Multi operations

### Error Handling
- Always pattern match on Multi results to handle different failure points
- Use `Multi.run/3` for complex operations that might fail
- Consider using custom error types for better error handling

### Performance
- Use `insert_all/3` for bulk operations instead of multiple inserts
- Consider batch processing for large datasets
- Use `returning: true` when you need the inserted/updated data

### Testing
- Test both success and failure scenarios
- Use database sandbox for test isolation
- Test partial failures to ensure proper rollback

### Database Constraints
- Let the database handle data integrity constraints
- Use `foreign_key_constraint/3` and `unique_constraint/3` in changesets
- Handle constraint violations gracefully in Multi operations

## References

- [Ecto.Multi Documentation](https://hexdocs.pm/ecto/Ecto.Multi.html)
- [Ecto Transactions Guide](https://hexdocs.pm/ecto/transactions.html)
- [Phoenix Context Transactions](https://hexdocs.pm/phoenix/contexts.html#transactions)
- [Ecto.Repo.transaction Documentation](https://hexdocs.pm/ecto/Ecto.Repo.html#c:transaction/2)