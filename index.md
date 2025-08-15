# Elixir/Phoenix Recipe Collection

## Overview

This collection provides comprehensive, practical recipes for common Elixir and Phoenix patterns. Each recipe includes runnable code examples, best practices, and references to official documentation.

## Repository Structure

```
/core         - Phoenix fundamentals and OTP patterns
/data         - Ecto and database patterns
/testing      - Testing strategies and patterns
/deployment   - Production deployment and debugging
/workflows    - Development workflows and methodologies
/components   - LiveView, components, and UI patterns
/config       - Configuration and environment management
```

## Table of Contents

### Core Phoenix & OTP

#### [Phoenix Contexts](core/phoenix_contexts.md)
Organize business logic and create boundaries between different parts of your application.

#### [Phoenix Controllers](core/phoenix_controllers.md)
Handle HTTP requests and responses using Phoenix controllers.

#### [Phoenix Router and Pipelines](core/phoenix_router_and_pipelines.md)
Configure HTTP routing and request processing pipelines in Phoenix applications.

#### [GenServer Basics](core/genserver_basics.md)
Build stateful server processes using GenServer for concurrent applications.

#### [Supervisor Tree](core/supervisor_tree.md)
Design fault-tolerant applications using OTP supervisor trees.

#### [Application Module](core/application_module.md)
Configure and manage your Phoenix application lifecycle and supervision tree.

#### [Oban Background Jobs](core/oban_and_oban_testing_recipe.md)
Implement reliable background job processing with Oban.

#### [Phoenix Scaffolding](core/phoenix_scaffolding_recipe.md)
Rapidly generate Phoenix resources and understand the generated code.

#### [Typespecs and Dialyzer](core/typespecs_dialyzer_recipe.md)
Add type specifications and static analysis to your Elixir code.

### Data Layer

#### [Ecto Schema Basics](data/ecto_schema_basics.md)
Learn how to define database schemas, field types, relationships, and validation rules using Ecto schemas.

#### [Ecto Changesets](data/ecto_changesets.md)
Master data validation and transformation using Ecto changesets for safe database operations.

#### [Ecto Multi Transaction](data/ecto_multi_transaction.md)
Handle complex database operations with transactions using Ecto.Multi for data consistency.

#### [Ecto Migrations](data/ecto_migrations.md)
Manage database schema changes over time with Ecto migrations.

### Components & UI

#### [Phoenix LiveView Basics](components/phoenix_liveview_basics.md)
Build interactive, real-time web applications with Phoenix LiveView.

#### [Phoenix LiveView Uploads](components/phoenix_liveview_uploads.md)
Handle file uploads in LiveView with progress tracking and validation.

#### [Phoenix Components](components/phoenix_components_recipe.md)
Create reusable UI components for Phoenix applications.

#### [Phoenix Componentization](components/phoenix_componentization_recipe.md)
Architect component-based Phoenix applications with proper composition patterns.

#### [Phoenix Channels](components/phoenix_channels.md)
Create real-time bidirectional communication using Phoenix Channels and WebSockets.

#### [Connection and Socket Troubleshooting](components/phoenix_conn_socket_troubleshooting.md)
Debug and resolve common Phoenix connection and socket issues.

#### [Traditional vs LiveView](components/phoenix_prefer_traditional_use_liveview_sparingly.md)
Guidelines for choosing between traditional Phoenix and LiveView approaches.

#### [Livebook Integration](components/livebook_recipe.md)
Integrate Livebook for interactive documentation and data exploration.

### Testing

#### [Comprehensive Testing Guide](testing/comprehensive_testing_guide.md)
Complete guide to testing Phoenix applications including:
- Unit testing (schemas, changesets, contexts)
- Controller testing with ConnCase
- LiveView component and interaction testing
- Test-Driven Development (TDD) workflow
- Testing helpers and best practices
- Common patterns and anti-patterns

### Configuration & Environment

#### [Configuration and Secrets](config/config_and_secrets.md)
Manage application configuration and secrets securely across environments.

#### [Environment Best Practices](config/environment_best_practices_in_phoenix.md)
Best practices for managing Phoenix environments from development to production.

#### [Environment Configuration for Fly](config/environment_configuration_phoenix_fly.md)
Configure Phoenix applications for deployment on Fly.io.

### Deployment & Production

#### [Fly.io Deployment and Debugging](deployment/fly-io_phoenix_deployments_and_production_debugging.md)
Deploy Phoenix applications to Fly.io and debug production issues.

#### [Systematic Debugging](deployment/systematic-debugging-of-staging-or-production-on-fly-and-supabase.md)
Systematic approach to debugging staging and production environments.

### Development Workflows

#### [TDD Git Workflow](workflows/tdd_git_workflow_recipe.md)
Integrate Test-Driven Development with Git workflows for Phoenix projects.

#### [MVP Focus Recipe](workflows/mvp_focus_recipe.md)
Build Minimum Viable Products efficiently with Phoenix.

#### [Combined Workflow](workflows/combined_workflow_recipe.md)
Integrate multiple development workflows for maximum productivity.

#### [No External Scripts](workflows/no_external_scripts_recipe.md)
Develop Phoenix applications without relying on external scripts.

#### [Template Recipe](workflows/template_elixir_phoenix_recipe.md)
Template for creating new Phoenix recipes and documentation.

## How to Use These Recipes

### Getting Started
1. Navigate to the appropriate category directory
2. Each recipe is self-contained with complete, runnable examples
3. Copy and adapt the code patterns to your specific use case
4. Follow the referenced documentation for deeper understanding

### Best Practices
- Start with the basic examples and build up to complex patterns
- Always test your implementations using the provided test patterns
- Follow the security and performance guidelines in each recipe
- Adapt the patterns to your specific domain and requirements

### Code Organization
- Use the suggested file structures and naming conventions
- Follow the separation of concerns shown in the examples
- Implement proper error handling as demonstrated
- Use the monitoring and logging patterns for production systems

## Contributing

These recipes are designed to be practical and up-to-date. If you find issues or have suggestions for improvements, please refer to the project's contribution guidelines.

## Additional Resources

### Official Documentation
- [Phoenix Framework](https://hexdocs.pm/phoenix/)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Elixir Documentation](https://elixir-lang.org/docs.html)

### Community Resources
- [Phoenix Community](https://phoenixframework.org/community)
- [Elixir Forum](https://elixirforum.com/)
- [Phoenix LiveView Examples](https://github.com/chrismccord/phoenix_live_view_example)

---

*This recipe collection is maintained as part of best practices documentation. Each recipe follows Phoenix and Elixir best practices as of 2025.*