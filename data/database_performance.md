# Database Performance Recipe

## Prerequisites & Related Recipes

### Prerequisites
- Understanding of Ecto schemas and basic querying
- Familiarity with Phoenix contexts pattern
- Basic knowledge of database concepts (indexes, joins, aggregations)

### Related Recipes
- **Foundation**: [Ecto Schema Basics](../data/ecto_schema_basics.md) - Understanding schema structure for optimization
- **Business Logic**: [Phoenix Contexts](../core/phoenix_contexts.md) - Implementing optimized queries within contexts
- **Testing**: [Comprehensive Testing Guide](../testing/comprehensive_testing_guide.md) - Testing query performance and behavior

## Introduction

Database performance directly impacts user experience and application scalability. This recipe covers when and how to optimize database interactions in Phoenix applications, focusing on query optimization, preloading strategies, N+1 prevention, and connection management.

## When to Optimize Database Performance

**Optimize early when:**
- Building data-intensive applications
- Expecting high traffic from launch
- Working with complex data relationships

**Optimize reactively when:**
- Experiencing slow page loads
- Database CPU/memory usage is high
- Users complain about response times

**Don't optimize when:**
- Building MVPs with simple data needs
- Premature optimization without measurements
- Traffic is low and performance is adequate

## Query Optimization Fundamentals

The key to fast queries is selecting only what you need and using the database efficiently. Ecto makes this straightforward with its composable query syntax.

```elixir
defmodule MyApp.Blog do
  import Ecto.Query
  alias MyApp.Repo

  # ❌ Don't: Load full records when you only need fields
  def list_post_titles_bad do
    Repo.all(Post) |> Enum.map(& &1.title)
  end

  # ✅ Do: Use select to limit returned fields
  def list_post_titles do
    from(p in Post,
      select: %{id: p.id, title: p.title},
      where: p.published == true,
      order_by: [desc: p.published_at]
    )
    |> Repo.all()
  end

  # ✅ Do: Use joins instead of separate queries
  def posts_with_comment_counts do
    from(p in Post,
      left_join: c in assoc(p, :comments),
      where: p.published == true,
      group_by: p.id,
      select: %{
        id: p.id,
        title: p.title,
        comment_count: count(c.id)
      }
    )
    |> Repo.all()
  end
end
```

**Why this works:** Using `select` reduces memory usage and network transfer. Joins in a single query are much faster than N separate queries. The database can optimize joined queries efficiently.

**When to use:** Always prefer `select` when you don't need full structs. Use joins when you need related data in the same operation.

## Strategic Preloading

Preloading solves N+1 queries by loading related data in batches. The key is loading only what you need, when you need it.

```elixir
defmodule MyApp.Blog do
  # ❌ Don't: This creates N+1 queries
  def list_posts_with_authors_bad do
    posts = Repo.all(Post)
    Enum.map(posts, fn post ->
      %{post | author: Repo.get!(User, post.author_id)}
    end)
  end

  # ✅ Do: Preload related data
  def list_posts_with_authors do
    from(p in Post, preload: [:author])
    |> Repo.all()
  end

  # ✅ Do: Conditional preloading for different use cases
  def list_posts(include_comments: include_comments?) do
    query = from p in Post, order_by: [desc: p.published_at]
    
    if include_comments? do
      from q in query, preload: [comments: [:author]]
    else
      query
    end
    |> Repo.all()
  end

  # ✅ Do: Custom queries for preloading
  def get_post_with_recent_comments!(id) do
    recent_comments_query = 
      from c in Comment,
        order_by: [desc: c.inserted_at],
        limit: 5,
        preload: [:author]

    Repo.get!(Post, id)
    |> Repo.preload([comments: recent_comments_query])
  end
end
```

**Why this works:** Preloading uses IN queries to load related data in batches, typically 1-2 queries instead of N+1. Custom preload queries let you control exactly what related data is loaded.

**When to use:** When you know you'll need related data. Don't preload data you won't use - it wastes memory and network bandwidth.

## N+1 Query Prevention

N+1 queries are a common performance killer. One query loads a list, then N additional queries load related data for each item.

```elixir
# ❌ This causes N+1 queries
def show_user_posts(user_id) do
  posts = Blog.get_posts_by_user(user_id)
  
  # This loads comments for each post individually!
  Enum.map(posts, fn post ->
    comments = Blog.get_comments_for_post(post.id)
    %{post | comments: comments}
  end)
end

# ✅ Load everything efficiently
def show_user_posts(user_id) do
  from(p in Post,
    where: p.user_id == ^user_id,
    preload: [comments: [:author]]
  )
  |> Repo.all()
end

# ✅ Even better: Use joins when you need aggregates
def show_user_posts_with_counts(user_id) do
  from(p in Post,
    left_join: c in assoc(p, :comments),
    where: p.user_id == ^user_id,
    group_by: p.id,
    select: %{
      post: p,
      comment_count: count(c.id)
    }
  )
  |> Repo.all()
end
```

**Why this works:** Instead of N+1 queries (1 + N), you get 1-2 queries total. The database is much more efficient at handling one large operation than many small ones.

**When to use:** Always be suspicious when you see `Enum.map` over database results that triggers more queries inside the map function.

## Connection Pooling and Management

Phoenix uses connection pooling to efficiently manage database connections. Proper configuration prevents connection exhaustion and optimizes resource usage.

```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  pool_size: 20,                    # Number of connections in pool
  queue_target: 50,                 # Target time for checkout (ms)
  queue_interval: 1000,             # Interval to check queue times
  timeout: 15_000,                  # Query timeout (15 seconds)
  ownership_timeout: 300_000        # How long pool waits for ownership
```

