# MVP Phoenix Patterns - Technology Choices for Fast Shipping

This guide provides specific Phoenix/Elixir technology choices and implementation patterns optimized for MVP development.

## Phoenix/Elixir MVP Technology Patterns

### Web Layer: Controllers vs LiveView

**MVP Default: Traditional Controllers + HEEx Templates**
```elixir
# Use for: Forms, CRUD operations, simple workflows
defmodule MyAppWeb.ImportController do
  use MyAppWeb, :controller

  def new(conn, _params) do
    render(conn, :new, changeset: Imports.change_import(%Import{}))
  end

  def create(conn, %{"import" => import_params}) do
    case Imports.create_import(import_params) do
      {:ok, import} ->
        conn
        |> put_flash(:info, "Import started")
        |> redirect(to: ~p"/imports/#{import}")
      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
```

**Roadmap: LiveView for Interactivity**
```elixir
# Use only when: Real-time updates are essential, complex client state
defmodule MyAppWeb.ImportLive.New do
  use MyAppWeb, :live_view

  def handle_event("validate", %{"import" => params}, socket) do
    # Real-time validation, file preview, progress tracking
  end
end
```

**Decision Rule**: If a page reload solves the user problem, use controllers.

### Data Layer: Schema Design

**MVP: Purpose-Driven Schema Design**
```elixir
# Design schemas that serve your core value proposition
# For data pipeline apps: structured data flow is essential
defmodule MyApp.Data.StagingRecord do
  schema "staging_records" do
    field :raw_data, :map
    field :entity_type, :string
    field :processed, :boolean, default: false
    belongs_to :import_batch, MyApp.Data.ImportBatch
    timestamps()
  end
end

defmodule MyApp.Data.Contact do
  schema "contacts" do
    field :name, :string
    field :email, :string
    belongs_to :organization, MyApp.Data.Organization
    # Structure that supports your core business logic
    timestamps()
  end
end
```

**Alternative MVP: Simple Flat Schema (When Appropriate)**
```elixir
# Use when: Data relationships aren't core to the value proposition
defmodule MyApp.Contacts.Person do
  schema "people" do
    field :name, :string
    field :email, :string
    field :company_name, :string        # Denormalized for simplicity
    field :company_domain, :string      # When relationships aren't essential
    timestamps()
  end
end
```

**Roadmap: Complex Relationships and Constraints**
```elixir
# Add when: Data integrity becomes critical, complex queries needed
defmodule MyApp.Contacts.Person do
  schema "people" do
    field :name, :string
    belongs_to :organization, MyApp.Organizations.Organization
    has_many :contact_methods, MyApp.Contacts.ContactMethod
    has_many :roles, MyApp.Contacts.Role
    has_many :interactions, MyApp.Contacts.Interaction
    # Complex validation rules and business constraints
  end
end
```

### Authentication Patterns

**MVP: Single OAuth Provider (When Simpler)**
```elixir
# Use when: OAuth is simpler than custom auth, B2B domain restrictions needed
# Google OAuth with domain filtering is often simpler than phx.gen.auth
defmodule MyAppWeb.GoogleAuth do
  # Single provider OAuth (Google)
  # Domain restriction (@company.com)
  # Basic session management
  # No complex role management
end
```

**MVP Alternative: Built-in Phoenix Authentication**
```elixir
# Use when: Simple email/password sufficient, no domain restrictions
defmodule MyAppWeb.UserAuth do
  # Standard Phoenix auth patterns
  # Email verification optional for MVP
  # Password reset can be manual/admin-assisted
end
```

**Roadmap: Multi-provider, Advanced Features**
```elixir
# Add when: User management becomes complex
# - Multiple OAuth providers (Google, GitHub, Microsoft)
# - Multi-factor authentication  
# - Advanced role-based access control
# - User provisioning and deprovisioning
```

### Background Processing

**MVP: Synchronous When Possible**
```elixir
# For fast operations (<2 seconds)
def import_small_csv(file_path) do
  file_path
  |> CSV.parse()
  |> Enum.each(&create_contact/1)
  
  {:ok, "Import completed"}
end
```

