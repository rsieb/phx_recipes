# Algorithm Testing with Predictable Data Recipe

## Problem

Testing algorithms against live data gives you vague feedback: “this seems about right” or “this looks wrong.” You need deterministic tests with known expected outcomes to verify your algorithm actually works correctly.

## Solution: Controlled Test Data

Create test data specifically designed to produce known results. If your algorithm should identify 60% of records as “qualified,” create exactly 10 records where 6 match and 4 don’t.

## Factory Setup with ExMachina

### 1. Add ExMachina to Test Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:ex_machina, "~> 2.7", only: :test}
  ]
end
```

### 2. Create Factory Module

```elixir
# test/support/factory.ex
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def person_factory do
    %MyApp.People.Person{
      name: sequence("Person"),
      email: sequence(:email, &"person#{&1}@example.com"),
      age: 30,
      score: 50,
      active: true
    }
  end

  # Derived factories for specific test cases
  def qualified_person_factory do
    struct!(
      person_factory(),
      %{
        score: 75,  # Above threshold
        active: true
      }
    )
  end

  def unqualified_person_factory do
    struct!(
      person_factory(),
      %{
        score: 25,  # Below threshold
        active: true
      }
    )
  end
end
```

## Testing an Algorithm with Known Outcomes

### Bad Practice: Testing Against Unknown Data

```elixir
# ❌ BAD: Don't know what the result should be
test "algorithm finds qualified people" do
  # Insert some random people
  people = insert_list(10, :person)

  results = MyApp.Algorithms.find_qualified(people)

  # Vague assertions - is this right?
  assert length(results) > 0
  assert length(results) < 10
  # "Seems about right" is not a test!
end
```

### Good Practice: Deterministic Test Data

```elixir
# ✅ GOOD: Know exactly what should happen
defmodule MyApp.AlgorithmsTest do
  use MyApp.DataCase
  import MyApp.Factory

  alias MyApp.Algorithms

  describe "find_qualified/1" do
    test "identifies exactly 60% as qualified with threshold of 50" do
      # Create deterministic test set: 6 qualified, 4 unqualified
      qualified = [
        insert(:person, score: 51, active: true),   # Just above threshold
        insert(:person, score: 60, active: true),
        insert(:person, score: 75, active: true),
        insert(:person, score: 90, active: true),
        insert(:person, score: 99, active: true),   # Well above threshold
        insert(:person, score: 50, active: true)    # Exactly at threshold
      ]

      unqualified = [
        insert(:person, score: 49, active: true),   # Just below threshold
        insert(:person, score: 40, active: true),
        insert(:person, score: 25, active: true),
        insert(:person, score: 0, active: true)     # Well below threshold
      ]

      all_people = qualified ++ unqualified
      results = Algorithms.find_qualified(all_people)

      # Exact assertions
      assert length(results) == 6
      assert Enum.sort(results) == Enum.sort(qualified)

      # Verify each qualified person is included
      for person <- qualified do
        assert person in results
      end

      # Verify no unqualified person is included
      for person <- unqualified do
        refute person in results
      end
    end

    test "handles edge cases correctly" do
      edge_cases = [
        insert(:person, score: 50, active: true),    # Exactly at threshold
        insert(:person, score: 50, active: false),   # At threshold but inactive
        insert(:person, score: nil, active: true),   # Missing score
        insert(:person, score: 100, active: false)   # High score but inactive
      ]

      results = Algorithms.find_qualified(edge_cases)

      # Only the first one should qualify
      assert length(results) == 1
      assert hd(results).score == 50
      assert hd(results).active == true
    end
  end
end
```

## Testing Ranking/Scoring Algorithms

```elixir
defmodule MyApp.ScoringTest do
  use MyApp.DataCase
  import MyApp.Factory

  describe "calculate_match_score/2" do
    setup do
      target_company = insert(:company,
        industry: "SaaS",
        size: "50-100",
        location: "San Francisco"
      )

      {:ok, target: target_company}
    end

    test "scores exact match as 100%", %{target: target} do
      perfect_match = insert(:company,
        industry: "SaaS",
        size: "50-100",
        location: "San Francisco"
      )

      score = Algorithms.calculate_match_score(perfect_match, target)
      assert score == 100.0
    end

    test "scores based on matching criteria", %{target: target} do
      test_cases = [
        {insert(:company, industry: "SaaS", size: "50-100", location: "New York"), 66.7},
        {insert(:company, industry: "SaaS", size: "10-50", location: "San Francisco"), 66.7},
        {insert(:company, industry: "Fintech", size: "50-100", location: "San Francisco"), 66.7},
        {insert(:company, industry: "SaaS", size: "10-50", location: "New York"), 33.3},
        {insert(:company, industry: "Fintech", size: "200-500", location: "Boston"), 0.0}
      ]

      for {company, expected_score} <- test_cases do
        score = Algorithms.calculate_match_score(company, target)
        assert_in_delta score, expected_score, 0.1,
          "Expected #{inspect(company)} to score #{expected_score}, got #{score}"
      end
    end
  end
end
```

## Making Tests Deterministic

### Use Fixed Seeds for Random Data

```elixir
# ❌ BAD: Non-deterministic
test "random sampling" do
  people = insert_list(100, :person)
  sample = Algorithms.random_sample(people, 10)
  assert length(sample) == 10
  # Different every run!
