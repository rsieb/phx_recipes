# Ecto Schema Basics Recipe

---
Phoenix Version: 1.7+
Complexity: Beginner
Time to Implement: 30 minutes
Prerequisites: Basic Elixir structs and modules, database concepts, data validation basics
---

## Prerequisites & Related Recipes

### Prerequisites
- Basic understanding of Elixir structs and modules
- Familiarity with database concepts (tables, columns, relationships)
- Knowledge of data validation concepts

### Related Recipes
- **Business Logic**: [Phoenix Contexts](../core/phoenix_contexts.md) - Using schemas within contexts for business operations
- **Web Layer**: [Phoenix LiveView Basics](../components/phoenix_liveview_basics.md) - Using schemas and changesets in LiveView forms
- **Testing**: [Comprehensive Testing Guide](../testing/comprehensive_testing_guide.md) - Testing schema validations and changeset functions
- **Advanced Data**: [Ecto Advanced Patterns](../data/ecto_advanced_patterns.md) - Complex queries and relationships
- **Performance**: [Database Performance](../data/database_performance.md) - Schema optimization techniques
- **Migrations**: [Ecto Migrations Guide](../data/ecto_migrations_guide.md) - Creating database structure for schemas

## Introduction

Ecto schemas define the structure of your database tables and provide a mapping between Elixir structs and database records. They serve as the foundation for all database operations in Phoenix applications, defining fields, types, relationships, and validation rules.

## Basic Schema Example

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  # Define the schema with table name and primary key
  schema "users" do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :active, :boolean, default: true
    field :bio, :string
    field :inserted_at, :naive_datetime
    field :updated_at, :naive_datetime

    # Relationships
    has_many :posts, MyApp.Blog.Post
    belongs_to :organization, MyApp.Accounts.Organization

    # Auto-managed timestamps
    timestamps()
  end

  # Changeset function for data validation
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :age, :active, :bio])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_number(:age, greater_than: 0)
    |> unique_constraint(:email)
  end
end
```

## Schema with Custom Primary Key

```elixir
defmodule MyApp.Inventory.Product do
  use Ecto.Schema
  import Ecto.Changeset

  # Custom primary key with different type
  @primary_key {:sku, :string, autogenerate: false}
  @foreign_key_type :string

  schema "products" do
    field :name, :string
    field :price, :decimal
    field :description, :string
    field :in_stock, :boolean, default: true
    
    # JSON field for flexible data
    field :metadata, :map
    
    # Virtual field (not stored in database)
    field :calculated_tax, :decimal, virtual: true

    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:sku, :name, :price, :description, :in_stock, :metadata])
    |> validate_required([:sku, :name, :price])
    |> validate_number(:price, greater_than: 0)
    |> put_calculated_tax()
  end

  defp put_calculated_tax(changeset) do
    case get_field(changeset, :price) do
      nil -> changeset
      price -> put_change(changeset, :calculated_tax, Decimal.mult(price, "0.08"))
    end
  end
end
```

## Schema Field Types

```elixir
defmodule MyApp.Examples.FieldTypes do
  use Ecto.Schema

  schema "field_examples" do
    # String types
    field :name, :string
    field :slug, :string, size: 100
    field :description, :text
    
    # Numeric types
    field :age, :integer
    field :score, :float
    field :price, :decimal
    
    # Boolean and binary
    field :active, :boolean
    field :avatar, :binary
    
    # Date and time
    field :birth_date, :date
    field :login_time, :time
    field :last_seen, :naive_datetime
    field :published_at, :utc_datetime
    
    # Collections and special types
    field :tags, {:array, :string}
    field :settings, :map
    field :config, {:map, :string}
    field :uuid, :binary_id
    
    # Enum field
    field :status, Ecto.Enum, values: [:pending, :active, :inactive]

    timestamps()
  end
end
```

## Tips & Best Practices

### Schema Organization
- Place schemas in context modules (e.g., `MyApp.Accounts.User`)
- Use descriptive table names that match your schema module
- Keep related schemas in the same context directory

### Field Definitions
- Always specify field types explicitly
- Use `:decimal` for monetary values, not `:float`
- Add defaults for boolean fields to avoid nil values
- Use `:binary_id` for UUIDs and foreign keys when using UUID primary keys

### Validation
- Keep changeset functions focused on a single purpose
- Use `validate_required/2` for mandatory fields
- Add database constraints with `unique_constraint/2`, `foreign_key_constraint/2`
- Virtual fields are useful for computed values that don't need persistence

### Performance Considerations
- Add database indexes for frequently queried fields
- Use `select/3` to load only needed fields for large datasets
- Consider using `Ecto.Enum` for status fields instead of strings

## References

- [Ecto Schema Documentation](https://hexdocs.pm/ecto/Ecto.Schema.html)
- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [Ecto Types Documentation](https://hexdocs.pm/ecto/Ecto.Type.html)
- [Ecto Changeset Documentation](https://hexdocs.pm/ecto/Ecto.Changeset.html)