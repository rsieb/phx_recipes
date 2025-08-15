# Database Performance Recipe

## Introduction

Database performance is critical for Phoenix applications. This recipe covers comprehensive patterns for optimizing database interactions using Ecto, including query optimization, preloading strategies, N+1 query prevention, index usage, connection pooling, and read replica configurations following Phoenix best practices.

## Query Optimization with Ecto

### Efficient Query Patterns

```elixir
defmodule MyApp.Blog do
  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Blog.{Post, Comment, Tag}

  # Use select to limit returned fields
  def list_post_summaries do
    from(p in Post,
      select: %{id: p.id, title: p.title, published_at: p.published_at},
      where: p.published == true,
      order_by: [desc: p.published_at]
    )
    |> Repo.all()
  end

  # Use joins instead of separate queries
  def posts_with_comment_counts do
    from(p in Post,
      left_join: c in assoc(p, :comments),
      where: p.published == true,
      group_by: p.id,
      select: %{
        id: p.id,
        title: p.title,
        content: p.content,
        comment_count: count(c.id)
      }
    )
    |> Repo.all()
  end

  # Use exists? for conditional queries
  def posts_with_comments do
    from(p in Post,
      where: exists(from c in Comment, where: c.post_id == p.id)
    )
    |> Repo.all()
  end

  # Use window functions for pagination with counts
  def paginated_posts_with_total(page, per_page) do
    offset = (page - 1) * per_page

    query = from(p in Post,
      select: %{
        post: p,
        total_count: over(count(), :posts_partition)
      },
      windows: [posts_partition: [partition_by: 1]],
      order_by: [desc: p.inserted_at],
      limit: ^per_page,
      offset: ^offset
    )

    case Repo.all(query) do
      [] -> {[], 0}
      results ->
        posts = Enum.map(results, & &1.post)
        total = List.first(results).total_count
        {posts, total}
    end
  end

  # Batch queries for multiple IDs
  def get_posts_by_ids(ids) when is_list(ids) do
    from(p in Post, where: p.id in ^ids)
    |> Repo.all()
    |> Enum.into(%{}, &{&1.id, &1})
  end

  # Use fragments for complex database functions
  def search_posts(term) do
    search_term = "%#{term}%"
    
    from(p in Post,
      where: fragment("? @@ to_tsquery(?)", p.search_vector, ^term),
      # Fallback to ILIKE for partial matches
      or_where: ilike(p.title, ^search_term) or ilike(p.content, ^search_term),
      order_by: [
        desc: fragment("ts_rank(?, to_tsquery(?))", p.search_vector, ^term),
        desc: p.published_at
      ]
    )
    |> Repo.all()
  end
end
```

### Query Composition and Reusability

```elixir
defmodule MyApp.Blog.PostQueries do
  import Ecto.Query
  alias MyApp.Blog.Post

  def base_query do
    from p in Post, as: :post
  end

  def published(query \\ base_query()) do
    from [post: p] in query,
      where: p.published == true
  end

  def by_author(query \\ base_query(), author_id) do
    from [post: p] in query,
      where: p.author_id == ^author_id
  end

  def by_tag(query \\ base_query(), tag_name) do
    from [post: p] in query,
      join: t in assoc(p, :tags),
      where: t.name == ^tag_name
  end

  def recent_first(query \\ base_query()) do
    from [post: p] in query,
      order_by: [desc: p.published_at]
  end

  def with_comment_count(query \\ base_query()) do
    from [post: p] in query,
      left_join: c in assoc(p, :comments),
      group_by: p.id,
      select_merge: %{comment_count: count(c.id)}
  end

  def limit_to(query \\ base_query(), limit) do
    from q in query, limit: ^limit
  end

  # Usage examples
  def recent_published_posts_by_author(author_id, limit \\ 10) do
    base_query()
    |> published()
    |> by_author(author_id)
    |> recent_first()
    |> limit_to(limit)
  end

  def popular_posts_with_comments do
    base_query()
    |> published()
    |> with_comment_count()
    |> recent_first()
  end
end
```

