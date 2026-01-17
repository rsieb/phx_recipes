# Testing Pyramid Setup for Phoenix LiveView Projects

## Overview

This recipe establishes a complete testing strategy from unit tests through manual UAT, ensuring each layer of the testing pyramid serves its distinct purpose without overlap or confusion.

## Testing Hierarchy

```
        👤 Manual UAT (Human validation)
       /
      /   🌐 E2E Tests (Browser automation - optional)
     /   /
    /   /    🔗 Integration Tests (LiveView/Context)
   /   /    /
  /   /    /     🧪 Unit Tests (Functions/Schemas)
 /   /    /     /
└───┴────┴─────┘
```

## Phase 1: Verify Foundation (Unit + Integration Tests)

**Purpose:** Ensure basic automated tests are working

### Steps

1. **Check test suite health:**
   ```bash
   mix test
   ```

2. **Review coverage:**
   ```bash
   mix coveralls
   ```

3. **Identify gaps:**
   - Failing tests blocking progress
   - Missing coverage for core functionality
   - Broken test helpers or fixtures

4. **Fix critical failures:**
   - Address any blocking test failures
   - Update deprecated test patterns
   - Ensure fixtures work correctly

**Success Criteria:**
- ✅ `mix test` runs green
- ✅ Coverage baseline documented
- ✅ No critical test infrastructure issues

## Phase 2: LiveView Integration Testing

**Purpose:** Test user interactions without browser overhead

### Key Concepts

- **Speed:** LiveView tests run in milliseconds
- **Scope:** Test user interactions through LiveView lifecycle
- **Sufficient:** These ARE your integration/functional tests
- **Not UAT:** Automated, not human validation

### Test Structure

```elixir
# test/middling_web/live/some_live_test.exs
defmodule MiddlingWeb.SomeLiveTest do
  use MiddlingWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "user flow" do
    setup do
      user = confirmed_user_fixture(%{is_onboarded: true})
      %{user: user}
    end

    test "user can complete action", %{conn: conn, user: user} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user)  # ← Bypass login UI
        |> live(~p"/app/some-page")

      # Test the actual functionality
      lv
      |> form("#some-form", some_data: %{field: "value"})
      |> render_submit()

      assert has_element?(lv, "#success-message")
    end
  end
end
```

### Available Helpers (ConnCase)

```elixir
# Quick session login
log_in_user(conn, user)

# Create user + org + log in
register_and_sign_in_user(conn)

# Admin user + org + log in
register_and_sign_in_admin(conn)

# Create test users
confirmed_user_fixture(%{optional: "attrs"})
admin_fixture(%{optional: "attrs"})
```

### Steps

1. **Review existing LiveView tests:**
   ```bash
   find test -name "*_live_test.exs" -type f
   ```

2. **Ensure consistent helper usage:**
   - All tests use `log_in_user(conn, user)`
   - No manual login form submissions in LiveView tests
   - Fixtures create users with known credentials

3. **Add missing tests for critical flows:**
   - Main user journeys (signup → action → success)
   - Form submissions and validations
   - Real-time updates and interactions
   - Error handling paths

4. **Verify performance:**
   ```bash
   mix test --trace  # Should show millisecond execution
   ```

**Success Criteria:**
- ✅ All critical user flows have LiveView test coverage
- ✅ Tests run fast (<1s each)
- ✅ No manual login flows in LiveView tests

## Phase 3: E2E Safety Net (Wallaby - Optional)

**Purpose:** Catch issues LiveView tests miss (JavaScript, CSS, timing)

### When to Use Wallaby

✅ **Use Wallaby if:**
- Heavy JavaScript interactions (charts, editors, etc.)
- CSS/visual regressions matter
- Third-party integrations need browser testing
- Compliance requires real browser validation

❌ **Skip Wallaby if:**
- Minimal JavaScript (AlpineJS for simple interactions)
- LiveView handles most interactivity
- Team velocity more important than comprehensive E2E
- You can manually test critical paths easily

### Wallaby Structure

