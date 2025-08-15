# MVP Focus Recipe - Ship Fast, Iterate Later

```bash
# Project structure for MVP discipline
docs/
├── prd/
│   ├── mvp.md           # Essential features only (see your actual file)
│   └── roadmap.md       # Everything else goes here
└── decisions/           # ADRs for MVP vs roadmap choices
```

## The Problem: Feature Creep and Perfectionism

❌ **Common Anti-Patterns:**
- "Just one more feature before we launch"
- "This needs to be perfect before users see it"
- "Let's add this cool new technology"
- "We should handle all edge cases first"
- Spending weeks on 20% improvement when 80% would ship

## The MVP Mindset: C+ Work is Shipping Work

**Target Quality: C+ (Good Enough)**
- ✅ Works for the happy path
- ✅ Handles basic error cases
- ✅ Looks presentable (not beautiful)
- ✅ Users can complete core tasks
- ❌ Not handling every edge case
- ❌ Not optimized for performance
- ❌ Not using the latest tech stack
- ❌ Not pixel-perfect design

## Decision Framework: MVP vs Roadmap

### The Five Questions Test

Before implementing any feature, ask:

1. **Can users complete the core task without this?**
   - If YES → Roadmap
   - If NO → Consider for MVP

2. **Does this take more than 1-2 days to implement?**
   - If YES → Break down or move to roadmap
   - If NO → Might be MVP

