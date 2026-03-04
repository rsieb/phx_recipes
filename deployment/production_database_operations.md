# Production Database Operations

## Connecting to Production

The app runs on Fly.io as `middling-ai`. The BEAM node is already running with the full app started.

### Interactive console (preferred for ad-hoc work)

```bash
flyctl ssh console -a middling-ai -C '/app/bin/middling remote'
```

This connects to the **running BEAM node** via IEx. Repo is already started, all modules are loaded.

```elixir
import Ecto.Query
Middling.Repo.all(from p in Middling.Proposals.Proposal, select: {p.id, p.title})
```

### Non-interactive one-liner (finicky, prefer interactive)

```bash
flyctl ssh console -a middling-ai -C 'echo "import Ecto.Query; Middling.Repo.all(...)" | /app/bin/middling remote'
```

### eval vs remote

| Command | Connects to | Repo available? | Use for |
|---------|-------------|-----------------|---------|
| `remote` | Running BEAM node | Yes (already started) | Ad-hoc queries, data fixes, debugging |
| `eval` | Fresh process (no app) | No | Migrations, release tasks, scripts needing clean env |

**Do NOT use `eval` for database queries.** It starts a fresh process where the app isn't running. Manually bootstrapping the Repo is brittle and causes port conflicts.

## Common Operations

### List all proposals

```elixir
import Ecto.Query
Middling.Repo.all(from p in Middling.Proposals.Proposal, select: {p.id, p.title}))
```

### Delete proposals by ID

All proposal foreign keys cascade (`on_delete: :delete_all`), so deleting a proposal automatically removes:
- proposal_clauses (and their clause_votes)
- votes
- comments

```elixir
import Ecto.Query
ids = [1, 2, 3]
{count, _} = Middling.Repo.delete_all(from p in Middling.Proposals.Proposal, where: p.id in ^ids)
IO.puts("Deleted #{count} proposals")
```

### List users

```elixir
Middling.Repo.all(from u in Middling.Accounts.User, select: {u.id, u.email})
```

## Authentication

If `flyctl` says "No access token available":

```bash
flyctl auth login
```

This opens a browser for auth. Last known credentials are cached in `~/.fly/config.yml`.

## Other Fly Commands

```bash
flyctl status -a middling-ai        # App status
flyctl logs -a middling-ai --follow  # Tail logs
flyctl machines list -a middling-ai  # List machines
```
