# Component Architecture

## Component Selection Priority

When building UI, always check for existing components in this order:

### 1. PetalComponents (first choice)
Located in `deps/petal_components/lib/petal_components/`

Available components:
- **Layout**: `<.container>`
- **Typography**: `<.h1>`, `<.h2>`, `<.h3>`, `<.h4>`, `<.p>`
- **Buttons**: `<.button>`, `<.button_group>`
- **Forms**: `<.form>`, `<.field>`, `<.input>`
- **Data Display**: `<.table>`, `<.card>`, `<.badge>`, `<.avatar>`
- **Feedback**: `<.alert>`, `<.progress>`, `<.skeleton>`, `<.loading>`
- **Navigation**: `<.tabs>`, `<.breadcrumbs>`, `<.pagination>`, `<.stepper>`
- **Overlays**: `<.modal>`, `<.dropdown>`, `<.slide_over>`
- **Other**: `<.accordion>`, `<.rating>`, `<.marquee>`, `<.icon>`

Documentation: Check component files directly or https://petal.build/components

### 2. PetalPro Components (second choice)
Located in `lib/middling_web/components/pro_components/`

Available components:
- `data_table/` - Advanced data tables with sorting, filtering, pagination
- `sidebar_layout.ex`, `sidebar_menu.ex` - App shell layouts
- `stacked_layout.ex` - Alternative layout
- `navbar.ex` - Navigation bars
- `flash.ex` - Toast notifications
- `combo_box.ex` - Searchable select
- `content_editor.ex` - Rich text editing
- `user_dropdown_menu.ex` - User account menu
- `color_scheme_switch.ex` - Dark/light mode toggle
- `social_button.ex` - OAuth login buttons
- `local_time.ex` - Timezone-aware time display
- `markdown.ex` - Markdown rendering
- `floating_div.ex` - Floating UI elements
- `page_components.ex` - Page-level helpers

### 3. Custom Components (last resort)
Only build custom components when PetalComponents and PetalPro don't cover the use case.

## core_components.ex Guidelines

**Keep it lean.** This file is for base UI primitives only.

### What belongs in core_components.ex:
- Phoenix-required components (flash, modal, etc.)
- True primitives that are used across many features
- Components that extend/wrap PetalComponents with app-specific defaults

### What does NOT belong:
- Feature-specific components (put these in feature modules or dedicated component files)
- One-off visualizations
- Complex business logic components

### When to create a separate component file:
- Component is feature-specific (e.g., `decoder_components.ex`)
- Component has significant logic (>50 lines)
- Component is only used in one area of the app

Example structure:
```
lib/middling_web/components/
├── core_components.ex          # Base primitives only
├── layouts.ex                  # Layout components
├── decoder_components.ex       # Decoder-specific (compass_plot, etc.)
├── proposal_components.ex      # Proposal-specific
└── pro_components/             # PetalPro components
```

## Usage Examples

### Prefer PetalComponents over raw HTML:

```heex
<!-- ❌ Don't do this -->
<button class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
  Submit
</button>

<!-- ✅ Do this -->
<.button>Submit</.button>
<.button color="primary" variant="outline">Submit</.button>
```

```heex
<!-- ❌ Don't do this -->
<div class="bg-white rounded-lg shadow p-6">
  <h2 class="text-xl font-bold">Title</h2>
  <p>Content</p>
</div>

<!-- ✅ Do this -->
<.card>
  <.card_content heading="Title">
    Content
  </.card_content>
</.card>
```

```heex
<!-- ❌ Don't do this -->
<span class="inline-block px-2 py-1 text-xs font-medium rounded bg-green-100 text-green-800">
  Active
</span>

<!-- ✅ Do this -->
<.badge color="success">Active</.badge>
```
