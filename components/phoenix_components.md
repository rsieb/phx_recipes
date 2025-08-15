# Phoenix Components & Livebook Integration Recipe

### Function Components Recipe

#### 1. Create a Function Component

```elixir
# lib/my_app_web/components/ui_components.ex
defmodule MyAppWeb.UIComponents do
  use Phoenix.Component

  @doc """
  Renders a card with optional header and footer.
  """
  attr :header, :string, default: nil
  attr :footer, :string, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class="p-4 bg-white rounded-lg shadow-md">
      <div :if={@header} class="pb-2 mb-4 border-b">
        <h3 class="text-lg font-semibold"><%= @header %></h3>
      </div>
      
      <div class="content">
        <%= render_slot(@inner_block) %>
      </div>
      
      <div :if={@footer} class="pt-2 mt-4 text-sm text-gray-600 border-t">
        <%= @footer %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a status badge.
  """
  attr :status, :atom, required: true, values: [:active, :inactive, :pending]
  attr :class, :string, default: ""

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "px-2 py-1 rounded-full text-xs font-medium",
      status_classes(@status),
      @class
    ]}>
      <%= String.capitalize(to_string(@status)) %>
    </span>
    """
  end

  defp status_classes(:active), do: "bg-green-100 text-green-800"
  defp status_classes(:inactive), do: "bg-red-100 text-red-800"
  defp status_classes(:pending), do: "bg-yellow-100 text-yellow-800"
end
```

#### 2. Test Function Components

```elixir
# test/my_app_web/components/ui_components_test.exs
defmodule MyAppWeb.UIComponentsTest do
  use MyAppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import MyAppWeb.UIComponents

  describe "card/1" do
    test "renders basic card with content" do
      assigns = %{}
      
      html = 
        rendered_to_string(~H"""
        <.card>
          <p>Card content</p>
        </.card>
        """)

      assert html =~ "bg-white rounded-lg shadow-md"
      assert html =~ "<p>Card content</p>"
      refute html =~ "border-b pb-2"  # No header
    end

    test "renders card with header and footer" do
      assigns = %{}
      
      html = 
        rendered_to_string(~H"""
        <.card header="My Header" footer="My Footer">
          <p>Content here</p>
        </.card>
        """)

      assert html =~ "My Header"
      assert html =~ "My Footer"
      assert html =~ "border-b pb-2"  # Header styling
      assert html =~ "border-t pt-2"  # Footer styling
    end
  end

  describe "status_badge/1" do
    test "renders active status" do
      assigns = %{}
      
      html = 
        rendered_to_string(~H"""
        <.status_badge status={:active} />
        """)

      assert html =~ "bg-green-100 text-green-800"
      assert html =~ "Active"
    end

    test "renders with custom classes" do
      assigns = %{}
      
      html = 
        rendered_to_string(~H"""
        <.status_badge status={:pending} class="ml-2" />
        """)

      assert html =~ "bg-yellow-100 text-yellow-800"
      assert html =~ "ml-2"
      assert html =~ "Pending"
    end
  end
end
```

### Live Components Recipe

#### 1. Create a Live Component

```elixir
# lib/my_app_web/live/components/contact_form_component.ex
defmodule MyAppWeb.ContactFormComponent do
  use MyAppWeb, :live_component
  alias MyApp.Contacts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto">
      <.simple_form
        for={@form}
        id="contact-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:phone]} type="text" label="Phone" />
        
        <:actions>
          <.button phx-disable-with="Saving..." type="submit">
            Save Contact
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{contact: contact} = assigns, socket) do
    changeset = Contacts.change_contact(contact)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"contact" => contact_params}, socket) do
    changeset =
      socket.assigns.contact
      |> Contacts.change_contact(contact_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"contact" => contact_params}, socket) do
    case Contacts.create_contact(contact_params) do
      {:ok, contact} ->
        notify_parent({:saved, contact})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
```

#### 2. Test Live Components

```elixir
# test/my_app_web/live/components/contact_form_component_test.exs
defmodule MyAppWeb.ContactFormComponentTest do
  use MyAppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias MyApp.Contacts

  describe "ContactFormComponent" do
    test "renders form for new contact", %{conn: conn} do
      contact = %Contacts.Contact{}

      {:ok, view, _html} = live_isolated(conn, MyAppWeb.ContactFormComponent,
        session: %{"contact" => contact}
      )

      assert has_element?(view, "form#contact-form")
      assert has_element?(view, "input[name='contact[name]']")
      assert has_element?(view, "input[name='contact[email]']")
      assert has_element?(view, "input[name='contact[phone]']")
    end

    test "validates form on change", %{conn: conn} do
      contact = %Contacts.Contact{}

      {:ok, view, _html} = live_isolated(conn, MyAppWeb.ContactFormComponent,
        session: %{"contact" => contact}
      )

      # Submit invalid data
      view
      |> form("#contact-form", contact: %{name: "", email: "invalid"})
      |> render_change()

      assert has_element?(view, "#contact-form .invalid-feedback")
    end

    test "creates contact on valid submission", %{conn: conn} do
      contact = %Contacts.Contact{}
      parent = self()

      {:ok, view, _html} = live_isolated(conn, MyAppWeb.ContactFormComponent,
        session: %{"contact" => contact}
      )

      # Monitor for parent notification
      ref = Process.monitor(parent)

      # Submit valid data
      view
      |> form("#contact-form", contact: %{
        name: "John Doe", 
        email: "john@example.com",
        phone: "555-1234"
      })
      |> render_submit()

      # Check that parent was notified
      assert_receive {MyAppWeb.ContactFormComponent, {:saved, %Contacts.Contact{}}}, 100
    end
  end
end
```

