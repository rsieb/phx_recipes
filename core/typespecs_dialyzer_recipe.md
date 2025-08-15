# Typespecs and Dialyzer Recipe for Phoenix MVP

## Philosophy: Pragmatic Type Safety

In an MVP, typespecs and Dialyzer should **prevent expensive bugs** without slowing down shipping. This recipe follows the 80/20 rule: add specs to the 20% of code that handles 80% of your business value.

## Where to Use Typespecs

### 1. Core Business Logic Functions
Your main domain functions that handle money, user data, or critical workflows. These will be reused and modified frequently.

```elixir
# ✅ DO: Add specs to scoring logic (bugs here affect all users)
@spec calculate_persona_score(Contact.t()) :: 
  %{persona_score: float(), breakdown: map()}
def calculate_persona_score(contact) do
  # This logic is complex and central to the product
end

# ✅ DO: Add specs to billing/payment functions
@spec calculate_pricing(User.t(), Product.t(), map()) :: 
  {:ok, Money.t()} | {:error, atom()}
def calculate_pricing(user, product, options) do
  # Bugs here cost money
end
```

### 2. Public API Modules
Any module that other developers will call. Context modules, API boundaries, and reusable utilities.

```elixir
# ✅ DO: Context module public functions
defmodule MyApp.Accounts do
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    # Clear contract for other developers
  end
  
  @spec get_user!(integer()) :: User.t() | no_return()
  def get_user!(id) do
    # Explicit about raising vs returning nil
  end
end
```

### 3. Data Transformation Functions
Functions that transform between different data shapes, especially when integrating with external APIs.

```elixir
# ✅ DO: API integration mappers
@spec apollo_response_to_contact(map()) :: {:ok, map()} | {:error, :invalid_data}
def apollo_response_to_contact(apollo_data) do
  # Prevents runtime errors from API changes
end
```

## Where to Skip Typespecs

### 1. Controllers and Views
Phoenix handles most of the type safety here. Focus on shipping features.

```elixir
# ❌ SKIP: Controller actions
def index(conn, params) do
  # Phoenix already ensures conn is a Plug.Conn
  contacts = Contacts.list_contacts(params)
  render(conn, :index, contacts: contacts)
end
```

### 2. LiveView Callbacks
The LiveView behaviour already provides type checking.

```elixir
# ❌ SKIP: LiveView handle_event
def handle_event("save", %{"contact" => contact_params}, socket) do
  # LiveView ensures the callback signature
end
```

### 3. One-off Migrations or Mix Tasks
Temporary code doesn't need the overhead.

```elixir
# ❌ SKIP: Data migration tasks
defmodule Mix.Tasks.MyApp.MigrateOldData do
  def run(_args) do
    # This runs once and gets deleted
  end
end
```

### 4. Simple Pipe Transformations
When the function is self-explanatory and unlikely to change.

```elixir
# ❌ SKIP: Simple, obvious transformations
defp normalize_email(email) do
  String.downcase(String.trim(email))
end
```

## Dialyzer Strategy for MVP

### Initial Setup

1. **Add to `mix.exs`:**
```elixir
def project do
  [
    dialyzer: [
      plt_add_apps: [:mix, :ex_unit],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [
        :unmatched_returns,
        :error_handling,
        # Skip these for MVP:
        # :underspecs,
        # :overspecs,
        # :specdiffs
      ]
    ]
  ]
end
```

2. **Create `.dialyzer_ignore.exs`:**
```elixir
[
  # Ignore warnings from generated code
  {"lib/my_app_web/telemetry.ex"},
  {"lib/my_app_web/controllers/page_html.ex"},
  
  # Temporarily ignore complex modules until stable
  {"lib/my_app/legacy_importer.ex"},
  
  # Ignore specific warning patterns
  ~r/Function .* has no local return/
]
```

### When to Run Dialyzer

**DON'T run in development** - It's too slow for MVP pace.

```bash
# ❌ Not in your daily workflow
mix dialyzer

# ✅ Only in CI/CD
# .github/workflows/ci.yml or similar
- name: Run Dialyzer
  run: mix dialyzer --format github
  continue-on-error: true  # Don't block deploys initially
```

### Progressive Adoption

1. **Month 1-2:** No Dialyzer, just critical typespecs
2. **Month 3-4:** Run Dialyzer in CI, ignore most warnings
3. **Month 5-6:** Start fixing warnings in core modules
4. **Post-MVP:** Comprehensive type coverage

## Practical Examples for Common Phoenix Patterns

### Context Module Pattern
```elixir
defmodule MyApp.Contacts do
  # ✅ DO: Spec the main CRUD functions
  @spec list_contacts(map()) :: [Contact.t()]
  @spec get_contact!(integer()) :: Contact.t() | no_return()
  @spec create_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  
  # ❌ SKIP: Internal helper functions
  defp preload_associations(contact) do
    # Unless this is called from multiple places
  end
end
```

### Worker/Job Pattern
```elixir
defmodule MyApp.Workers.EmailWorker do
  use Oban.Worker
  
  # ✅ DO: Spec the perform function
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    # Critical async work needs type safety
  end
end
```

### Schema Modules
```elixir
defmodule MyApp.Contacts.Contact do
  use Ecto.Schema
  
  # ✅ DO: Custom type definitions
  @type t :: %__MODULE__{
    id: integer() | nil,
    name: String.t(),
    email: String.t() | nil,
    persona_score: float() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }
  
  # ❌ SKIP: Changeset functions (Ecto handles these well)
  def changeset(contact, attrs) do
    # Ecto's built-in type checking is sufficient
  end
end
```

## The 80/20 Rule in Practice

### High-Value Specs (20% that matter)
- Payment processing
- User authentication
- Core business logic (scoring, matching, recommendations)
- Data import/export
- API integrations
- Report generation

### Low-Value Specs (80% to skip)
- View helpers
- Simple CRUD operations
- Form validations
- Background job scheduling
- Admin interfaces
- Development tools

## Common Pitfalls to Avoid

1. **Don't spec everything** - You'll slow down and the specs will become outdated
2. **Don't fix all Dialyzer warnings** - Some are false positives or not worth the complexity
3. **Don't use complex type gymnastics** - If the spec is harder to read than the code, skip it
4. **Don't block deploys on Dialyzer** - Use `continue-on-error` in CI initially

## When to Increase Type Coverage

Add more typespecs when:
- You onboard a second developer
- You have paying customers and stability matters
- You're refactoring core business logic
- You keep hitting the same category of bugs
- You're building a library for others to use

## Example: Applying to Your Scoring System

```elixir
# HIGH VALUE - Spec this (core business logic)
@spec calculate_persona_score(Contact.t()) :: 
  %{persona_score: float(), breakdown: map()}
def calculate_persona_score(contact) do
  # ...
end

# MEDIUM VALUE - Maybe spec this (public API)
@spec list_contacts_with_scoring_details(map(), map()) :: 
  {[map()], map()}
def list_contacts_with_scoring_details(filters, opts) do
  # ...
end

# LOW VALUE - Skip this (view helper)
def format_score_percentage(score) do
  "#{round(score * 100)}%"
end
```

## Summary

**MVP Goal:** Prevent expensive bugs in critical paths while maintaining development velocity.

**Not MVP Goal:** 100% type coverage or zero Dialyzer warnings.

Remember: **Perfection is the enemy of shipping.** Add types where they prevent real bugs that would hurt users or cost money. Skip them everywhere else until you've found product-market fit.