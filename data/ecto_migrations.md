# Ecto Migrations Recipe

## Prerequisites & Related Recipes

### Prerequisites
- Understanding of database concepts (tables, indexes, constraints)
- Basic knowledge of Ecto schemas and their field types
- Familiarity with SQL DDL (Data Definition Language)

### Related Recipes
- **Foundation**: [Ecto Schema Basics](../data/ecto_schema_basics.md) - Designing schemas that require database structure
- **Performance**: [Database Performance](../data/database_performance.md) - Migration strategies for optimal database performance

## Introduction

Migrations are Ecto's way of managing database schema changes over time. They provide a version-controlled approach to modifying your database structure, ensuring that all environments can be brought to the same state. Each migration is a module that defines how to apply and rollback database changes.

## Basic Migration Structure

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :age, :integer
      add :active, :boolean, default: true
      add :bio, :text
      add :settings, :map
      add :tags, {:array, :string}

      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:name])
  end
end
```

## Migration with Up/Down Functions

```elixir
defmodule MyApp.Repo.Migrations.AddUserRoles do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :role, :string, default: "user"
    end

    create constraint(:users, :valid_role, 
      check: "role IN ('user', 'admin', 'moderator')")
    
    # Data migration
    execute("UPDATE users SET role = 'user' WHERE role IS NULL")
  end

  def down do
    alter table(:users) do
      remove :role
    end
    
    drop constraint(:users, :valid_role)
  end
end
```

## Complex Migration with Relationships

```elixir
defmodule MyApp.Repo.Migrations.CreatePostsAndComments do
  use Ecto.Migration

  def change do
    # Create posts table
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :content, :text
      add :status, :string, default: "draft"
      add :published_at, :naive_datetime
      add :view_count, :integer, default: 0
      add :author_id, references(:users, on_delete: :restrict), null: false

      timestamps()
    end

    # Create comments table
    create table(:comments) do
      add :content, :text, null: false
      add :approved, :boolean, default: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    # Create indexes
    create index(:posts, [:author_id])
    create index(:posts, [:status])
    create index(:posts, [:published_at])
    create index(:comments, [:post_id])
    create index(:comments, [:author_id])
    create index(:comments, [:approved])

    # Add constraints
    create constraint(:posts, :valid_status,
      check: "status IN ('draft', 'published', 'archived')")
    
    create constraint(:posts, :published_at_when_published,
      check: "NOT (status = 'published' AND published_at IS NULL)")
  end
end
```

## Data Migration

```elixir
defmodule MyApp.Repo.Migrations.MigrateUserProfiles do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Create new profiles table
    create table(:profiles) do
      add :first_name, :string
      add :last_name, :string
      add :bio, :text
      add :avatar_url, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:profiles, [:user_id])

    # Migrate existing data
    flush()

    # Import schemas for data migration
    Code.eval_string("""
      defmodule User do
        use Ecto.Schema
        schema "users" do
          field :name, :string
          field :bio, :string
        end
      end

      defmodule Profile do
        use Ecto.Schema
        schema "profiles" do
          field :first_name, :string
          field :last_name, :string
          field :bio, :string
          field :user_id, :integer
          timestamps()
        end
      end
    """)

    # Migrate data
    users = MyApp.Repo.all(User)
    
    for user <- users do
      names = String.split(user.name, " ", parts: 2)
      first_name = Enum.at(names, 0)
      last_name = Enum.at(names, 1)

      %Profile{}
      |> Profile.changeset(%{
        first_name: first_name,
        last_name: last_name,
        bio: user.bio,
        user_id: user.id
      })
      |> MyApp.Repo.insert!()
    end

    # Remove old columns
    alter table(:users) do
      remove :bio
    end
  end

  def down do
    alter table(:users) do
      add :bio, :text
    end

    flush()

    # Migrate data back
    profiles = MyApp.Repo.all(Profile)
    
    for profile <- profiles do
      user = MyApp.Repo.get!(User, profile.user_id)
      
      MyApp.Repo.update!(
        Ecto.Changeset.change(user, bio: profile.bio)
      )
    end

    drop table(:profiles)
  end
