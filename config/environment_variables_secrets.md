# Environment Variables and Secrets Management in Phoenix

## The Fundamental Question: Where Do Secrets Live?

Every Phoenix application needs secrets: API keys, database passwords, service tokens. The question isn't whether you need them, but where to put them and how to manage them across different environments without compromising security or developer experience.

## Why Environment Variables Won

The Phoenix community has standardized on environment variables for secrets management. This isn't arbitrary - it's the result of years of collective experience. Here's why this approach dominates:

**Separation of concerns**: Your code describes what configuration it needs. The deployment environment provides the actual values. This separation means the same compiled code can run anywhere.

**Platform agnostic**: Every deployment platform - from Heroku to Kubernetes to bare metal - supports environment variables. You're not locked into proprietary configuration systems.

**Security by default**: Environment variables are never accidentally committed to version control. They're not visible in stack traces. They're isolated from application code.

**Twelve-Factor App compliance**: Phoenix follows the Twelve-Factor App methodology, which prescribes storing config in the environment. This isn't just convention - it's a proven pattern for scalable applications.

## The Phoenix Configuration Pipeline

Understanding how configuration flows through a Phoenix application is crucial:

1. **Operating System** provides environment variables
2. **runtime.exs** reads these variables when the application starts
3. **Application configuration** stores the processed values
4. **Your code** accesses configuration through Application.get_env()

This pipeline ensures configuration is centralized, validated, and properly typed before your application code ever sees it.

## Runtime.exs: The Configuration Gateway

The `runtime.exs` file is special. Unlike other config files, it runs when your application starts, not when it compiles. This makes it the perfect place to read environment variables and transform them into application configuration.

```elixir
# config/runtime.exs
config :my_app, :octave_api,
  api_key: System.get_env("OCTAVE_API_KEY") || raise("Missing OCTAVE_API_KEY")
```

This pattern does three critical things:
1. Reads from the environment
2. Validates the value exists
3. Fails fast if misconfigured

## The Development Problem and Its Solution

Environment variables are great for production but cumbersome in development. You don't want to export dozens of variables every time you start coding. The community has settled on `.env` files as the solution.

The pattern is simple:
- `.env` contains your actual development secrets (git-ignored)
- `.env.example` shows what variables are needed (committed)
- Developers copy `.env.example` to `.env` and fill in their values

This gives you security (no committed secrets) with convenience (no manual exports).

## Required vs Optional: A Critical Distinction

Not all configuration is created equal. Your payment processor API key is critical - the app shouldn't start without it. A custom timeout value is nice to have but not essential.

Phoenix developers handle this distinction explicitly:

**Required values** should raise errors if missing. This fails fast and makes misconfigurations obvious.

**Optional values** should have sensible defaults. This keeps the app flexible without requiring extensive configuration.

The decision between required and optional often depends on the environment. A Slack webhook might be optional in development but required in production.

## Why Not Store Secrets in Code?

Some frameworks encourage storing encrypted secrets in the repository. Phoenix doesn't, and for good reason:

**Rotation becomes difficult**: When you need to change a compromised key, you must redeploy code rather than just update an environment variable.

**Access control is binary**: Anyone with repository access can see all secrets (even if encrypted, they can decrypt them by running the app).

**Audit trails are weak**: Git history shows when secrets changed but not who accessed them.

**Local development is complicated**: Developers need decryption keys just to run the app locally.

Environment variables solve all these problems. They can be rotated without deployment, have platform-specific access controls, leave audit trails, and work simply in development.

## The Testing Challenge

How do you test code that depends on environment variables? The Phoenix approach is pragmatic: use application configuration as an abstraction layer.

Instead of reading environment variables directly in your code, you read application configuration. Tests can then manipulate this configuration without touching actual environment variables. This makes tests faster, more isolated, and more reliable.

## Platform-Specific Patterns

Each deployment platform has its own way of managing secrets, but they all map to environment variables:

**Platform-as-a-Service** (Heroku, Fly.io): These platforms provide CLI commands to set production secrets. They handle encryption, storage, and injection into your app's environment.

**Container Orchestration** (Kubernetes): Secrets are first-class objects that get mounted as environment variables in your pods. This adds namespace isolation and role-based access control.

**Traditional Servers**: Tools like systemd or supervisor can set environment variables for your application process. Secrets might live in protected files that only the app user can read.

The beauty of environment variables is that your Phoenix app doesn't care about these platform differences. It just reads from the environment.

## Security Considerations

Environment variables aren't a security silver bullet. You still need to:

**Limit access**: Use your platform's access controls to restrict who can view or modify production secrets.

**Rotate regularly**: Treat API keys like passwords - change them periodically.

**Monitor usage**: Many services let you track API key usage to detect compromises.

**Use different keys per environment**: Never use production API keys in development or staging.

**Avoid logging secrets**: Be careful not to log configuration that contains secrets.

## The Configuration Boundary

There's an important architectural principle at play: configuration should be processed at the boundary of your system (runtime.exs) and then passed inward as regular application state. 

Your business logic shouldn't know about environment variables. It should receive configuration as function arguments or module attributes. This makes your core logic testable, portable, and easier to reason about.

## When Not to Use Environment Variables

Environment variables aren't always the answer:

**Complex configuration**: If you need structured configuration (nested maps, lists), consider configuration files that are referenced by environment variables.

**Feature flags**: While simple boolean flags work as environment variables, complex feature flag systems might need database backing for dynamic updates.

**Per-request configuration**: Things like user preferences or tenant settings belong in your database, not environment variables.

## Documentation as Code

The `.env.example` file serves as living documentation. It should include:
- Every required variable
- Example values that show the expected format
- Comments explaining what each variable does
- Links to where to obtain API keys

This file is often more valuable than external documentation because it's always in sync with the code and immediately useful to developers.

## The Migration Path

If you're moving from hardcoded configuration to environment variables:

1. Start with non-secret configuration to get comfortable with the pattern
2. Move development/test secrets to `.env` files
3. Set up production secrets in your deployment platform
4. Add validation and helpful error messages
5. Document everything in `.env.example`

## Common Pitfalls

**Forgetting to set production variables**: Your app works locally but crashes in production. Always validate required variables in runtime.exs.

**Committing .env files**: Add `.env` to `.gitignore` immediately. Once committed, secrets are compromised forever in git history.

**Using production keys in development**: This risks both security (dev machines are less secure) and stability (development work might hit production services).

**Not providing defaults**: Requiring dozens of environment variables makes development painful. Provide sensible defaults where possible.

## The Philosophy

Environment variables embody the Phoenix philosophy: explicit over implicit, simple over clever, standard over custom. They're not the most sophisticated solution, but they're the most pragmatic.

This approach scales from solo projects to large teams, from simple apps to complex systems. It's boring technology that just works, which is exactly what you want for something as critical as configuration management.