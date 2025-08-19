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

### TRUE TDD: One Test at a Time

#### 1. RED: Write ONE Failing Test
```elixir
# test/myapp/context_test.exs
test "creates resource with valid attributes" do
  assert {:ok, resource} = Context.create_resource(%{name: "Test"})
  assert resource.name == "Test"
end
```
Run: `mix test` (should fail)
Commit: `git commit -m "Add test for create_resource (RED)"`

#### 2. GREEN: Write Minimal Code to Pass
```elixir
# Just enough to make the test pass - nothing more!
def create_resource(attrs) do
  {:ok, %Resource{name: attrs[:name]}}
end
```
Run: `mix test` (should pass)
Commit: `git commit -m "Implement create_resource - 1 test passing (GREEN)"`

#### 3. REFACTOR: Clean Up (if needed)
Only if code needs improvement while tests stay green
Commit: `git commit -m "Refactor: improve create_resource"`

#### 4. REPEAT: Next Test
```elixir
# NOW write the second test
test "validates required fields" do
  assert {:error, changeset} = Context.create_resource(%{})
  assert "can't be blank" in errors_on(changeset).name
end
```
Run: `mix test` (should fail)
Commit: `git commit -m "Add validation test (RED)"`

Then implement, commit green, refactor if needed...

### Important TDD Rules
- **NEVER** write multiple tests before implementing
- **NEVER** implement features without a failing test
- **NEVER** write code beyond what the current test requires
- Each cycle should take 5-15 minutes max
- Commit after EVERY Red-Green-Refactor cycle

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