end
```

## Migration with Custom SQL

```elixir
defmodule MyApp.Repo.Migrations.AddFullTextSearch do
  use Ecto.Migration

  def up do
    # Add PostgreSQL specific features
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    
    # Add full text search column
    alter table(:posts) do
      add :search_vector, :tsvector
    end

    # Create GIN index for full text search
    execute("""
      CREATE INDEX posts_search_vector_idx ON posts 
      USING GIN (search_vector)
    """)

    # Create trigger to update search vector
    execute("""
      CREATE OR REPLACE FUNCTION update_posts_search_vector()
      RETURNS trigger AS $$
      BEGIN
        NEW.search_vector := to_tsvector('english', 
          COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, ''));
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    """)

    execute("""
      CREATE TRIGGER posts_search_vector_trigger
      BEFORE INSERT OR UPDATE ON posts
      FOR EACH ROW EXECUTE FUNCTION update_posts_search_vector();
    """)

    # Update existing records
    execute("""
      UPDATE posts SET search_vector = to_tsvector('english', 
        COALESCE(title, '') || ' ' || COALESCE(content, ''))
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS posts_search_vector_trigger ON posts")
    execute("DROP FUNCTION IF EXISTS update_posts_search_vector()")
    execute("DROP INDEX IF EXISTS posts_search_vector_idx")
    
    alter table(:posts) do
      remove :search_vector
    end
  end
end
```

## Migration with Enum Types

```elixir
defmodule MyApp.Repo.Migrations.CreateOrdersWithEnums do
  use Ecto.Migration

  def up do
    # Create custom enum types (PostgreSQL)
    execute("CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled')")
    execute("CREATE TYPE payment_method AS ENUM ('credit_card', 'paypal', 'stripe', 'bank_transfer')")

    create table(:orders) do
      add :total, :decimal, precision: 10, scale: 2, null: false
      add :status, :order_status, null: false, default: "pending"
      add :payment_method, :payment_method
      add :user_id, references(:users, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:orders, [:status])
    create index(:orders, [:user_id])
  end

  def down do
    drop table(:orders)
    execute("DROP TYPE order_status")
    execute("DROP TYPE payment_method")
  end
end
```

## Migration for Partitioned Tables

```elixir
defmodule MyApp.Repo.Migrations.CreatePartitionedEvents do
  use Ecto.Migration

  def up do
    # Create partitioned table by date
    execute("""
      CREATE TABLE events (
        id BIGSERIAL,
        event_type VARCHAR(50) NOT NULL,
        user_id INTEGER REFERENCES users(id),
        metadata JSONB,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      ) PARTITION BY RANGE (created_at)
    """)

    # Create partitions for current and next month
    current_month = Date.utc_today() |> Date.beginning_of_month()
    next_month = Date.add(current_month, 32) |> Date.beginning_of_month()
    
    execute("""
      CREATE TABLE events_#{Date.to_string(current_month) |> String.replace("-", "_")} 
      PARTITION OF events
      FOR VALUES FROM ('#{current_month}') TO ('#{next_month}')
    """)

    # Create indexes on partitioned table
    execute("CREATE INDEX events_user_id_idx ON events (user_id)")
    execute("CREATE INDEX events_event_type_idx ON events (event_type)")
    execute("CREATE INDEX events_created_at_idx ON events (created_at)")
  end

  def down do
    execute("DROP TABLE events")
  end
end
```

## Rollback-Safe Migration

```elixir
defmodule MyApp.Repo.Migrations.SafeColumnAddition do
  use Ecto.Migration

  def up do
    # Add column as nullable first
    alter table(:users) do
      add :phone_number, :string
    end

    # Add index
    create index(:users, [:phone_number])

    # Add constraint after data is migrated
    create constraint(:users, :valid_phone_format,
      check: "phone_number ~ '^\\+?[0-9\\s\\-\\(\\)]+$'")
  end

  def down do
    alter table(:users) do
      remove :phone_number
    end
  end
end
```

## Migration Testing

```elixir
defmodule MyApp.Repo.Migrations.TestableDataMigration do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :title, :string, null: false
      add :message, :text
      add :read, :boolean, default: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:read])
  end

  # Helper function for testing
  def create_sample_data do
    if Code.ensure_loaded?(MyApp.Repo) do
      users = MyApp.Repo.all(MyApp.User)
      
      for user <- Enum.take(users, 3) do
        MyApp.Repo.insert!(%MyApp.Notification{
          title: "Welcome!",
          message: "Welcome to our platform",
          user_id: user.id
        })
      end
    end
  end
end
```

## Tips & Best Practices

### Migration Safety
- Always test migrations on a copy of production data
- Use `change/0` when possible for automatic reversibility
- Use `up/0` and `down/0` for complex migrations that need custom rollback logic
- Add constraints gradually: first add nullable columns, migrate data, then add constraints

### Performance Considerations
- Create indexes concurrently in production: `create index(:table, [:column], concurrently: true)`
- Use `ALTER TABLE ... ADD COLUMN ... DEFAULT ...` carefully on large tables
- Consider using `execute/1` for complex operations that might time out

### Data Integrity
- Always add foreign key constraints with appropriate `on_delete` options
- Use database constraints to enforce business rules
- Test both forward and backward migrations thoroughly

### Naming Conventions
- Use descriptive migration names: `AddIndexToUsersEmail` instead of `AddIndex`
- Include the operation type in the name: `CreateUsers`, `AddRoleToUsers`, `RemoveDeprecatedColumns`
- Use consistent naming for similar operations

### Production Deployment
- Plan for zero-downtime deployments
- Consider migration timing and locking behavior
- Use feature flags for schema changes that affect application code
- Monitor migration performance and rollback plans

## References

- [Ecto Migrations Documentation](https://hexdocs.pm/ecto/Ecto.Migration.html)
- [Phoenix Ecto Guide](https://hexdocs.pm/phoenix/ecto.html)
- [PostgreSQL Migration Best Practices](https://www.postgresql.org/docs/current/ddl-alter.html)
- [Ecto.Migrator Documentation](https://hexdocs.pm/ecto/Ecto.Migrator.html)