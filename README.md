# Phoenix Recipes Collection

A comprehensive collection of Phoenix and Elixir recipes organized as best practices documentation. This repository serves as a submodule for Phoenix projects, providing ready-to-use patterns and solutions.

## 🚀 Quick Start

**New to this collection?** Start with the [Quick Start Guide](QUICK_START.md) for a decision tree approach to finding the right recipe.

## 📚 Repository Structure

```
/core         - Phoenix fundamentals and OTP patterns
/data         - Ecto and database patterns  
/testing      - Testing strategies and patterns
/deployment   - Production deployment and debugging
/workflows    - Development workflows and methodologies
/components   - LiveView, components, and UI patterns
/config       - Configuration and environment management
```

## 🎯 Purpose

This repository is designed to be added as a git submodule to Phoenix projects, providing:
- Consistent best practices across projects
- Ready-to-use code patterns
- Comprehensive testing strategies
- Production-ready deployment guides
- TDD workflows and methodologies

## 💻 Usage as a Submodule

Add this repository to your Phoenix project:

```bash
git submodule add https://github.com/rsieb/phx_recipes.git docs/recipes
git submodule update --init --recursive
```

Update to latest recipes:

```bash
cd docs/recipes
git pull origin main
cd ../..
git add docs/recipes
git commit -m "Update Phoenix recipes"
```

## 📖 Key Recipes

### For Beginners
- [Ecto Schema Basics](data/ecto_schema_basics.md)
- [Phoenix Router and Pipelines](core/phoenix_router_and_pipelines.md)
- [TDD Git Workflow](workflows/tdd_git_workflow.md)

### For Building Features
- [Phoenix Contexts](core/phoenix_contexts.md)
- [Phoenix LiveView Basics](components/phoenix_liveview_basics.md)
- [Authentication & Authorization](core/authentication_authorization.md)

### For Production
- [Configuration Management](config/configuration_management.md)
- [CI/CD Pipeline](deployment/cicd_pipeline.md)
- [Production Debugging](deployment/production_debugging.md)

## 🧪 Testing

All recipes include comprehensive testing examples. See the [Comprehensive Testing Guide](testing/comprehensive_testing_guide.md) for Phoenix testing best practices.

## 🔧 Requirements

- Elixir 1.14+
- Phoenix 1.7+
- PostgreSQL
- Basic familiarity with Elixir and Phoenix

## 📝 Contributing

This is a living document. When you discover new patterns or improve existing ones:

1. Follow the [Recipe Template](workflows/recipe_template.md)
2. Include practical, runnable examples
3. Add appropriate cross-references
4. Update the index and quick start guide

## 📚 Full Documentation

See the complete [Table of Contents](index.md) for all available recipes.

## 🔗 Additional Resources

- [Phoenix Framework Documentation](https://hexdocs.pm/phoenix/)
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Phoenix Community](https://phoenixframework.org/community)

---

*Built with inspiration from Phoenix best practices and the Phoenix community.*