**Why this works:** The pool maintains ready connections, avoiding the overhead of establishing connections for each query. Timeouts prevent hung queries from blocking the pool.

**When to tune:** When you see connection timeout errors, slow response times during peak traffic, or database connection limits being reached.

## Index Strategy

Database indexes dramatically speed up queries but slow down writes. The key is indexing the right columns for your query patterns.

```elixir
# In a migration
defmodule MyApp.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Compound index for common query patterns
    create index(:posts, [:author_id, :published_at])
    
    # Partial index for published posts only
    create index(:posts, [:published_at], where: "published = true")
    
    # Text search index (PostgreSQL)
    create index(:posts, [:title], using: :gin, prefix: :gin_trgm_ops)
  end
end

# Query that benefits from the compound index
def list_posts_by_author(author_id) do
  from(p in Post,
    where: p.author_id == ^author_id and p.published == true,
    order_by: [desc: p.published_at]
  )
  |> Repo.all()
end
```

**Why this works:** Compound indexes match multiple WHERE conditions in one lookup. Partial indexes save space by only indexing relevant rows. The query planner uses these indexes automatically when they match your query patterns.

**When to add indexes:** After profiling slow queries, before they become performance problems in production. Don't over-index - each index adds write overhead.

## Query Composition for Reusability

Building reusable query components keeps your code DRY and makes optimization easier.

```elixir
defmodule MyApp.Blog.PostQueries do
  import Ecto.Query
  alias MyApp.Blog.Post

  def base_query, do: from p in Post, as: :post

  def published(query \\ base_query()) do
    from [post: p] in query, where: p.published == true
  end

  def by_author(query \\ base_query(), author_id) do
    from [post: p] in query, where: p.author_id == ^author_id
  end

  def recent_first(query \\ base_query()) do
    from [post: p] in query, order_by: [desc: p.published_at]
  end

  def with_comment_count(query \\ base_query()) do
    from [post: p] in query,
      left_join: c in assoc(p, :comments),
      group_by: p.id,
      select_merge: %{comment_count: count(c.id)}
  end

  # Compose complex queries from simple building blocks
  def recent_published_posts_by_author(author_id, limit \\ 10) do
    base_query()
    |> published()
    |> by_author(author_id)
    |> recent_first()
    |> limit(^limit)
  end
end
```

**Why this works:** Query composition lets you build complex queries from tested, optimized components. You can optimize individual query functions without affecting all the places they're used.

**When to use:** When you have common query patterns used across multiple contexts. This approach scales well as your application grows.

## Read Replicas for Scale

As your application grows, you can separate read and write operations to different database instances.

```elixir
# config/config.exs
config :my_app, MyApp.Repo,
  url: System.get_env("DATABASE_URL")  # Primary database

config :my_app, MyApp.ReadRepo,
  url: System.get_env("READ_DATABASE_URL"),  # Read replica
  pool_size: 15

# Usage in contexts
defmodule MyApp.Blog do
  alias MyApp.{Repo, ReadRepo}

  # Writes go to primary
  def create_post(attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  # Reads can use replica
  def list_published_posts do
    from(p in Post, where: p.published == true)
    |> ReadRepo.all()
  end

  # Fresh data needed after writes
  def get_fresh_post!(id) do
    Repo.get!(Post, id)  # Use primary for fresh data
  end
end
```

**Why this works:** Read replicas handle the majority of database load (usually 80%+ reads). The primary database focuses on writes and consistency-critical reads.

**When to use:** When your database becomes a bottleneck, you have geographically distributed users, or you need to separate analytical queries from transactional ones.

## Common Performance Pitfalls

**Loading Too Much Data**
Always use `select` when you don't need full structs. Loading 100 full Post records when you only need titles wastes memory and bandwidth.

**Missing Preloads**
If you see many individual `Repo.get` calls in your logs, you probably have N+1 queries. Use preloading or joins instead.

**Over-Preloading**
Don't preload associations you won't use. Each preload adds memory usage and query complexity.

**Ignoring Database Logs**
Enable query logging in development to catch N+1 queries and slow operations early.

## Performance Monitoring

Set up monitoring to catch performance issues before they impact users.

```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  log: false,  # Use telemetry instead of logs in production
  telemetry_prefix: [:my_app, :repo]

# Set up telemetry to track slow queries
:telemetry.attach(
  "slow-query-logger",
  [:my_app, :repo, :query],
  &MyApp.SlowQueryLogger.handle_event/4,
  nil
)
```

**Why this works:** Telemetry gives you detailed metrics without the overhead of string-based logging. You can send these metrics to monitoring systems for alerting and analysis.

**When to use:** Always in production. Consider adding query time thresholds that trigger alerts when exceeded.

## Decision Criteria

**Optimize queries when:**
- Individual queries take > 100ms
- Pages load slowly due to database time
- Database CPU/memory usage is consistently high

**Add indexes when:**
- Queries scan large tables without indexes
- You have consistent query patterns
- Read performance matters more than write performance

**Use preloading when:**
- You always need related data
- You're seeing N+1 query patterns
- Related data fits comfortably in memory

**Consider read replicas when:**
- Database is a bottleneck despite optimization
- You have geographically distributed users
- You need to run heavy analytical queries

## References

- [Ecto Query Documentation](https://hexdocs.pm/ecto/Ecto.Query.html)
- [PostgreSQL Performance Tips](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [Phoenix Telemetry Guide](https://hexdocs.pm/phoenix/telemetry.html)
- [Database Performance Best Practices](https://use-the-index-luke.com/)