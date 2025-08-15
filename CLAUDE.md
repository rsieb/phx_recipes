# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of Phoenix and Elixir recipes organized as markdown documentation in a structured directory layout. Each recipe provides comprehensive, runnable examples for common patterns in Phoenix development.

### Directory Structure
- `/core` - Phoenix fundamentals and OTP patterns
- `/data` - Ecto and database patterns  
- `/testing` - Testing strategies and patterns
- `/deployment` - Production deployment and debugging
- `/workflows` - Development workflows and methodologies
- `/components` - LiveView, components, and UI patterns
- `/config` - Configuration and environment management

## Working with Recipe Files

The recipes are in markdown format with embedded Elixir code. When editing these files:
- Maintain the Mix.install block at the top for dependencies
- Keep code examples complete and runnable
- Include appropriate comments and documentation within code blocks

## Recipe Structure

Each recipe follows a consistent structure:
1. Mix.install block for dependencies
2. Conceptual overview
3. Basic examples (Red-Green-Refactor for TDD recipes)
4. Advanced patterns
5. Best practices and references

## Key Architecture Patterns

### Test-Driven Development Focus
The repository emphasizes TDD methodology with specific recipes for:
- Phoenix TDD workflow (phoenix_tdd_recipe.md)
- TDD with Git workflow (tdd_git_workflow_recipe.md)
- Testing patterns for ConnCase and LiveView

### Phoenix Layers
Recipes are organized by Phoenix's architectural layers:
- **Data Layer**: Ecto schemas, changesets, migrations, transactions
- **Context Layer**: Business logic boundaries (phoenix_contexts.md)
- **Web Layer**: Controllers, LiveView, channels, routers
- **OTP Layer**: GenServers, supervisors, application modules

## Development Commands

Since this is a recipe collection without a Phoenix app structure, there are no traditional build/test commands. However, when working with these recipes:

### Running Recipe Code
The recipes contain Elixir code blocks that can be copied into your Phoenix project or run in IEx.

### Testing Recipe Code
When implementing code from recipes in a Phoenix project:
```bash
# Run all tests
mix test

# Run specific test file
mix test test/path/to/test.exs

# Run tests matching a pattern
mix test --only tag:focus

# Run tests with coverage
mix test --cover
```

## Recipe Categories

1. **Database & Data Layer**: Ecto-related patterns (schemas, changesets, migrations, transactions)
2. **Phoenix Web Layer**: Controllers, LiveView, channels, routing
3. **OTP & Concurrency**: GenServers, supervisors, application configuration
4. **Configuration & Testing**: Environment config, testing patterns
5. **Deployment & Production**: Fly.io deployment, debugging, monitoring

## Important Workflows

### TDD Workflow (from tdd_git_workflow_recipe.md)
1. Create feature branch from main
2. Write failing tests first
3. Commit tests
4. Implement minimal code to pass tests
5. Commit when tests pass
6. Refactor if needed
7. Merge to main when complete

### Phoenix Context Pattern
Contexts provide boundaries between different parts of the application. Follow the patterns in phoenix_contexts.md for:
- API design within contexts
- Cross-context communication
- Query organization
- Testing context functions

## Environment and Deployment Patterns

- **Fly.io deployment**: See fly-io_phoenix_deployments_and_production_debugging.md
- **Environment configuration**: See environment_configuration_phoenix_fly.md
- **Secret management**: See config_and_secrets.md

## Code Conventions from Recipes

When implementing patterns from these recipes:
- Use descriptive function names following Elixir conventions
- Implement comprehensive error handling with pattern matching
- Write tests first following TDD methodology
- Use contexts to organize business logic
- Prefer composition over inheritance
- Leverage OTP patterns for fault tolerance