**MVP: Basic Oban for Essential Background Tasks**
```elixir
# Use when: Core functionality requires background processing
defmodule MyApp.Workers.ImportWorker do
  use Oban.Worker, queue: :imports

  def perform(%Oban.Job{args: %{"file_path" => path}}) do
    # Essential background tasks like:
    # - Data deduplication
    # - External API enrichment
    # - CRM synchronization
    # Keep logic simple, basic error handling
  end
end

# Basic scheduled jobs for essential maintenance
defmodule MyApp.Workers.ScheduledWorker do
  use Oban.Worker, queue: :scheduled, cron: "0 2 * * *"
  
  # Nightly maintenance tasks that are core to the app
end
```

**Roadmap: Complex Job Orchestration**
```elixir
# Advanced Oban features:
# - Job dependencies and workflows
# - Custom retry logic and backoff strategies
# - Queue priorities and rate limiting
# - Comprehensive job observability and metrics
# - Complex error recovery patterns
```

### Database Patterns

**MVP: Simple Ecto Queries**
```elixir
# Direct, readable queries
def list_recent_contacts do
  from(c in Contact,
    where: c.inserted_at > ago(7, "day"),
    order_by: [desc: c.inserted_at],
    limit: 100
  )
  |> Repo.all()
end

# Basic pagination with offset/limit
def list_contacts(page \\ 1, per_page \\ 20) do
  offset = (page - 1) * per_page
  
  from(c in Contact,
    limit: ^per_page,
    offset: ^offset
  )
  |> Repo.all()
end
```

**Roadmap: Advanced Query Patterns**
```elixir
# When needed: Complex aggregations, materialized views, full-text search
# - Ecto.Query with complex joins and subqueries
# - Database-specific features (PostgreSQL JSON, full-text search)
# - Query optimization and explain analysis
# - Custom Ecto types and functions
```

### API Design

**MVP: Simple JSON Controllers**
```elixir
# Basic REST endpoints for essential integrations
defmodule MyAppWeb.API.ContactController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    contacts = Contacts.list_contacts()
    json(conn, %{contacts: contacts})
  end

  def show(conn, %{"id" => id}) do
    contact = Contacts.get_contact!(id)
    json(conn, %{contact: contact})
  end
end
```

**Roadmap: GraphQL, Comprehensive APIs**
```elixir
# When needed: Complex client requirements, mobile apps
# - Absinthe GraphQL with subscriptions
# - API versioning and deprecation
# - Rate limiting and authentication
# - OpenAPI documentation
```

### External API Integration

**MVP: Essential APIs with Basic Integration**
```elixir
# Use when: External data IS the core value proposition
defmodule MyApp.ExternalAPI.Client do
  # Basic HTTP client for essential integrations
  # Simple error handling (log and retry once)
  # Basic rate limiting (sleep/delay, not sophisticated queuing)
  
  def enrich_contact(email) do
    case HTTPoison.get("#{@base_url}/enrich", headers: auth_headers()) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}
      {:ok, %{status_code: 429}} ->
        Process.sleep(1000)  # Simple rate limit handling
        {:error, :rate_limited}
      {:error, _} ->
        {:error, :api_unavailable}
    end
  end
end
```

**Roadmap: Sophisticated API Management**
```elixir
# Advanced features when scale demands it:
# - Comprehensive rate limiting with backoff strategies
# - Circuit breakers and fallback mechanisms
# - Request/response caching and optimization
# - Detailed API monitoring and alerting
# - Multiple provider fallbacks
```

### Error Handling

**MVP: Basic Error Pages and Flash Messages**
```elixir
# Simple, user-friendly error handling
def create_contact(conn, params) do
  case Contacts.create_contact(params) do
    {:ok, contact} ->
      conn
      |> put_flash(:info, "Contact created successfully")
      |> redirect(to: ~p"/contacts/#{contact}")
    
    {:error, changeset} ->
      conn
      |> put_flash(:error, "Please fix the errors below")
      |> render(:new, changeset: changeset)
  end
end

# Basic error pages in router
defp handle_errors(conn, %{kind: :error, reason: %Phoenix.Router.NoRouteError{}}) do
  render(conn, MyAppWeb.ErrorHTML, "404.html")
end
```