```elixir
# test/wallaby/critical_flow_test.exs
defmodule Middling.CriticalFlowTest do
  use MiddlingWeb.WallabyCase
  import Wallaby.Browser

  @tag :wallaby
  test "complete critical user journey", %{session: session} do
    user = confirmed_user_fixture()

    session
    |> log_in(user)  # ← Use WallabyCase helper
    |> visit(~p"/app/proposals")
    |> click(button("New Proposal"))
    |> fill_in(text_field("Title"), with: "Test Proposal")
    |> click(button("Submit"))
    |> assert_has(css("#success-notification"))
  end
end
```

### Available Helpers (WallabyCase)

```elixir
# Browser-based login (fills form automatically)
log_in(session, user)

# Create fresh browser session
new_session()
```

### Steps

1. **Verify Wallaby setup:**
   ```bash
   mix wallaby
   ```

2. **Fix any import/helper issues:**
   - Ensure WallabyCase helpers are available
   - Update tests using local login functions
   - Add missing Wallaby imports if needed

3. **Choose 2-3 critical paths for E2E:**
   - New user signup → first meaningful action
   - Core value proposition flow (end-to-end)
   - Payment/checkout flow (if applicable)

4. **Keep E2E suite small:**
   - Max 5-10 E2E tests total
   - Only test what LiveView can't catch
   - Focus on integration between systems

**Success Criteria:**
- ✅ `mix wallaby` runs successfully
- ✅ 2-3 critical paths have E2E coverage
- ✅ E2E tests catch different issues than LiveView tests

**Decision Point:** Evaluate if Wallaby adds value before investing heavily.

## Phase 4: Manual UAT Workflow

**Purpose:** Enable rapid manual testing without friction

### The Problem

Manual testing shouldn't require:
- Filling login forms repeatedly
- Remembering test credentials
- Resetting state between tests
- Complex setup for each test session

### Solution Options

#### Option A: Dev-Only Auto-Login Route (Recommended)

```elixir
# lib/middling_web/router.ex
if Mix.env() == :dev do
  scope "/dev" do
    pipe_through :browser

    get "/login/:user_id", MiddlingWeb.DevController, :auto_login
  end
end

# lib/middling_web/controllers/dev_controller.ex
defmodule MiddlingWeb.DevController do
  use MiddlingWeb, :controller

  def auto_login(conn, %{"user_id" => user_id}) do
    user = Middling.Accounts.get_user!(user_id)

    conn
    |> Middling.Accounts.log_in_user(user)
    |> redirect(to: ~p"/app")
  end
end
```

**Usage:**
```bash
# Visit http://localhost:4000/dev/login/1
# Instantly logged in as user ID 1
```

#### Option B: Extended Session Timeout

```elixir
# config/dev.exs
config :middling, MiddlingWeb.Endpoint,
  live_view: [
    signing_salt: "...",
    session_timeout: :timer.hours(8)  # ← Stay logged in for 8 hours
  ]
```

#### Option C: Well-Known Test Account

```elixir
# priv/repo/seeds.exs
if Mix.env() == :dev do
  {:ok, _user} = Middling.Accounts.register_user(%{
    email: "test@example.com",
    password: "password",
    confirmed_at: DateTime.utc_now()
  })

  IO.puts("\n✅ Test account: test@example.com / password\n")
end
```

**Usage:**
```bash
mix seed
# Use test@example.com / password
```

### Implementation Steps

1. **Choose UAT workflow solution:**
   - Evaluate options based on team preferences
   - Consider security vs convenience trade-offs
   - Can implement multiple solutions (auto-login + long sessions)

2. **Implement chosen solution:**
   - Add dev-only routes/configuration
   - Test that it works as expected
   - Document credentials or URLs

3. **Create UAT checklist template:**
   ```markdown
   ## UAT Checklist: [Feature Name]

   **Setup:**
   - [ ] Log in as test user
   - [ ] Navigate to feature

   **Happy Path:**
   - [ ] Primary action works
   - [ ] Success feedback clear
   - [ ] UI intuitive

   **Edge Cases:**
   - [ ] Error handling clear
   - [ ] Validation messages helpful

   **Polish:**
   - [ ] Responsive on mobile
   - [ ] Loading states smooth
   - [ ] Accessible (keyboard nav)
   ```

4. **Document workflow:**
   - Add to project README or CLAUDE.md
   - Include in onboarding docs
   - Share with team members

**Success Criteria:**
- ✅ Can start manual testing in <30 seconds
- ✅ No login friction during UAT sessions
- ✅ UAT checklist template exists
- ✅ Workflow documented for team

