# Phoenix Controllers Recipe

## Introduction

Controllers in Phoenix handle incoming HTTP requests and return appropriate responses. They act as the interface between your web layer and your application contexts, processing parameters, calling business logic, and rendering responses. Controllers should be kept thin, focusing primarily on request/response handling.

## Basic Controller Structure

```elixir
defmodule MyAppWeb.PostController do
  use MyAppWeb, :controller
  
  alias MyApp.Blog
  alias MyApp.Blog.Post

  def index(conn, _params) do
    posts = Blog.list_posts()
    render(conn, :index, posts: posts)
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    render(conn, :show, post: post)
  end

  def new(conn, _params) do
    changeset = Blog.change_post(%Post{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"post" => post_params}) do
    case Blog.create_post(post_params) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post created successfully.")
        |> redirect(to: ~p"/posts/#{post}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    changeset = Blog.change_post(post)
    render(conn, :edit, post: post, changeset: changeset)
  end

  def update(conn, %{"id" => id, "post" => post_params}) do
    post = Blog.get_post!(id)

    case Blog.update_post(post, post_params) do
      {:ok, post} ->
        conn
        |> put_flash(:info, "Post updated successfully.")
        |> redirect(to: ~p"/posts/#{post}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, post: post, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    {:ok, _post} = Blog.delete_post(post)

    conn
    |> put_flash(:info, "Post deleted successfully.")
    |> redirect(to: ~p"/posts")
  end
end
```

## Controller with Authentication

```elixir
defmodule MyAppWeb.DashboardController do
  use MyAppWeb, :controller

  # Require authentication for all actions
  plug :require_authenticated_user

  # Custom authorization plug
  plug :authorize_user when action in [:admin_dashboard]

  def index(conn, _params) do
    user = conn.assigns.current_user
    stats = MyApp.Analytics.get_user_stats(user)
    render(conn, :index, stats: stats)
  end

  def admin_dashboard(conn, _params) do
    admin_stats = MyApp.Analytics.get_admin_stats()
    render(conn, :admin_dashboard, stats: admin_stats)
  end

  defp authorize_user(conn, _opts) do
    if conn.assigns.current_user.role == :admin do
      conn
    else
      conn
      |> put_flash(:error, "Access denied.")
      |> redirect(to: ~p"/dashboard")
      |> halt()
    end
  end
end
```

## API Controller with JSON Responses

```elixir
defmodule MyAppWeb.API.PostController do
  use MyAppWeb, :controller

  alias MyApp.Blog
  alias MyApp.Blog.Post

  action_fallback MyAppWeb.API.FallbackController

  def index(conn, params) do
    page = Map.get(params, "page", 1)
    per_page = Map.get(params, "per_page", 20)
    
    posts = Blog.list_posts(page: page, per_page: per_page)
    render(conn, :index, posts: posts)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, post} <- Blog.get_post(id) do
      render(conn, :show, post: post)
    end
  end

  def create(conn, %{"post" => post_params}) do
    with {:ok, %Post{} = post} <- Blog.create_post(post_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/posts/#{post}")
      |> render(:show, post: post)
    end
  end

  def update(conn, %{"id" => id, "post" => post_params}) do
    with {:ok, post} <- Blog.get_post(id),
         {:ok, %Post{} = post} <- Blog.update_post(post, post_params) do
      render(conn, :show, post: post)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, post} <- Blog.get_post(id),
         {:ok, %Post{}} <- Blog.delete_post(post) do
      send_resp(conn, :no_content, "")
    end
  end
end
```

## Fallback Controller for Error Handling

```elixir
defmodule MyAppWeb.API.FallbackController do
  use MyAppWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(MyAppWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(MyAppWeb.ErrorJSON)
    |> render(:"401")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(MyAppWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(MyAppWeb.ErrorJSON)
    |> render(:"400")
  end
end
```

## Controller with File Upload