**Roadmap: Comprehensive Error Management**
```elixir
# Advanced error handling:
# - Structured error logging with metadata
# - Error monitoring and alerting (Sentry, etc.)
# - Graceful degradation patterns
# - Custom error types and recovery strategies
```

### Testing Strategy

**MVP: Happy Path + Basic Error Cases**
```elixir
# Context tests for core business logic
test "create_contact/1 with valid data creates a contact" do
  valid_attrs = %{name: "John", email: "john@example.com"}
  assert {:ok, %Contact{} = contact} = Contacts.create_contact(valid_attrs)
  assert contact.name == "John"
end

# Controller tests for main user flows
test "GET /contacts returns list of contacts", %{conn: conn} do
  contact = contact_fixture()
  conn = get(conn, ~p"/contacts")
  assert html_response(conn, 200) =~ contact.name
end

# Skip: Complex edge cases, performance tests, property-based tests
```

**Roadmap: Comprehensive Test Suite**
```elixir
# When needed: Complex business logic, integration requirements
# - Property-based testing with StreamData
# - Performance and load testing
# - Integration tests with external APIs
# - Browser-based testing with Wallaby
```

### Deployment Patterns

**MVP: Single Server Deployment**
```bash
# Railway, Render, or Heroku deployment
# Single Postgres instance
# No CDN, load balancers, or horizontal scaling
# Basic monitoring (platform-provided)
# SQLite for development/testing

# Simple release configuration
mix phx.gen.release
# Basic environment variables
# No infrastructure as code
```

**Roadmap: Production Infrastructure**
```bash
# When needed: Scale requirements, high availability
# - Multi-server deployment with load balancing
# - CDN for static assets
# - Redis for session storage/caching
# - Comprehensive monitoring (Datadog, New Relic)
# - Infrastructure as code (Terraform, Ansible)
# - CI/CD pipelines with staging environments
```

### Styling and UI

**MVP: Utility-First CSS (Tailwind)**
```heex
<!-- Direct Tailwind classes, no custom components -->
<div class="max-w-md mx-auto bg-white rounded-lg shadow-md p-6">
  <h2 class="text-xl font-bold mb-4">Add Contact</h2>
  <form>
    <div class="mb-4">
      <label class="block text-sm font-medium text-gray-700 mb-2">
        Name
      </label>
      <input type="text" class="w-full border border-gray-300 rounded-md px-3 py-2">
    </div>
    <button class="w-full bg-blue-500 text-white py-2 px-4 rounded-md hover:bg-blue-600">
      Save
    </button>
  </form>
</div>
```

**Roadmap: Design System and Components**
```heex
<!-- When needed: Consistent UI across large app -->
<.card>
  <.form for={@form}>
    <.input field={@form[:name]} label="Name" />
    <.button variant="primary">Save</.button>
  </.form>
</.card>

<!-- Custom CSS, design tokens, component library -->
```

### Phoenix Feature Decision Matrix

| Feature | MVP (Use) | Roadmap (Defer) |
|---------|-----------|-----------------|
| **Controllers** | ✅ Form handling, CRUD | Complex workflows |
| **LiveView** | Simple real-time needs | ✅ Interactive features |
| **Contexts** | ✅ Basic CRUD functions | Complex business logic |
| **Ecto Schemas** | ✅ Purpose-driven design | Over-normalized complexity |
| **Background Jobs** | ✅ Essential tasks (Oban) | Complex orchestration |
| **Authentication** | ✅ OAuth (if simpler) or phx.gen.auth | Multi-provider, advanced RBAC |
| **External APIs** | ✅ Essential integrations | Sophisticated error handling |
| **Testing** | ✅ Happy path coverage | Comprehensive edge cases |
| **Deployment** | ✅ Single server (Railway) | Multi-server, DevOps |
| **Monitoring** | Platform-provided basics | ✅ Custom metrics, APM |
| **Caching** | Simple ETS if needed | ✅ Redis, complex strategies |