## Preloading Strategies

### Strategic Preloading Patterns

```elixir
defmodule MyApp.Blog do
  import Ecto.Query
  alias MyApp.Repo

  # Basic preloading
  def get_post_with_author!(id) do
    Repo.get!(Post, id)
    |> Repo.preload(:author)
  end

  # Nested preloading
  def get_post_with_comments_and_authors!(id) do
    Repo.get!(Post, id)
    |> Repo.preload([comments: :author])
  end

  # Selective preloading with custom queries
  def get_post_with_recent_comments!(id) do
    recent_comments_query = 
      from c in Comment,
        order_by: [desc: c.inserted_at],
        limit: 5,
        preload: [:author]

    Repo.get!(Post, id)
    |> Repo.preload([comments: recent_comments_query])
  end

  # Conditional preloading
  def list_posts(preload_associations \\ []) do
    Post
    |> Repo.all()
    |> Repo.preload(preload_associations)
  end

  # Preloading with custom select
  def get_post_with_author_summary!(id) do
    author_query = 
      from a in MyApp.Accounts.User,
        select: %{id: a.id, name: a.name, email: a.email}

    Repo.get!(Post, id)
    |> Repo.preload([author: author_query])
  end

  # Batch preloading for multiple records
  def preload_posts_associations(posts) do
    posts
    |> Repo.preload([
      :author,
      :tags,
      comments: [:author]
    ])
  end

  # Lazy preloading with custom function
  def maybe_preload_comments(post, include_comments? \\ false) do
    if include_comments? do
      Repo.preload(post, [comments: [:author]])
    else
      post
    end
  end
end
```

### Advanced Preloading with DataLoader

```elixir
defmodule MyApp.DataLoader do
  def source do
    Dataloader.Ecto.new(MyApp.Repo, query: &query/2)
  end

  def query(Comment, %{scope: :with_author}) do
    from c in Comment, preload: [:author]
  end

  def query(Post, %{scope: :published}) do
    from p in Post, where: p.published == true
  end

  def query(queryable, _params) do
    queryable
  end
end

# Usage in context
defmodule MyApp.Blog do
  def list_posts_with_efficient_loading do
    posts = Repo.all(Post)
    
    loader = 
      Dataloader.new()
      |> Dataloader.add_source(:blog, MyApp.DataLoader.source())

    # Batch load comments for all posts
    loader = 
      Enum.reduce(posts, loader, fn post, acc ->
        Dataloader.load(acc, :blog, {Comment, %{scope: :with_author}}, post.id)
      end)

    loader = Dataloader.run(loader)

    # Attach loaded data
    Enum.map(posts, fn post ->
      comments = Dataloader.get(loader, :blog, {Comment, %{scope: :with_author}}, post.id)
      %{post | comments: comments}
    end)
  end
end
```

## N+1 Query Prevention

### Identifying and Fixing N+1 Queries

```elixir
# BAD: N+1 Query Pattern
defmodule MyApp.BlogBad do
  def list_posts_with_author_names do
    posts = Repo.all(Post)
    
    # This will execute one query per post!
    Enum.map(posts, fn post ->
      author = Repo.get!(User, post.author_id)
      %{title: post.title, author_name: author.name}
    end)
  end
end

# GOOD: Fixed with preloading
defmodule MyApp.Blog do
  def list_posts_with_author_names do
    from(p in Post, preload: [:author])
    |> Repo.all()
    |> Enum.map(fn post ->
      %{title: post.title, author_name: post.author.name}
    end)
  end

  # EVEN BETTER: Use join and select
  def list_posts_with_author_names_optimized do
    from(p in Post,
      join: a in assoc(p, :author),
      select: %{title: p.title, author_name: a.name}
    )
    |> Repo.all()
  end
end
```

### N+1 Detection Middleware