3. **Is this a "nice to have" or "must have"?**
   - Nice to have → Roadmap
   - Must have → MVP (but question if it's really must-have)

4. **Are we adding this to show off technical skills?**
   - If YES → Definitely roadmap
   - If NO → Continue evaluation

5. **Will 90% of users need this on day 1?**
   - If NO → Roadmap
   - If YES → MVP candidate

### Implementation Complexity Ladder

**Choose the simplest approach that works:**

```elixir
# LEVEL 1: MVP - Static page refresh
def show_metrics(conn, _params) do
  metrics = Analytics.get_current_metrics()
  render(conn, :dashboard, metrics: metrics)
end

# LEVEL 2: Roadmap - Real-time updates
def show_metrics(socket, _params) do
  socket
  |> assign(:metrics, Analytics.get_current_metrics())
  |> start_metrics_timer()  # Phoenix.LiveView real-time
end

# LEVEL 3: Future - Advanced analytics
def show_metrics(socket, _params) do
  socket
  |> assign(:metrics, Analytics.get_real_time_metrics())
  |> assign(:trends, Analytics.calculate_trends())
  |> assign(:predictions, ML.predict_future_metrics())
  |> start_advanced_timer()
end
```

**MVP Rule**: Always choose Level 1 unless Level 2 is trivially easy.

## "Good Enough" vs Over-Engineering Examples

### Database Design

```elixir
# MVP: Simple, direct approach
defmodule MyApp.People.Person do
  schema "people" do
    field :name, :string
    field :email, :string
    field :company, :string
    timestamps()
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :email, :company])
    |> validate_required([:name, :email])
  end
end

# OVER-ENGINEERED: Complex normalization
defmodule MyApp.People.Person do
  schema "people" do
    field :first_name, :string
    field :middle_name, :string
    field :last_name, :string
    field :preferred_name, :string
    field :name_prefix, :string
    field :name_suffix, :string
    
    has_many :email_addresses, MyApp.People.EmailAddress
    has_many :phone_numbers, MyApp.People.PhoneNumber
    belongs_to :primary_organization, MyApp.Organizations.Organization
    has_many :organization_roles, MyApp.People.OrganizationRole
  end
end
```

### User Interface Approach

```heex
<!-- MVP: Functional form with basic styling -->
<div class="max-w-lg mx-auto">
  <h1 class="text-xl font-bold mb-4">Upload CSV</h1>
  <.form for={@form} action={~p"/imports"} multipart>
    <div class="mb-4">
      <.input field={@form[:file]} type="file" accept=".csv" />
    </div>
    <div class="mb-4">
      <.input field={@form[:format]} type="select" 
             options={[{"Auto-detect", ""}, {"Crunchbase", "crunchbase"}]} />
    </div>
    <.button>Upload</.button>
  </.form>
</div>

<!-- OVER-ENGINEERED: Drag-drop with preview -->
<div class="upload-wizard">
  <.drag_drop_zone 
    on_drop="file_dropped"
    on_preview="show_preview"
    with_progress_bar
    animated_transitions>
    <.file_preview columns={@preview_columns} rows={@preview_rows} />
    <.mapping_interface source={@detected_format} target={@schema} />
    <.validation_results errors={@validation_errors} warnings={@warnings} />
  </.drag_drop_zone>
</div>
```

### Error Handling Complexity

```elixir
# MVP: Basic error handling
def import_csv(file_path) do
  case CSV.parse_file(file_path) do
    {:ok, data} -> 
      process_records(data)
      {:ok, "Import completed"}
    {:error, reason} -> 
      {:error, "Failed to process file: #{reason}"}
  end
end

# OVER-ENGINEERED: Comprehensive error system
def import_csv(file_path) do
  with {:ok, file_info} <- validate_file(file_path),
       {:ok, parsed_data} <- parse_with_recovery(file_path),
       {:ok, validated_data} <- validate_business_rules(parsed_data),
       {:ok, processed_data} <- process_with_rollback(validated_data),
       {:ok, _} <- update_audit_trail(processed_data) do
    {:ok, generate_detailed_report(processed_data)}
  else
    {:error, :file_too_large} -> {:error, create_file_size_error()}
    {:error, :invalid_format} -> {:error, create_format_error()}
    {:error, :business_rule_violation, details} -> {:error, create_business_error(details)}
    {:error, reason} -> {:error, create_generic_error(reason)}
  end
end
```

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

## When MVP Requires Complexity

Some MVPs need sophisticated architecture from day one because the complexity **is** the value proposition:

### Justified Complexity Scenarios

**Data Processing Platforms**
- Multi-tier data architecture (staging → production → enrichment)
- Background job coordination for data pipeline
- External API integration for data enrichment
- *Why*: Data quality and processing **is** the core value

**B2B Security/Compliance Applications**
- OAuth with domain restrictions instead of simple auth
- Audit trails and data lineage from day one
- Role-based access controls
- *Why*: Security requirements can't be retrofitted

**Integration-Heavy Products**
- Bidirectional CRM synchronization
- Multiple data format support
- Conflict resolution logic
- *Why*: Integration capability **is** the primary value

**Real-time Collaborative Tools**
- WebSocket connections and state management
- Operational transformation for concurrent editing
- Presence and user awareness
- *Why*: Real-time collaboration **is** the core feature

### When to Override MVP Simplicity Rules

Override the "simplest approach" when:

1. **The complexity IS the core value proposition**
   - Data pipeline architecture for a CDP
   - Real-time features for collaboration tools
   - Advanced algorithms for AI/ML products

2. **Foundation architecture can't be easily changed later**
   - Database schema for data-heavy applications
   - Authentication system for B2B products
   - API design for platform products

3. **User expectations are set by competitive landscape**
   - SSO login in enterprise software
   - Mobile responsiveness in consumer apps
   - Performance benchmarks in developer tools

4. **Regulatory/security requirements mandate complexity**
   - Healthcare data handling (HIPAA)
   - Financial compliance (SOX, PCI)
   - European privacy requirements (GDPR)

### Documenting Complexity Decisions

Use this template for justifying complexity:

```markdown
# Complexity Decision: [Feature Name]

## Decision: Include in MVP (Override Simplicity Rule)

## Justification:
- **Core Value Impact**: [How this complexity delivers core value]
- **Later Cost**: [Cost of adding this later vs now]
- **User Expectation**: [Industry standard or user requirement]
- **Risk of Deferring**: [What breaks if we don't include this]

## Complexity Boundaries:
- **Include**: [Minimum complexity needed]
- **Exclude**: [Advanced features still deferred to roadmap]

## Date**: [YYYY-MM-DD]
## Decided by**: [Name]
```

### Examples: MVP Complexity vs Roadmap

**Data Pipeline MVP**:
- ✅ Three-tier architecture (staging/production/enrichment)
- ✅ Basic background job coordination
- ✅ Essential external API integration
- ❌ Advanced deduplication algorithms (fuzzy matching)
- ❌ Multiple enrichment providers
- ❌ Real-time processing

**B2B Security MVP**:
- ✅ OAuth with domain restrictions
- ✅ Basic audit logging
- ✅ Role-based routes
- ❌ Advanced role management UI
- ❌ Comprehensive audit dashboard
- ❌ SOC 2 compliance features

Remember: Complexity should be **essential** to the core value proposition, not impressive to developers.

### The "While We're At It" Pattern

```markdown
# Starting point: "Users need to upload contact data"

❌ Scope creep sequence:
→ "While we're at it, let's add data validation"
→ "And duplicate detection"  
→ "And intelligent field mapping"
→ "And real-time progress updates"
→ "And email notifications when complete"
→ Never ships

✅ MVP sequence:
→ Upload CSV file
→ Process in background
→ Show results on refresh
→ Ships in 2 days
```

### The "Edge Case Rabbit Hole"

```markdown
# Core feature: Import contact data from CSV

❌ Edge case expansion:
→ "What if the CSV has malformed emails?"
→ "What if names have special characters?"
→ "What if companies have multiple domains?"
→ "What if the file is corrupted?"
→ Spend 2 weeks on edge cases

✅ MVP approach:
→ Handle valid CSV files
→ Show clear error for invalid files
→ Document limitations
→ Ship core functionality
```

## Quality Criteria: "Good Enough" Definitions

### User Interface
- **Good Enough**: Users can complete tasks without confusion
- **Over-Engineering**: Pixel-perfect design with animations

### Error Handling  
- **Good Enough**: Clear error messages for common failures
- **Over-Engineering**: Graceful degradation for every possible failure

### Performance
- **Good Enough**: Works fine with expected load
- **Over-Engineering**: Optimized for 10x expected load

### Data Validation
- **Good Enough**: Prevents obviously bad data
- **Over-Engineering**: Validates every edge case

### Testing
- **Good Enough**: Happy path works, basic error cases covered
- **Over-Engineering**: 100% test coverage including edge cases

## Daily Decision-Making Practices

### Morning Planning Question
*"What am I building today that directly serves the core user need defined in docs/prd/mvp.md?"*

### Afternoon Reality Check  
*"Am I gold-plating something that's already functional?"*

### End-of-Day Review
*"What did I build that's not in mvp.md? Should it be moved to roadmap.md?"*

## Implementation Strategy: Simplest First

### Choose Implementation Approach by Complexity

**Level 1: Static/Synchronous (Preferred for MVP)**
- Form submissions with redirects
- Page refreshes for updated data
- Synchronous processing where possible
- Simple error pages

**Level 2: Dynamic/Asynchronous (Use sparingly)**
- LiveView for truly interactive features
- Background jobs for long-running tasks
- WebSocket updates for essential real-time needs

**Level 3: Advanced (Roadmap only)**
- Real-time collaboration
- Complex state management
- Advanced caching strategies
- Performance optimization

### Example: Progress Indication

```markdown
# Level 1 (MVP): 
Upload form → "Processing..." page → Results page

# Level 2 (Roadmap):
Upload form → Real-time progress bar → Live results

# Level 3 (Future):
Drag-drop → Streaming progress → Live preview → Collaborative editing
```

## Measuring MVP Success

### Week 1: Functionality Validation
- Core user flow works end-to-end
- Users can accomplish primary task
- No blocking bugs in happy path

### Week 2-4: User Feedback Integration
- What's the biggest user complaint?
- Where do users get confused?
- What features are they requesting?

### Month 1+: Usage Patterns
- Feature utilization rates
- User retention metrics
- Support ticket themes

**Key Principle**: Optimize for learning, not perfection.

## Common Anti-Patterns and Solutions

### The "Perfect Foundation" Trap
```markdown
❌ "We need to build the perfect data architecture first"
✅ "We need a working data pipeline first"

❌ "Let's set up comprehensive monitoring before launch"  
✅ "Let's ship with basic error logging"

❌ "We should handle internationalization from day one"
✅ "We should work for our primary users first"
```

### The "Future-Proofing" Trap
```markdown
❌ "This component needs to be reusable across the entire app"
✅ "This component needs to work for this specific page"

❌ "We should design the API for all possible use cases"
✅ "We should design the API for our current use case"
```

## Documentation Discipline

### Feature Decision Log Template

```markdown
# Feature Decision: [Feature Name]

## Decision: MVP / Roadmap / Deferred

## Reasoning:
- **User Impact**: [High/Medium/Low]
- **Implementation Complexity**: [1-2 days / 3-5 days / 1+ week]
- **Blocks core user flow**: [Yes/No]
- **Alternative workaround**: [Description]

## Date: [YYYY-MM-DD]
## Decided by: [Name]
```

### Weekly MVP Boundary Review

Every week, audit current work:
1. List everything being built
2. Check if it's in docs/prd/mvp.md
3. If not, justify or move to roadmap.md
4. Identify any over-engineering

## Key Mantras for MVP Development

1. **"Shipping beats perfection"** - Real user feedback is more valuable than theoretical perfection
2. **"Boring technology wins"** - Proven solutions over exciting new frameworks
3. **"Good enough is a conscious choice"** - Deliberately choose simplicity over completeness
4. **"Users care about outcomes, not implementation"** - Solve their problem with minimal complexity
5. **"Roadmap exists for a reason"** - Defer aggressively, build selectively

## When to Graduate Beyond MVP

Ready to move beyond MVP discipline when:
- ✅ Core user workflows are proven and stable
- ✅ You have real user feedback on priorities  
- ✅ Users are successfully accomplishing their goals
- ✅ The foundation can support iterative improvement

Only then start systematically working through roadmap.md based on actual user needs, not theoretical requirements.

**Remember**: The goal is to validate that you're building something users want, not something perfect. Ship to learn, iterate based on reality.