### Testing Patterns & Best Practices

#### 1. Component Test Helpers

```elixir
# test/support/component_helpers.ex
defmodule MyAppWeb.ComponentHelpers do
  @moduledoc """
  Helper functions for testing components.
  """
  import Phoenix.LiveViewTest

  def render_component(component, assigns \\ %{}) do
    rendered_to_string(component.(assigns))
  end

  def assert_component_has_class(html, class) do
    assert html =~ class, "Expected component to have class '#{class}'"
  end

  def refute_component_has_class(html, class) do
    refute html =~ class, "Expected component to NOT have class '#{class}'"
  end
end
```

#### 2. Integration Tests

```elixir
# test/my_app_web/live/contacts_live_test.exs
defmodule MyAppWeb.ContactsLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  test "can create contact using form component", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/contacts")

    # Click new contact button
    view |> element("a", "New Contact") |> render_click()

    # Fill out the form component
    view
    |> form("#contact-form", contact: %{
      name: "Jane Doe",
      email: "jane@example.com"
    })
    |> render_submit()

    # Verify contact appears in list
    assert has_element?(view, "[data-test-contact-name='Jane Doe']")
  end
end
```

#### 3. Component Documentation Tests

```elixir
# Mix task to verify all components have proper documentation
defmodule Mix.Tasks.Test.ComponentDocs do
  use Mix.Task

  def run(_) do
    components = [
      MyAppWeb.UIComponents,
      MyAppWeb.ContactFormComponent
    ]

    Enum.each(components, fn module ->
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)
      
      public_functions = 
        docs
        |> Enum.filter(fn {{:function, name, _arity}, _, _, _, _} -> 
          !String.starts_with?(to_string(name), "_")
        end)

      Enum.each(public_functions, fn {{:function, name, arity}, _, _, doc, _} ->
        if is_nil(doc) do
          Mix.shell().error("Missing documentation: #{module}.#{name}/#{arity}")
        end
      end)
    end)
  end
end
```

---

## Part 3: Key Testing Guidelines with Examples

### 1. Test Behavior, Not Implementation

#### ✅ DO: Test what users see and experience
```elixir
test "displays contact name and email" do
  html = render_component(&contact_card/1, %{
    contact: %{name: "John Doe", email: "john@example.com"}
  })
  
  assert html =~ "John Doe"
  assert html =~ "john@example.com"
end

test "shows active status with green badge" do
  html = render_component(&status_badge/1, %{status: :active})
  
  assert html =~ "Active"
  assert html =~ "bg-green-100"  # Visual indicator
end
```

#### ❌ DON'T: Test internal function calls or private details
```elixir
# Bad: Testing implementation details
test "calls format_phone_number helper" do
  contact = %{phone: "5551234567"}
  
  # This tests HOW it works, not WHAT it produces
  assert_called(MyComponent.format_phone_number(contact.phone))
end

# Bad: Testing private CSS class generation
test "status_classes returns correct class" do
  assert MyComponent.status_classes(:active) == "bg-green-100"
end
```

### 2. Use `rendered_to_string/1` for Function Components

#### ✅ DO: Use for simple, stateless components
```elixir
test "button component renders with label" do
  assigns = %{}
  
  html = rendered_to_string(~H"""
  <.button label="Click me" type="submit" />
  """)
  
  assert html =~ "Click me"
  assert html =~ "type=\"submit\""
end
```

#### ❌ DON'T: Use for components that need interaction
```elixir
# Bad: Can't test click events with rendered_to_string
test "button handles click" do
  html = rendered_to_string(~H"""
  <.button phx-click="save" />
  """)
  
  # This won't work - no event handling in static render
  html |> element("button") |> render_click()
end
```

### 3. Use `live_isolated/3` for Live Components

#### ✅ DO: Isolate live components for focused testing
```elixir
test "form validates on change", %{conn: conn} do
  {:ok, view, _html} = live_isolated(conn, ContactFormComponent,
    session: %{"contact" => %Contact{}}
  )
  
  view
  |> form("#contact-form", contact: %{email: "invalid"})
  |> render_change()
  
  assert has_element?(view, ".invalid-feedback")
end
```