```elixir
defmodule MyApp.QueryLogger do
  require Logger

  def log_query(query, measurements, metadata, _config) do
    if Application.get_env(:my_app, :log_queries, false) do
      Logger.info("Query: #{query} - #{measurements.total_time}μs")
    end
  end

  def warn_on_many_queries do
    Process.put(:query_count, 0)
    
    :telemetry.attach(
      "query-counter",
      [:my_app, :repo, :query],
      &count_queries/4,
      nil
    )
  end

  defp count_queries(_event, _measurements, _metadata, _config) do
    count = Process.get(:query_count, 0) + 1
    Process.put(:query_count, count)
    
    if count > 10 do
      Logger.warn("High query count detected: #{count} queries")
    end
  end
end
```

## Index Usage and Analysis

### Strategic Index Creation

```elixir
# Migration with performance indexes
defmodule MyApp.Repo.Migrations.CreatePerformanceIndexes do
  use Ecto.Migration

  def change do
    # Compound index for common query patterns
    create index(:posts, [:author_id, :published_at])
    
    # Partial index for published posts only
    create index(:posts, [:published_at], where: "published = true")
    
    # Unique compound index
    create unique_index(:user_roles, [:user_id, :role_id])
    
    # Text search index (PostgreSQL)
    create index(:posts, [:title], using: :gin, prefix: :gin_trgm_ops)
    
    # Full-text search
    execute "CREATE INDEX posts_search_idx ON posts USING gin(to_tsvector('english', title || ' ' || content))"
    
    # Covering index (includes additional columns)
    create index(:posts, [:author_id], include: [:title, :published_at])
    
    # Expression index
    create index(:users, ["lower(email)"], unique: true)
  end
end
```

### Query Analysis Tools

```elixir
defmodule MyApp.QueryAnalyzer do
  alias MyApp.Repo

  def explain_query(query) do
    explained = Ecto.Adapters.SQL.explain(Repo, :all, query, analyze: true, buffers: true)
    IO.puts(explained)
    explained
  end

  def analyze_slow_queries do
    # Enable query logging
    Ecto.Adapters.SQL.query!(
      Repo,
      "SET log_min_duration_statement = 100",
      []
    )
  end

  def find_missing_indexes do
    query = """
    SELECT 
      schemaname,
      tablename,
      attname,
      n_distinct,
      correlation
    FROM pg_stats
    WHERE schemaname = 'public'
      AND n_distinct > 100
      AND correlation < 0.1
    ORDER BY n_distinct DESC
    """
    
    Ecto.Adapters.SQL.query!(Repo, query, [])
  end

  def table_sizes do
    query = """
    SELECT 
      schemaname,
      tablename,
      pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
      pg_total_relation_size(schemaname||'.'||tablename) as size_bytes
    FROM pg_tables 
    WHERE schemaname = 'public'
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
    """
    
    Ecto.Adapters.SQL.query!(Repo, query, [])
  end
end
```

## Connection Pooling

### DBConnection Pool Configuration

```elixir
# config/config.exs
config :my_app, MyApp.Repo,
  # Connection pool configuration
  pool_size: 20,                    # Number of connections in pool
  queue_target: 50,                 # Target time for checkout (ms)
  queue_interval: 1000,             # Interval to check queue times
  
  # Connection timeouts
  timeout: 15_000,                  # Query timeout (15 seconds)
  connect_timeout: 5_000,           # Connection timeout (5 seconds)
  handshake_timeout: 5_000,         # Handshake timeout
  
  # Pool management
  pool_overflow: 10,                # Allow extra connections if needed
  lazy: false,                      # Start connections immediately
  
  # Connection validation
  disconnect_on_error_codes: [:closed, :closed_for_reading]

# Environment-specific configurations
# config/prod.exs
config :my_app, MyApp.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
  queue_target: 50,
  queue_interval: 1000,
  timeout: 15_000,
  ssl: true,
  ssl_opts: [
    verify: :verify_peer,
    cacerts: :public_key.cacerts_get(),
    server_name_indication: 'db.example.com',
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ]
```