```elixir
defmodule MyAppWeb.UploadController do
  use MyAppWeb, :controller

  plug :require_authenticated_user

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"upload" => upload_params}) do
    case upload_params["file"] do
      %Plug.Upload{} = upload ->
        case MyApp.FileStorage.store_upload(upload, conn.assigns.current_user) do
          {:ok, file} ->
            conn
            |> put_flash(:info, "File uploaded successfully.")
            |> redirect(to: ~p"/uploads/#{file}")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Upload failed: #{reason}")
            |> render(:new)
        end

      nil ->
        conn
        |> put_flash(:error, "Please select a file to upload.")
        |> render(:new)
    end
  end

  def show(conn, %{"id" => id}) do
    file = MyApp.FileStorage.get_file!(id)
    
    # Check if user has permission to view this file
    if can_view_file?(conn.assigns.current_user, file) do
      render(conn, :show, file: file)
    else
      conn
      |> put_flash(:error, "Access denied.")
      |> redirect(to: ~p"/uploads")
    end
  end

  def download(conn, %{"id" => id}) do
    file = MyApp.FileStorage.get_file!(id)
    
    if can_view_file?(conn.assigns.current_user, file) do
      conn
      |> put_resp_content_type(file.content_type)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{file.filename}"))
      |> send_file(200, file.path)
    else
      conn
      |> put_status(:forbidden)
      |> put_view(MyAppWeb.ErrorHTML)
      |> render(:"403")
    end
  end

  defp can_view_file?(user, file) do
    file.user_id == user.id or user.role == :admin
  end
end
```

## Controller with Pagination and Search

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  alias MyApp.Accounts

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    search = params["search"] || ""
    sort_by = params["sort_by"] || "name"
    sort_order = params["sort_order"] || "asc"

    users = Accounts.list_users(
      page: page,
      per_page: 25,
      search: search,
      sort_by: sort_by,
      sort_order: sort_order
    )

    render(conn, :index, 
      users: users,
      page: page,
      search: search,
      sort_by: sort_by,
      sort_order: sort_order
    )
  end

  def search(conn, %{"q" => query}) do
    users = Accounts.search_users(query, limit: 10)
    
    # Return JSON for AJAX requests
    case get_format(conn) do
      "json" ->
        render(conn, :search, users: users)
      _ ->
        render(conn, :index, users: users, search: query)
    end
  end
end
```

## Controller with Custom Response Formats

```elixir
defmodule MyAppWeb.ReportController do
  use MyAppWeb, :controller

  plug :require_authenticated_user

  def show(conn, %{"id" => id}) do
    report = MyApp.Reports.get_report!(id)
    
    case get_format(conn) do
      "html" ->
        render(conn, :show, report: report)
        
      "json" ->
        render(conn, :show, report: report)
        
      "csv" ->
        csv_data = MyApp.Reports.to_csv(report)
        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="report_#{id}.csv"))
        |> send_resp(200, csv_data)
        
      "pdf" ->
        pdf_data = MyApp.Reports.to_pdf(report)
        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(attachment; filename="report_#{id}.pdf"))
        |> send_resp(200, pdf_data)
        
      _ ->
        conn
        |> put_status(:not_acceptable)
        |> put_view(MyAppWeb.ErrorHTML)
        |> render(:"406")
    end
  end
end
```

## Controller with Background Jobs

```elixir
defmodule MyAppWeb.ImportController do
  use MyAppWeb, :controller

  alias MyApp.DataImport

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"import" => %{"file" => file}}) do
    case DataImport.queue_import(file, conn.assigns.current_user) do
      {:ok, import_job} ->
        conn
        |> put_flash(:info, "Import started. You'll be notified when it's complete.")
        |> redirect(to: ~p"/imports/#{import_job}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Import failed: #{reason}")
        |> render(:new)
    end
  end

  def show(conn, %{"id" => id}) do
    import_job = DataImport.get_import_job!(id)
    
    # Check if user owns this import
    if import_job.user_id == conn.assigns.current_user.id do
      render(conn, :show, import_job: import_job)
    else
      conn
      |> put_flash(:error, "Access denied.")
      |> redirect(to: ~p"/imports")
    end
  end

  def cancel(conn, %{"id" => id}) do
    import_job = DataImport.get_import_job!(id)
    
    case DataImport.cancel_import(import_job) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Import cancelled.")
        |> redirect(to: ~p"/imports/#{import_job}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Cannot cancel import: #{reason}")
        |> redirect(to: ~p"/imports/#{import_job}")
    end
  end