### Technology Choice Guidelines

**Use in MVP:**
- Phoenix 1.7+ (stable, proven)
- PostgreSQL (for any serious data)
- Tailwind CSS (utility-first styling)
- Oban (when background jobs essential)
- OAuth (if simpler than custom auth) OR phx.gen.auth
- HEEx templates for server-rendered pages
- Basic Ecto queries with purpose-driven schemas
- Essential external API integrations (simple implementation)

**Defer to Roadmap:**
- LiveView (unless trivially simple)
- GraphQL (use REST first)
- Custom CSS frameworks
- Microservices architecture
- Event sourcing/CQRS patterns
- Advanced caching strategies
- Complex deployment orchestration
- Sophisticated API management

**Never Use in MVP:**
- Experimental Phoenix features
- Custom authentication systems (unless OAuth is also complex)
- Premature optimizations
- Complex state management
- Advanced metaprogramming

## Phoenix-Specific MVP Implementation Examples

### Form Handling: Controller vs LiveView

**MVP: Traditional Form Controller**
```elixir
# lib/my_app_web/controllers/contact_controller.ex
defmodule MyAppWeb.ContactController do
  use MyAppWeb, :controller

  def new(conn, _params) do
    changeset = Contacts.change_contact(%Contact{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"contact" => contact_params}) do
    case Contacts.create_contact(contact_params) do
      {:ok, contact} ->
        conn
        |> put_flash(:info, "Contact created successfully.")
        |> redirect(to: ~p"/contacts/#{contact}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, status: :unprocessable_entity)
    end
  end
end
```

**Roadmap: LiveView with Real-time Validation**
```elixir
# lib/my_app_web/live/contact_live/form_component.ex
defmodule MyAppWeb.ContactLive.FormComponent do
  use MyAppWeb, :live_component

  def handle_event("validate", %{"contact" => contact_params}, socket) do
    changeset =
      socket.assigns.contact
      |> Contacts.change_contact(contact_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"contact" => contact_params}, socket) do
    save_contact(socket, socket.assigns.action, contact_params)
  end
end
```

### Data Import: Synchronous vs Background

**MVP: Synchronous Processing**
```elixir
# lib/my_app_web/controllers/import_controller.ex
def create(conn, %{"import" => %{"file" => upload}}) do
  case ImportService.process_csv_sync(upload.path) do
    {:ok, results} ->
      conn
      |> put_flash(:info, "Imported #{results.count} records")
      |> redirect(to: ~p"/contacts")
    
    {:error, reason} ->
      conn
      |> put_flash(:error, "Import failed: #{reason}")
      |> redirect(to: ~p"/imports/new")
  end
end
```

**Roadmap: Background Processing with Status**
```elixir
# lib/my_app_web/live/import_live/show.ex
def handle_event("start_import", %{"file" => upload}, socket) do
  {:ok, job} = ImportWorker.enqueue(%{file_path: upload.path})
  
  socket =
    socket
    |> assign(:import_job_id, job.id)
    |> start_import_timer()
  
  {:noreply, socket}
end

defp start_import_timer(socket) do
  if connected?(socket) do
    Process.send_after(self(), :check_import_status, 1000)
  end
  socket
end
```

### Authentication: OAuth vs Built-in

**MVP: Google OAuth (For B2B with Domain Restrictions)**
```elixir
# lib/my_app_web/controllers/auth_controller.ex
defmodule MyAppWeb.AuthController do
  use MyAppWeb, :controller
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_info = %{
      email: auth.info.email,
      name: auth.info.name,
      domain: extract_domain(auth.info.email)
    }
    
    case is_allowed_domain?(user_info.domain) do
      true ->
        {:ok, user} = Accounts.find_or_create_user(user_info)
        
        conn
        |> put_session(:user_id, user.id)
        |> redirect(to: ~p"/dashboard")
      
      false ->
        conn
        |> put_flash(:error, "Domain not authorized")
        |> redirect(to: ~p"/")
    end
  end

  defp is_allowed_domain?(domain) do
    domain in ["mycompany.com", "partner.com"]
  end
end
```

