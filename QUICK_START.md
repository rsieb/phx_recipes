# Phoenix Recipe Quick Start Guide

## 🎯 What Do You Want to Build?

### "I'm starting a new Phoenix project"
1. Start with [MVP Principles](workflows/mvp_principles.md) - understand what to build
2. Review [Phoenix Contexts](core/phoenix_contexts.md) - organize your code properly
3. Follow [TDD Git Workflow](workflows/tdd_git_workflow.md) - development process

### "I need to add authentication"
→ [Authentication & Authorization](core/authentication_authorization.md)

### "I want real-time features"
- Basic real-time → [Phoenix Channels](components/phoenix_channels.md)
- Interactive UI → [Phoenix LiveView Basics](components/phoenix_liveview_basics.md)
- Advanced patterns → [WebSocket Patterns](components/websocket_patterns.md)

### "I need to work with the database"
- Defining models → [Ecto Schema Basics](data/ecto_schema_basics.md)
- Validating data → [Ecto Changesets](data/ecto_changesets.md)
- Complex operations → [Ecto Multi Transaction](data/ecto_multi_transaction.md)
- Performance issues → [Database Performance](data/database_performance.md)

### "I'm ready to deploy"
1. [Configuration Management](config/configuration_management.md) - prepare your app
2. [CI/CD Pipeline](deployment/cicd_pipeline.md) - automate deployment
3. [Fly.io Deployment](deployment/fly_deployment_debugging.md) - deploy to production

### "Something is broken in production"
→ [Production Debugging](deployment/production_debugging.md)

## 📚 By Experience Level

### Beginner (New to Phoenix)
1. [Phoenix Router and Pipelines](core/phoenix_router_and_pipelines.md)
2. [Phoenix Controllers](core/phoenix_controllers.md)
3. [Ecto Schema Basics](data/ecto_schema_basics.md)
4. [Phoenix Scaffolding](core/phoenix_scaffolding.md)

### Intermediate (Building Features)
1. [Phoenix Contexts](core/phoenix_contexts.md)
2. [Component Architecture](components/component_architecture.md)
3. [Comprehensive Testing Guide](testing/comprehensive_testing_guide.md)
4. [Phoenix LiveView Basics](components/phoenix_liveview_basics.md)

### Advanced (Scaling & Optimizing)
1. [Database Performance](data/database_performance.md)
2. [GenServer Basics](core/genserver_basics.md)
3. [Supervisor Tree](core/supervisor_tree.md)
4. [WebSocket Patterns](components/websocket_patterns.md)

## 🔧 Common Tasks → Recipe

| Task | Recipe |
|------|--------|
| Add file uploads | [Phoenix LiveView Uploads](components/phoenix_liveview_uploads.md) |
| Background jobs | [Oban Background Jobs](core/oban_background_jobs.md) |
| Type checking | [Typespecs and Dialyzer](core/typespecs_dialyzer.md) |
| Component reuse | [Phoenix Components](components/phoenix_components.md) |
| Testing strategy | [Comprehensive Testing Guide](testing/comprehensive_testing_guide.md) |
| Config management | [Configuration Management](config/configuration_management.md) |
| When to use LiveView | [Traditional vs LiveView](components/phoenix_prefer_traditional_use_liveview_sparingly.md) |

## 🚀 Development Workflows

- **MVP Development** → [MVP Phoenix Patterns](workflows/mvp_phoenix_patterns.md)
- **Test-Driven Development** → [TDD Git Workflow](workflows/tdd_git_workflow.md)
- **No External Dependencies** → [No External Scripts](workflows/no_external_scripts.md)
- **Combined Approach** → [Combined Workflow](workflows/combined_workflow.md)

## 📋 Prerequisites

Most recipes assume you have:
- Elixir 1.14+ and Phoenix 1.7+
- PostgreSQL installed
- Basic familiarity with Elixir syntax
- A Phoenix project generated with `mix phx.new`

## 💡 Tips for Using Recipes

1. **Start with the problem**, not the solution - identify what you're trying to achieve
2. **Read the overview first** - understand the concept before diving into code
3. **Adapt to your context** - recipes are starting points, not rigid rules
4. **Test everything** - use the testing patterns provided in each recipe
5. **Check cross-references** - related recipes often provide complementary information

## 🔍 Can't Find What You Need?

1. Check the full [Table of Contents](index.md)
2. Search for keywords in recipe files
3. Review the [Recipe Template](workflows/recipe_template.md) to create your own
4. Consider if your need fits into existing patterns

---

*Start with the simplest solution that works, then iterate based on real needs.*