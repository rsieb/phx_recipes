# Environment Variables and Secrets Management

## Overview

Phoenix uses environment variables for secrets. This isn't Rails credentials — there's no encrypted file in the repo. Instead, `.env` files handle local development and your deployment platform (Fly.io) manages production secrets.

## Setup

### 1. Add dotenvy

```elixir
# mix.exs
defp deps do
  [
    {:dotenvy, "~> 0.8"}
  ]
end
```

### 2. Configure runtime.exs

```elixir
# config/runtime.exs (at the top, before any other config)
import Config

if config_env() in [:dev, :test] do
  Dotenvy.source([
    ".env",                    # shared secrets
    ".env.#{config_env()}"     # environment-specific overrides
  ])
end

# Rest of runtime.exs continues normally...
# Later files override earlier ones for duplicate keys
```

### 3. Create environment files

```bash
# File structure
.env              # shared across dev/test/production
.env.dev          # dev-specific overrides
.env.test         # test-specific overrides
.env.production   # production-specific overrides
```

```bash
# .gitignore (add all of these)
.env
.env.dev
.env.test
.env.production
```

```bash
# .env.example (commit this - documents required variables)
# Shared secrets
STRIPE_API_KEY=sk_test_xxx
OPENAI_API_KEY=sk-xxx

# Environment-specific (set in .env.dev, .env.test, .env.production)
# DATABASE_URL=postgresql://...
# SECRET_KEY_BASE=...
```

### 4. Deploy to Fly.io

```bash
# Push shared secrets
fly secrets import < .env

# Push production-specific secrets (overrides shared)
fly secrets import < .env.production
```

Later imports override earlier ones for duplicate keys — same behavior as dotenvy locally.

## What Lives Where

| Variable | Dev | Test | Production |
|----------|-----|------|------------|
| DATABASE_URL | hardcoded in `dev.exs` | hardcoded in `test.exs` | Fly auto-manages |
| SECRET_KEY_BASE | hardcoded in `dev.exs` | hardcoded in `test.exs` | Fly auto-manages |
| PHX_HOST | hardcoded | hardcoded | `fly.toml` or Fly secrets |
| Your API keys | `.env` + `.env.dev` | `.env` + `.env.test` | `fly secrets import` |

Fly auto-sets `DATABASE_URL` and `SECRET_KEY_BASE` when you attach Postgres and deploy. Check with `fly secrets list`.

## Accessing Secrets in Code

```elixir
# config/runtime.exs
config :my_app, :stripe,
  api_key: System.get_env("STRIPE_API_KEY") || raise("Missing STRIPE_API_KEY")

# Optional with default
config :my_app, :pool_size,
  String.to_integer(System.get_env("POOL_SIZE") || "10")
```

```elixir
# In application code - read from config, not env
Application.get_env(:my_app, :stripe)[:api_key]
```

## Workflow

### Adding a new secret

1. Add to `.env` (shared) or `.env.dev` (dev-only)
2. Add to `.env.example` with description
3. Add to `runtime.exs` to read into config
4. Push to production: `fly secrets import < .env`

### Checking production secrets

```bash
fly secrets list
```

### Rotating a secret

```bash
# Update locally
echo "NEW_API_KEY=xxx" >> .env

# Push to production
fly secrets set NEW_API_KEY=xxx
# or
fly secrets import < .env
```

## Why Not Rails Credentials?

Phoenix doesn't have an equivalent. The ecosystem philosophy is "the platform handles secrets" — Fly, Kubernetes, AWS all have secret stores. This is arguably more correct (secrets never touch git) but worse DX for solo devs.

The `.env` + dotenvy + `fly secrets import` pattern gets you 80% of Rails credentials convenience without building custom tooling.