**MVP Alternative: phx.gen.auth (For Simple Email/Password)**
```bash
# Generate basic authentication
mix phx.gen.auth Accounts User users

# Minimal customization:
# - Skip email confirmation for MVP
# - Simple password reset (admin-assisted)
# - Basic session management
```

### Real-time Features: Polling vs LiveView

**MVP: Simple Polling**
```javascript
// assets/js/app.js - Simple JavaScript polling
function updateDashboard() {
  fetch('/api/dashboard/stats')
    .then(response => response.json())
    .then(data => {
      document.getElementById('contact-count').textContent = data.contact_count;
      document.getElementById('deal-count').textContent = data.deal_count;
    });
}

// Poll every 30 seconds
setInterval(updateDashboard, 30000);
```

**Roadmap: LiveView Real-time Updates**
```elixir
# lib/my_app_web/live/dashboard_live.ex
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, "dashboard_updates")
      :timer.send_interval(5000, self(), :update_stats)
    end

    {:ok, assign(socket, :stats, Dashboard.get_stats())}
  end

  def handle_info(:update_stats, socket) do
    {:noreply, assign(socket, :stats, Dashboard.get_stats())}
  end

  def handle_info({:stats_updated, new_stats}, socket) do
    {:noreply, assign(socket, :stats, new_stats)}
  end
end
```

### Error Handling: Simple vs Comprehensive

**MVP: Basic Flash Messages**
```elixir
# lib/my_app_web/controllers/contact_controller.ex
def create(conn, %{"contact" => contact_params}) do
  case Contacts.create_contact(contact_params) do
    {:ok, contact} ->
      conn
      |> put_flash(:info, "Contact created successfully")
      |> redirect(to: ~p"/contacts/#{contact}")
    
    {:error, %Ecto.Changeset{} = changeset} ->
      conn
      |> put_flash(:error, "Please check the errors below")
      |> render(:new, changeset: changeset)
    
    {:error, reason} ->
      conn
      |> put_flash(:error, "Something went wrong: #{reason}")
      |> render(:new, changeset: Contacts.change_contact(%Contact{}))
  end
end
```

**Roadmap: Structured Error Handling**
```elixir
# lib/my_app/error_tracker.ex
defmodule MyApp.ErrorTracker do
  def track_error(error, context \\ %{}) do
    metadata = %{
      user_id: context[:user_id],
      request_id: context[:request_id],
      timestamp: DateTime.utc_now(),
      environment: Application.get_env(:my_app, :environment)
    }
    
    # Send to external service (Sentry, Rollbar, etc.)
    ExternalErrorService.report(error, metadata)
    
    # Log locally
    Logger.error("Application error", error: error, metadata: metadata)
  end
end
```

## Summary

Phoenix MVP development should prioritize:

1. **Controllers over LiveView** for most use cases
2. **Simple schemas** that serve your core value proposition
3. **Basic authentication** (OAuth for B2B, phx.gen.auth for simple apps)
4. **Synchronous processing** when possible, basic Oban when needed
5. **Simple Ecto queries** over complex database patterns
6. **Basic error handling** with flash messages
7. **Utility-first CSS** over custom design systems

Remember: These patterns are about shipping quickly and learning from real users. Once you've validated your core value proposition, you can systematically upgrade to more sophisticated patterns based on actual needs, not theoretical requirements.

---

## Related Files

For high-level MVP decision-making, see:
- [MVP Principles](./mvp_principles.md) - Decision frameworks and philosophy
- [TDD Git Workflow Recipe](./tdd_git_workflow_recipe.md) - Development practices
- [Template Elixir Phoenix Recipe](./template_elixir_phoenix_recipe.md) - Project setup patterns