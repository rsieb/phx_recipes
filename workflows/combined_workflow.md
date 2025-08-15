# Phoenix Combined TDD+MVP Workflow

## MVP Decision Framework
Before coding, ask: "Can users complete core task without this?"
- YES → roadmap.md
- NO → Is it <2 days work? → MVP candidate

Document: `docs/decisions/FEATURE.md`
```
Decision: MVP/Roadmap
Complexity: [1-2 days/3-5 days/1+ week]
Blocks core flow: Y/N
```

## Implementation Rules
1. Controllers > LiveView (MVP default)
2. Simple schemas > Complex relations
3. Basic error handling only
4. No background processing in MVP

## TDD Git Workflow

### Setup
```bash
git checkout -b feature/task-NNN-description
```

### RED: Write ALL Tests First
```elixir
# test/myapp/context_test.exs
test "creates resource" do
  assert {:ok, _} = Context.create_resource(%{field: "value"})
end

# test/myapp_web/controllers/resource_controller_test.exs  
test "POST /resources creates resource", %{conn: conn} do
  conn = post(conn, ~p"/resources", %{resource: %{field: "value"}})
  assert redirected_to(conn) =~ "/resources/"
end
```

Commit: `git commit -m "Add tests for X (failing)"`

### GREEN: Implement Layer by Layer
1. **Schema/Migration** → test → commit
2. **Context functions** → test → commit  
3. **Controller/Routes** → test → commit
4. **Templates** → test → commit

Commit pattern: `git commit -m "Implement X - N tests passing"`

### REFACTOR: Clean & Merge
```bash
mix test --cover
git checkout develop && git pull
git merge --no-ff feature/task-NNN
git push && git branch -d feature/task-NNN
```

## Phoenix Patterns

### Context (Bottom Layer)
```elixir
def create_resource(attrs) do
  %Resource{}
  |> Resource.changeset(attrs)
  |> Repo.insert()
end

def list_resources do
  Repo.all(Resource)
end

def get_resource!(id) do
  Repo.get!(Resource, id)
end
```

### Controller (Top Layer)
```elixir
def index(conn, _params) do
  resources = Context.list_resources()
  render(conn, :index, resources: resources)
end

def create(conn, %{"resource" => params}) do
  case Context.create_resource(params) do
    {:ok, resource} ->
      conn
      |> put_flash(:info, "Resource created successfully.")
      |> redirect(to: ~p"/resources/#{resource}")
    {:error, changeset} ->
      render(conn, :new, changeset: changeset)
  end
end
```

### Simple Schema
```elixir
schema "resources" do
  field :name, :string
  field :status, :string, default: "active"
  timestamps()
end

def changeset(resource, attrs) do
  resource
  |> cast(attrs, [:name, :status])
  |> validate_required([:name])
end
```

## Quick Reference

**Branch naming**: `feature/task-NNN-description`
**Test first**: Always commit failing tests before implementation
**MVP test**: If it works with page reload, use controller
**Complexity limit**: 2 days max or break it down

## Deferred to Roadmap
- Real-time updates → Use controllers + refresh
- Advanced validations → Basic presence/format only
- Bulk operations → Single record workflow  
- Email notifications → Flash messages
- Complex UI → Simple forms
- Background jobs → Synchronous processing
- External APIs → Manual data entry

## Testing Commands
```bash
mix test                    # Run all tests
mix test --failed          # Run only failed tests
mix test test/path:42      # Run specific test
mix test.watch             # Continuous testing
```

Remember: Ship working software > Perfect architecture

## Phase-Based Task Management with Tags

### Tag Strategy for Product Lifecycle

Use taskmaster tags to organize tasks by development phase, not just features:

```bash
# Core phase tags
mvp/              # Must-have features for launch
alpha/            # Internal testing features  
beta/             # Public beta additions
v1.0/             # First stable release
roadmap/          # Future features & ideas

# Supporting tags
backlog/          # Nice-to-haves, tech debt
experiments/      # R&D, proof of concepts
customer-requests/ # Feature requests from users
tech-debt/        # Refactoring tasks
performance/      # Optimization tasks
```

### Workflow Example

```bash
# Start with MVP tasks only
task-master create-tag mvp
task-master parse-prd mvp-requirements.txt --tag mvp

# View only MVP tasks
task-master list --tag mvp

# As MVP nears completion, prepare next phase
task-master create-tag alpha
task-master copy-tag mvp alpha  # Carry over incomplete tasks

# Move specific future tasks to roadmap
task-master create-tag roadmap
task-master move --from=15 --to=25 --tag roadmap
```

### Benefits of Phase-Based Tags

1. **Focus**: MVP tag keeps only critical-path tasks visible
2. **Progression**: Natural task flow from mvp → alpha → beta
3. **Parking Lot**: Roadmap tag prevents "someday" tasks from cluttering current work
4. **Scope Control**: Clear boundaries prevent feature creep
5. **Context Isolation**: Each phase has its own priority order

### Suggested Task Progression

```
mvp         → "Ship or die" features only
alpha       → MVP + critical fixes + initial feedback
beta        → Alpha + UX polish + performance  
v1.0        → Production-ready + documentation
v1.1        → Quick wins post-launch
roadmap     → Everything else (organized by theme)
```

### Branch Naming with Phase Tags

Combine phase tags with task numbers in branch names:

```bash
# Branch patterns
git checkout -b mvp/task-10-user-auth
git checkout -b alpha/task-45-api-rate-limiting
git checkout -b roadmap/task-99-ml-recommendations
```

This turns tags into a **product lifecycle management system** where each phase has isolated context and priorities.