end
```

## Controller with Caching

```elixir
defmodule MyAppWeb.PublicController do
  use MyAppWeb, :controller

  plug :put_cache_headers when action in [:index, :show]

  def index(conn, _params) do
    posts = get_cached_posts()
    render(conn, :index, posts: posts)
  end

  def show(conn, %{"slug" => slug}) do
    case get_cached_post(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(MyAppWeb.ErrorHTML)
        |> render(:"404")
        
      post ->
        render(conn, :show, post: post)
    end
  end

  defp put_cache_headers(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> put_resp_header("etag", generate_etag(conn))
  end

  defp get_cached_posts do
    # Use your preferred caching solution
    case :ets.lookup(:posts_cache, :all) do
      [{:all, posts}] -> posts
      [] ->
        posts = MyApp.Blog.list_published_posts()
        :ets.insert(:posts_cache, {:all, posts})
        posts
    end
  end

  defp get_cached_post(slug) do
    case :ets.lookup(:posts_cache, slug) do
      [{^slug, post}] -> post
      [] ->
        case MyApp.Blog.get_post_by_slug(slug) do
          nil -> nil
          post ->
            :ets.insert(:posts_cache, {slug, post})
            post
        end
    end
  end

  defp generate_etag(conn) do
    # Generate ETag based on request path and current time
    data = "#{conn.request_path}:#{System.system_time(:second)}"
    :crypto.hash(:md5, data) |> Base.encode16(case: :lower)
  end
end
```

## Testing Controllers

```elixir
defmodule MyAppWeb.PostControllerTest do
  use MyAppWeb.ConnCase

  import MyApp.BlogFixtures

  describe "GET /posts" do
    test "lists all posts", %{conn: conn} do
      post = post_fixture()
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ post.title
    end
  end

  describe "GET /posts/new" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/posts/new")
      assert html_response(conn, 200) =~ "New Post"
    end
  end

  describe "POST /posts" do
    test "creates post when data is valid", %{conn: conn} do
      post_params = %{title: "Test Post", content: "Test content"}
      conn = post(conn, ~p"/posts", post: post_params)
      
      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/posts/#{id}"
      
      conn = get(conn, ~p"/posts/#{id}")
      assert html_response(conn, 200) =~ "Test Post"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/posts", post: %{title: ""})
      assert html_response(conn, 200) =~ "can't be blank"
    end
  end

  describe "authentication" do
    test "requires user to be logged in", %{conn: conn} do
      conn = get(conn, ~p"/posts/new")
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
```

## Tips & Best Practices

### Controller Design
- Keep controllers thin - business logic belongs in contexts
- Use pattern matching in function parameters for clarity
- Handle both success and error cases explicitly
- Use `action_fallback` for consistent error handling in APIs

### Parameter Handling
- Always validate and sanitize input parameters
- Use pattern matching to extract expected parameters
- Provide default values for optional parameters
- Use `Ecto.Changeset` for complex parameter validation

### Response Handling
- Use appropriate HTTP status codes
- Provide meaningful flash messages for user feedback
- Handle different response formats (HTML, JSON, CSV, etc.)
- Use proper headers for caching and security

### Security
- Always validate user permissions before actions
- Use CSRF protection for state-changing operations
- Sanitize file uploads and validate file types
- Implement rate limiting for sensitive endpoints

### Performance
- Use database pagination for large datasets
- Implement caching for frequently accessed data
- Use background jobs for time-consuming operations
- Optimize database queries in your contexts

## References

- [Phoenix Controllers Documentation](https://hexdocs.pm/phoenix/controllers.html)
- [Plug.Conn Documentation](https://hexdocs.pm/plug/Plug.Conn.html)
- [Phoenix Testing Controllers](https://hexdocs.pm/phoenix/testing_controllers.html)
- [Phoenix Views and Templates](https://hexdocs.pm/phoenix/views.html)