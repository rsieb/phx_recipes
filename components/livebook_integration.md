# Phoenix Components & Livebook Integration Recipe


### Objective
Integrate Livebook into the Phoenix app to provide interactive documentation with live data access for the contacts table.

### Requirements

#### 1. Livebook Setup
- Add Livebook dependency to Phoenix app
- Configure Livebook to run embedded within the Phoenix application
- Set up routing to access Livebook at `/docs/livebook` or similar path

#### 2. Database Access
- Create a read-only database connection/repo module
- Implement query timeouts (max 30 seconds)
- Limit result sets to maximum 1000 records per query
- Ensure all database operations are wrapped in read-only transactions

#### 3. Contact Table Notebook
- Create a single notebook file: `contacts_documentation.livemd`
- Structure the notebook with:
  - **Introduction section**: Explain what the contacts table contains
  - **Schema overview**: Display all column names and types
  - **Sample queries section**: Pre-written examples users can run
  - **Interactive query cell**: Where users can write their own queries

#### 4. Security Constraints
- Only expose `SELECT` operations (no INSERT, UPDATE, DELETE)
- Restrict access to contacts table only
- No access to sensitive tables (users, sessions, etc.)
- Implement basic authentication if not already present

#### 5. Sample Functionality
The notebook should demonstrate:
- `Contacts |> limit(10) |> Repo.all()` - Basic record fetching
- Filtering by common fields (name, email, status)
- Counting records with various conditions
- Showing table schema with `describe(Contacts)`

#### 6. Technical Implementation
- Use existing `MyApp.Contacts` context if available
- Create `MyApp.ReadOnlyRepo` for safe database access
- Set up proper error handling for malformed queries
- Display results in readable table format using Kino.DataTable

#### Success Criteria
- Users can access the notebook through the main Phoenix app
- Users can execute read-only queries against contacts table
- All queries are properly sandboxed and secured
- Documentation is clear enough for non-technical users to understand basic querying

#### Out of Scope for POC
- Multiple tables
- Complex joins
- User authentication/authorization beyond basic access
- Query history or saving functionality
- Advanced visualizations