#### ❌ DON'T: Test live components in full page context unless needed
```elixir
# Bad: Overly complex setup for simple component test
test "form validates", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/contacts/new")
  
  # Now you have to deal with the entire page, navigation, etc.
  view |> element("#show-form-modal") |> render_click()
  view |> form("#contact-form", contact: %{email: "bad"}) |> render_change()
  
  assert has_element?(view, ".invalid-feedback")
end
```

### 4. Test Error States

#### ✅ DO: Test validation, missing data, and edge cases
```elixir
test "shows error for missing required fields" do
  assigns = %{}
  
  html = rendered_to_string(~H"""
  <.input field={%Phoenix.HTML.FormField{errors: [{"can't be blank", [validation: :required]}]}} />
  """)
  
  assert html =~ "can't be blank"
end

test "handles server error gracefully", %{conn: conn} do
  # Mock the context to return an error
  expect(ContactsMock, :create_contact, fn _ -> 
    {:error, %Ecto.Changeset{}}
  end)
  
  {:ok, view, _html} = live_isolated(conn, ContactFormComponent, 
    session: %{"contact" => %Contact{}}
  )
  
  view |> form("#contact-form") |> render_submit()
  
  assert has_element?(view, ".alert-error")
end
```

#### ❌ DON'T: Only test the happy path
```elixir
# Bad: Only testing successful scenarios
test "creates contact" do
  view |> form("#contact-form", contact: valid_attrs()) |> render_submit()
  assert has_element?(view, ".success-message")
  # What about validation errors? Network failures? Duplicate emails?
end
```

### 5. Mock External Dependencies

#### ✅ DO: Mock external services and APIs
```elixir
test "sends welcome email after contact creation" do
  expect(EmailServiceMock, :send_welcome_email, fn contact ->
    {:ok, %{id: "email-123"}}
  end)
  
  {:ok, view, _html} = live_isolated(conn, ContactFormComponent,
    session: %{"contact" => %Contact{}}
  )
  
  view |> form("#contact-form", contact: valid_attrs()) |> render_submit()
  
  verify!(EmailServiceMock)
end
```

#### ❌ DON'T: Hit real external services in tests
```elixir
# Bad: Real API calls make tests slow and fragile
test "validates email with real email service" do
  # This will actually call the external API
  EmailValidator.verify("test@example.com")
  
  view |> form("#contact-form", contact: %{email: "test@example.com"})
  # Test becomes dependent on network, API quotas, etc.
end
```

### 6. Use Data Attributes for Test Selectors

#### ✅ DO: Use stable, semantic test selectors
```elixir
# In your component
def contact_card(assigns) do
  ~H"""
  <div data-test-contact-card data-contact-id={@contact.id}>
    <h3 data-test-contact-name><%= @contact.name %></h3>
    <span data-test-contact-status={@contact.status}>
      <%= @contact.status %>
    </span>
  </div>
  """
end

# In your test
test "displays contact information" do
  assert has_element?(view, "[data-test-contact-name]", "John Doe")
  assert has_element?(view, "[data-test-contact-status='active']")
end
```

#### ❌ DON'T: Rely on CSS classes or DOM structure
```elixir
# Bad: Fragile selectors that break when styling changes
test "displays contact" do
  assert has_element?(view, ".bg-white.rounded-lg .text-lg.font-semibold", "John")
  assert has_element?(view, "div > div > span.text-green-600")
end

# Bad: Position-dependent selectors
test "shows status in second column" do
  assert has_element?(view, "tr td:nth-child(2)", "Active")
end
```

### Bonus: Testing Async Behavior

#### ✅ DO: Properly handle async operations
```elixir
test "shows loading state during save", %{conn: conn} do
  # Slow down the mock to test loading state
  expect(ContactsMock, :create_contact, fn _ ->
    Process.sleep(100)
    {:ok, %Contact{}}
  end)
  
  {:ok, view, _html} = live_isolated(conn, ContactFormComponent,
    session: %{"contact" => %Contact{}}
  )
  
  view |> form("#contact-form") |> render_submit()
  
  # Check loading state appears
  assert has_element?(view, "[data-test-loading]")
  
  # Wait for completion
  assert_patch(view, "/contacts")
end
```

#### ❌ DON'T: Race conditions in tests
```elixir
# Bad: Assumes immediate completion
test "redirects after save" do
  view |> form("#contact-form") |> render_submit()
  # This might fail if the operation is async
  assert_patch(view, "/contacts")
end
```

---

## Summary

This recipe provides:

2. **Complete examples** of creating both function and live components
3. **Comprehensive testing strategies** with real code examples
4. **Best practices** with clear do's and don'ts for maintainable tests

### Key Takeaways

- **Function components** for simple, reusable UI elements
- **Live components** for stateful, interactive elements
- **Test behavior, not implementation** 
- **Use proper testing tools** for each component type
- **Mock external dependencies** to keep tests fast and reliable
- **Use semantic test selectors** that won't break with UI changes

This approach creates maintainable, testable components while providing powerful interactive documentation capabilities through Livebook integration.