## Phase 5: Documentation

**Purpose:** Capture testing strategy for future reference

### Create Testing Strategy Doc

```markdown
# docs/testing-strategy.md

## Testing Pyramid

### Unit Tests (mix test test/middling/)
- Test individual functions and schemas
- Run on every file save
- Should be fast (<100ms total)

### Integration Tests (mix test test/middling_web/)
- Test LiveView user interactions
- Use log_in_user(conn, user) helper
- Verify complete user flows
- Run before commits

### E2E Tests (mix wallaby) - Optional
- Test 2-3 critical paths only
- Catch JavaScript/CSS issues
- Run before deploys

### Manual UAT
- Human validation of UX/design
- Use dev auto-login for speed
- Follow UAT checklist templates
- Required before shipping features

## Quick Reference

# Run all automated tests
mix test

# Run with coverage
mix coveralls

# Run E2E tests only
mix wallaby

# Manual testing
Visit: http://localhost:4000/dev/login/1

## Test Helpers

### ConnCase (LiveView/Controller Tests)
- log_in_user(conn, user)
- register_and_sign_in_user(conn)
- confirmed_user_fixture()

### WallabyCase (Browser Tests)
- log_in(session, user)
- new_session()
```

### Update Project Documentation

1. **Add testing section to CLAUDE.md:**
   ```markdown
   ## Testing

   See docs/testing-strategy.md for complete testing approach.

   Quick commands:
   - `mix test` - Run all automated tests
   - `mix wallaby` - Run E2E tests (if applicable)
   - Dev login: http://localhost:4000/dev/login/1
   ```

2. **Update README if needed:**
   - Add testing section with key commands
   - Link to full testing strategy doc

**Success Criteria:**
- ✅ Testing strategy documented
- ✅ Test commands in CLAUDE.md
- ✅ Team can reference testing approach

## Common Pitfalls

### ❌ Confusing Automated Tests with UAT
- **Problem:** Treating automated tests as UX validation
- **Solution:** Automated = "Does it work?", UAT = "Is it usable?"

### ❌ Over-investing in E2E Tests
- **Problem:** Slow, brittle Wallaby tests for everything
- **Solution:** LiveView tests sufficient for most flows

### ❌ Login Friction in Manual Testing
- **Problem:** Typing credentials 50 times per day
- **Solution:** Dev auto-login or extended sessions

### ❌ No UAT Before Shipping
- **Problem:** Perfect automated tests, terrible UX
- **Solution:** Always manually test before deploy

### ❌ Skipping Test Documentation
- **Problem:** Team doesn't know testing approach
- **Solution:** Document strategy and helpers

## Success Metrics

- **Unit/Integration:** >80% code coverage
- **LiveView Tests:** All critical flows covered
- **E2E Tests:** 0-5 tests (only if needed)
- **Manual UAT:** <30s to start testing
- **Test Speed:** Full suite <30 seconds
- **Team Knowledge:** Everyone knows which test to write when

## Maintenance

### Monthly Review
- Prune obsolete tests
- Update helpers as needed
- Review coverage gaps
- Simplify complex tests

### Before Major Releases
- Run full test suite
- Execute manual UAT checklist
- Verify E2E tests (if applicable)
- Update test documentation

## Template Checklist

Use this checklist when setting up testing for a new Phoenix LiveView project:

- [ ] Phase 1: Verify `mix test` runs green
- [ ] Phase 2: Add LiveView integration tests
- [ ] Phase 2: Ensure login helpers used consistently
- [ ] Phase 3: Evaluate need for Wallaby E2E
- [ ] Phase 3: If yes, add 2-3 critical E2E tests
- [ ] Phase 4: Implement dev UAT workflow (auto-login or long session)
- [ ] Phase 4: Create UAT checklist template
- [ ] Phase 5: Document testing strategy
- [ ] Phase 5: Update CLAUDE.md with test commands
- [ ] Share testing approach with team

## Related Resources

- [Phoenix Testing Guide](https://hexdocs.pm/phoenix/testing.html)
- [Phoenix LiveView Testing](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)
- [Wallaby Documentation](https://hexdocs.pm/wallaby/)
- [ExUnit Best Practices](https://hexdocs.pm/ex_unit/)