end

# ✅ GOOD: Deterministic with seed
test "random sampling with seed" do
  :rand.seed(:exsss, {123, 456, 789})  # Fixed seed

  people = insert_list(100, :person)
  sample = Algorithms.random_sample(people, 10)

  assert length(sample) == 10
  # Verify specific IDs that should always be selected with this seed
  assert Enum.map(sample, & &1.id) == [1, 15, 23, 34, 45, 56, 67, 78, 89, 91]
end
```

### Avoid Time-Dependent Tests

```elixir
# ❌ BAD: Depends on current time
test "finds recent records" do
  old = insert(:person, inserted_at: Timex.shift(Timex.now(), days: -31))
  new = insert(:person)  # Uses current time

  recent = Algorithms.find_recent_records()
  assert new in recent
  refute old in recent
end

# ✅ GOOD: Use fixed timestamps
test "finds records from last 30 days" do
  base_time = ~U[2024-01-15 12:00:00Z]

  old = insert(:person, inserted_at: ~U[2023-12-01 12:00:00Z])
  borderline = insert(:person, inserted_at: ~U[2023-12-16 12:00:00Z])
  recent = insert(:person, inserted_at: ~U[2024-01-10 12:00:00Z])

  # Mock current time if needed
  results = Algorithms.find_recent_records(as_of: base_time)

  assert recent in results
  assert borderline in results  # Exactly 30 days ago
  refute old in results
end
```

## Factory Best Practices

### Build vs Insert

```elixir
# Use build when you don't need database persistence
test "validation logic" do
  # No database hit
  person = build(:person, score: -1)
  changeset = Person.changeset(person, %{})
  refute changeset.valid?
end

# Use insert when testing queries or associations
test "finding by criteria" do
  # Needs to be in database
  person = insert(:person, score: 75)
  result = Repo.get_by(Person, score: 75)
  assert result.id == person.id
end
```

### Traits for Variations

```elixir
# test/support/factory.ex
def person_factory do
  %Person{
    name: sequence("Person"),
    status: "pending",
    score: 50
  }
end

# Use traits for common variations
def person_factory(attrs) do
  person = %Person{
    name: sequence("Person"),
    status: "pending",
    score: 50
  }

  person
  |> apply_trait(attrs)
end

defp apply_trait(record, :qualified) do
  %{record | score: 75, status: "active"}
end

defp apply_trait(record, :rejected) do
  %{record | score: 25, status: "rejected"}
end

# Usage in tests
test "processes qualified people" do
  qualified = insert_list(5, :person, :qualified)
  rejected = insert_list(5, :person, :rejected)

  results = Algorithms.process_active()
  assert length(results) == 5
end
```

## Testing Distribution Algorithms

```elixir
test "distributes leads evenly among sales reps" do
  # Create exactly 3 reps
  reps = insert_list(3, :sales_rep)

  # Create exactly 9 leads for even distribution
  leads = insert_list(9, :lead)

  assignments = Algorithms.distribute_leads(leads, reps)

  # Each rep should get exactly 3 leads
  for rep <- reps do
    rep_assignments = Enum.filter(assignments, & &1.rep_id == rep.id)
    assert length(rep_assignments) == 3
  end

  # All leads should be assigned
  assert length(assignments) == 9
end

test "handles uneven distribution with remainder" do
  reps = insert_list(3, :sales_rep)
  leads = insert_list(10, :lead)  # 10 doesn't divide evenly by 3

  assignments = Algorithms.distribute_leads(leads, reps)

  rep_counts =
    assignments
    |> Enum.group_by(& &1.rep_id)
    |> Enum.map(fn {_id, assigns} -> length(assigns) end)
    |> Enum.sort()

  # Should be [3, 3, 4] - two get 3, one gets 4
  assert rep_counts == [3, 3, 4]
end
```

## Quick Reference

```elixir
# Factory setup
use MyApp.DataCase
import MyApp.Factory

# Create test data with known properties
good_data = insert_list(6, :person, score: 75)
bad_data = insert_list(4, :person, score: 25)

# Test exact outcomes
assert Algorithm.process(good_data ++ bad_data) == good_data

# Make random tests deterministic
:rand.seed(:exsss, {123, 456, 789})

# Use fixed times
base_time = ~U[2024-01-15 12:00:00Z]

# Build vs Insert
build(:person)    # No database
insert(:person)   # In database
```

## Key Principles

1. **Know your expected outcomes** - Design test data to produce specific results
1. **Test edge cases explicitly** - At threshold, just above, just below
1. **Make tests repeatable** - Use fixed seeds and timestamps
1. **Test the algorithm, not the randomness** - Control random elements
1. **Use minimal data sets** - 10 records is often enough to prove the algorithm

## Anti-Patterns to Avoid

- Testing with production data dumps
- Assertions like “should be more than 0”
- Time-dependent tests without mocking
- Random data without fixed seeds
- Testing that “something happens” vs “the right thing happens”

Remember: If you can’t predict what your test should output, you’re not testing your algorithm - you’re just running it.​​​​​​​​​​​​​​​​