### Pool Monitoring and Management

```elixir
defmodule MyApp.PoolMonitor do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Check pool stats every 30 seconds
    :timer.send_interval(30_000, :check_pool)
    {:ok, %{}}
  end

  def handle_info(:check_pool, state) do
    stats = DBConnection.status(MyApp.Repo)
    
    case stats do
      %{ready_conn_count: ready, checked_out_count: checked_out, pool_size: pool_size} ->
        utilization = checked_out / pool_size * 100
        
        if utilization > 80 do
          Logger.warn("High database pool utilization: #{utilization}% (#{checked_out}/#{pool_size})")
        end
        
        Logger.info("DB Pool Stats - Ready: #{ready}, Used: #{checked_out}/#{pool_size} (#{utilization}%)")
      
      _ ->
        Logger.warn("Could not retrieve database pool statistics")
    end
    
    {:noreply, state}
  end

  def get_pool_stats do
    DBConnection.status(MyApp.Repo)
  end
end

# Add to application supervision tree
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    MyApp.PoolMonitor,
    # ... other children
  ]
  
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Connection Pool Patterns

```elixir
defmodule MyApp.DatabaseUtils do
  alias MyApp.Repo
  
  # Use transactions for multiple operations
  def create_user_with_profile(user_attrs, profile_attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- create_user(user_attrs),
           {:ok, profile} <- create_profile(user, profile_attrs) do
        {user, profile}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Use checkout for long-running operations
  def bulk_import(data_list) do
    Repo.checkout(fn ->
      Enum.each(data_list, &import_record/1)
    end, timeout: 60_000)
  end

  # Pool-aware batching
  def process_in_batches(items, batch_size \\ 100) do
    items
    |> Enum.chunk_every(batch_size)
    |> Enum.each(fn batch ->
      Repo.transaction(fn ->
        Enum.each(batch, &process_item/1)
      end)
    end)
  end

  defp import_record(data) do
    # Import logic here
  end

  defp process_item(item) do
    # Process item logic
  end
end
```

## Read Replicas

### Read Replica Configuration

```elixir
# lib/my_app/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres
end

# Read replica repo
defmodule MyApp.ReadRepo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end

# config/config.exs
config :my_app, MyApp.Repo,
  # Primary database configuration
  url: System.get_env("DATABASE_URL"),
  pool_size: 20

config :my_app, MyApp.ReadRepo,
  # Read replica configuration
  url: System.get_env("READ_DATABASE_URL"),
  pool_size: 15,
  priv: "priv/repo" # Share migrations with primary repo
```

### Read/Write Separation Patterns

```elixir
defmodule MyApp.BlogReader do
  alias MyApp.{Repo, ReadRepo}
  alias MyApp.Blog.Post
  import Ecto.Query

  # Read operations use read replica
  def list_published_posts do
    from(p in Post, where: p.published == true)
    |> ReadRepo.all()
  end

  def get_post!(id) do
    ReadRepo.get!(Post, id)
  end

  def search_posts(term) do
    # Complex read queries on replica
    search_query(term)
    |> ReadRepo.all()
  end

  # Write operations use primary database
  def create_post(attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def update_post(post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  defp search_query(term) do
    from p in Post,
      where: fragment("? @@ to_tsquery(?)", p.search_vector, ^term),
      order_by: [desc: fragment("ts_rank(?, to_tsquery(?))", p.search_vector, ^term)]
  end
end
```

### Automatic Read/Write Routing

```elixir
defmodule MyApp.RepoRouter do
  @read_operations [:all, :one, :one!, :get, :get!, :get_by, :get_by!, :exists?, :aggregate]
  @write_operations [:insert, :insert!, :update, :update!, :delete, :delete!, :insert_all, :update_all, :delete_all]

  def route_query(operation, query, opts \\ []) do
    repo = select_repo(operation, opts)
    apply(repo, operation, [query] ++ [opts])
  end

  defp select_repo(operation, opts) do
    cond do
      opts[:force_primary] -> MyApp.Repo
      operation in @read_operations -> MyApp.ReadRepo
      operation in @write_operations -> MyApp.Repo
      true -> MyApp.Repo # Default to primary for unknown operations
    end
  end

  # Wrapper functions
  def all(query, opts \\ []), do: route_query(:all, query, opts)
  def get!(schema, id, opts \\ []), do: route_query(:get!, schema, [id] ++ [opts])
  def insert(changeset, opts \\ []), do: route_query(:insert, changeset, opts)
  def update(changeset, opts \\ []), do: route_query(:update, changeset, opts)
end

# Usage in contexts
defmodule MyApp.Blog do
  alias MyApp.RepoRouter, as: Repo

  def list_posts do
    # Automatically routed to read replica
    Repo.all(Post)
  end

  def get_post!(id) do
    # Automatically routed to read replica
    Repo.get!(Post, id)
  end

  def create_post(attrs) do
    # Automatically routed to primary database
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def get_fresh_post!(id) do
    # Force read from primary (after write)
    Repo.get!(Post, id, force_primary: true)
  end
end
```

## Performance Monitoring

### Query Performance Tracking

```elixir
defmodule MyApp.QueryInstrumentation do
  require Logger

  def setup_telemetry do
    :telemetry.attach_many(
      "query-instrumentation",
      [
        [:my_app, :repo, :query],
        [:my_app, :read_repo, :query]
      ],
      &handle_query_event/4,
      nil
    )
  end

  def handle_query_event([:my_app, repo, :query], measurements, metadata, _config) do
    query_time = measurements.total_time
    
    # Log slow queries
    if query_time > 1_000_000 do # 1 second in microseconds
      Logger.warn("""
      Slow query detected on #{repo}:
      Time: #{query_time / 1_000}ms
      Query: #{metadata.query}
      """)
    end

    # Track query metrics
    :telemetry.execute(
      [:my_app, :database, :query],
      %{duration: query_time},
      %{repo: repo, query_type: classify_query(metadata.query)}
    )
  end

  defp classify_query(query) do
    cond do
      String.starts_with?(query, "SELECT") -> :read
      String.starts_with?(query, "INSERT") -> :write
      String.starts_with?(query, "UPDATE") -> :write
      String.starts_with?(query, "DELETE") -> :write
      true -> :other
    end
  end
end

# Add to application startup
def start(_type, _args) do
  MyApp.QueryInstrumentation.setup_telemetry()
  # ... rest of application
end
```

### Database Health Checks

```elixir
defmodule MyApp.DatabaseHealth do
  alias MyApp.{Repo, ReadRepo}

  def health_check do
    %{
      primary: check_connection(Repo),
      read_replica: check_connection(ReadRepo),
      pool_stats: pool_statistics()
    }
  end

  defp check_connection(repo) do
    try do
      Ecto.Adapters.SQL.query!(repo, "SELECT 1", [])
      %{status: :healthy, timestamp: DateTime.utc_now()}
    rescue
      _ -> %{status: :unhealthy, timestamp: DateTime.utc_now()}
    end
  end

  defp pool_statistics do
    %{
      primary: DBConnection.status(Repo),
      read_replica: DBConnection.status(ReadRepo)
    }
  end

  def cache_hit_ratio do
    query = """
    SELECT 
      sum(heap_blks_read) as heap_read,
      sum(heap_blks_hit) as heap_hit,
      sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
    FROM pg_statio_user_tables
    """
    
    case Ecto.Adapters.SQL.query(Repo, query, []) do
      {:ok, %{rows: [[_, _, ratio]]}} -> Float.round(ratio * 100, 2)
      _ -> nil
    end
  end
end
```

This comprehensive database performance recipe provides production-ready patterns for optimizing database interactions in Phoenix applications, ensuring efficient queries, proper connection management, and scalable read/write patterns.