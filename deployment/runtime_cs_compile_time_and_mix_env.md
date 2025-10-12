# Mix.env() is Undefined in Production: Understanding Phoenix Runtime vs Compile-Time

## The Core Problem

When you deploy a Phoenix application to production, you'll encounter a frustrating error: `Mix.env/0 is undefined`. This happens because Mix is fundamentally a build tool, not a runtime dependency. Understanding this distinction is crucial for Phoenix developers.

## Why This Happens: The Two Lives of Your Code

Phoenix applications live two separate lives that developers often conflate:

**Compile-time**: When your code is being transformed from Elixir source files into BEAM bytecode. During this phase, Mix is present and orchestrating the build process. This happens on your development machine or CI server.

**Runtime**: When your compiled application is actually running and serving requests. In production, this is typically a released OTP application where Mix doesn't exist at all - your app is just BEAM bytecode running on the Erlang VM.

The confusion arises because in development, these two phases blur together. When you run `mix phx.server`, Mix stays around to provide conveniences like code reloading. This creates a false sense of security that `Mix.env()` will always be available.

## What Mix.env() Actually Is

Mix.env() is a compile-time flag that tells the build system how to compile your code. It determines:

- Which configuration files to load (dev.exs vs prod.exs)
- Which dependencies to include
- What optimizations to apply
- Which compile-time code branches to keep

Think of it like compiler flags in C or build configurations in other languages. Once compilation is done, this information has already been "baked into" your compiled code. The flag itself is no longer needed or available.

## The Phoenix Solution: Runtime Configuration

Phoenix solves this by separating compile-time configuration from runtime configuration. The framework expects you to:

1. Use Mix.env() only in configuration files that run during compilation
2. Store runtime environment detection in application configuration
3. Access that configuration at runtime through Application.get_env()

This separation is deliberate and important. It ensures your production releases are self-contained and don't depend on build tools being present.

## The Standard Pattern

The Phoenix community has converged on a simple pattern:

```elixir
# In config/runtime.exs (which runs when the app starts)
config :my_app, :environment, System.get_env("APP_ENV", "development") |> String.to_atom()

# In your application code
def check_environment do
  Application.get_env(:my_app, :environment)
end
```

This pattern explicitly separates the build environment (MIX_ENV) from the runtime environment (APP_ENV). They often have the same value, but they're fundamentally different concepts.

## Why Not Auto-Detect?

You might wonder why Phoenix doesn't automatically detect the environment at runtime. The answer is philosophical and practical:

**Explicit is better than implicit**: Phoenix wants you to be deliberate about your environment. Auto-detection based on various heuristics (port numbers, hostnames, etc.) leads to subtle bugs and confusion.

**Releases should be environment-agnostic**: The same compiled release should be deployable to staging or production just by changing environment variables. This enables practices like promoting the exact same artifact through environments.

**Predictability**: When something goes wrong at 3 AM, you want to know exactly how your app determines its environment, not chase through clever detection logic.

## Common Misconceptions

### "I'll just check Mix.env() and handle the error"

This misunderstands the problem. It's not that Mix.env() might fail - it's that the entire Mix module doesn't exist in production. You can't even check if it's defined without causing compilation issues.

### "Module attributes will work"

Module attributes like `@env Mix.env()` are resolved at compile-time. In production, they'll always contain whatever MIX_ENV was during compilation (usually "prod"), not the actual runtime environment.

### "I need different code for different environments"

Usually, you don't. What you need is different configuration. The same code should work in all environments, just with different settings (URLs, credentials, feature flags). This is what configuration is for.

## Testing Environment-Specific Behavior

Since environment detection is now just configuration, testing becomes straightforward. You temporarily change the application environment in your tests:

```elixir
# Save original, change for test, restore after
original = Application.get_env(:my_app, :environment)
Application.put_env(:my_app, :environment, :production)
# Test production behavior
Application.put_env(:my_app, :environment, original)
```

This is much cleaner than trying to mock Mix.env() or manipulate build-time configuration.

## The Broader Lesson

This Mix.env() issue teaches an important lesson about Phoenix and Elixir: understand the boundaries between compile-time and runtime. Many Phoenix gotchas stem from this confusion:

- Configuration that seems to change randomly (compile-time vs runtime)
- Module attributes that don't update (compile-time evaluation)
- Macros behaving unexpectedly (compile-time expansion)
- Release configuration not taking effect (runtime.exs vs config.exs)

## When to Use What

**Use Mix.env() when:**
- You're in config/*.exs files (except runtime.exs)
- You're writing macros that need compile-time environment detection
- You're in Mix tasks

**Use Application.get_env() when:**
- You're in application code
- You're in runtime.exs
- You need to check environment at runtime
- You're writing tests

**Use System.get_env() when:**
- You're in runtime.exs reading environment variables
- You need to check actual OS environment variables

## Deployment Checklist

Before deploying, ensure:

1. No Mix.env() calls in application code
2. Runtime environment configured in runtime.exs
3. APP_ENV (or equivalent) documented in deployment guides
4. Environment-specific behavior uses Application.get_env()
5. Module attributes don't reference Mix.env()

## The Key Takeaway

Mix.env() is a compile-time build flag, not a runtime environment detector. In production, your code runs without Mix entirely. Embrace Phoenix's explicit runtime configuration approach - it's more predictable, testable, and deployment-friendly than clever auto-detection.

This separation of concerns between build-time and runtime is a feature, not a bug. It forces you to think clearly about configuration and makes your deployments more reliable.
