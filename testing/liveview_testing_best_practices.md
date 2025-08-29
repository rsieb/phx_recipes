## Phoenix LiveView Testing Best Practices: A Conceptual Guide

### Understanding LiveView's Testing Model

LiveView testing operates on three distinct layers, each serving different purposes:

**The Disconnected/Connected Duality**: Every LiveView has two lifecycles - the initial HTTP request (disconnected) and the WebSocket upgrade (connected). Many developers only test the connected state, missing bugs that occur during the initial page load. The disconnected mount runs in a different process and can't access certain features like PubSub or timers, making it crucial to test both states.

**The Process Model**: Each LiveView runs as a stateful GenServer process. This means your tests are actually interacting with a real, running process that maintains state between interactions. Understanding this helps explain why timing matters in tests and why certain patterns like `send/2` work.

**The Rendering Pipeline**: LiveView optimizes by only sending diffs over the wire. In tests, calling `render/1` forces a complete render cycle, which is why you sometimes need to call it between actions to ensure state changes are processed.

### Core Testing Principles

#### Test User Behavior, Not Implementation

The most maintainable tests focus on what users see and do, not how the LiveView achieves it. This means preferring:

```elixir
# Good: Testing user-visible behavior
assert has_element?(view, "#user-profile", "John Doe")

# Avoid: Testing internal state
assert view.assigns.user.name == "John Doe"
```

Why? Internal assigns structure changes frequently during refactoring. User-facing elements change less often. When you test assigns directly, you couple your tests to implementation details that don't matter to users.

#### The Timing Problem and How to Solve It

LiveView tests often fail intermittently because of race conditions. The LiveView process runs asynchronously, and your test might check for results before the process finishes updating.

**Common timing error patterns:**
- Sending messages and immediately asserting without allowing processing time
- Testing PubSub broadcasts without accounting for message delivery
- Checking for side effects before async operations complete

**Solutions:**

The "render and wait" pattern forces synchronization:
```elixir
send(view.pid, :some_message)
_ = render(view)  # Forces the view to process pending messages
assert has_element?(view, "#expected-element")
```

Why does this work? The `render/1` function is synchronous - it sends a message to the LiveView process and waits for a response, ensuring all previous messages are processed first.

#### Testing State Transitions, Not State

Rather than testing that assigns contain specific values, test the transitions and their effects:

```elixir
# Testing a multi-step form
{:ok, view, _} = live(conn, "/wizard")

# Step 1 -> Step 2 transition
view |> form("#step-1", %{data: "value"}) |> render_submit()
assert has_element?(view, "#step-2")

# Verify we can go back
view |> element("#back-button") |> render_click()
assert has_element?(view, "#step-1")
```

This approach ensures your state machine logic works correctly without depending on internal representation.

### Component Testing Strategy

#### The Isolation Spectrum

LiveComponents exist on a spectrum from purely functional to deeply integrated:

**Purely Functional Components** should be tested with `render_component/2`:
- They only receive assigns and render HTML
- No internal state or event handlers
- Test like pure functions - given inputs, expect outputs

**Stateful Components** need `live_isolated/3`:
- They maintain their own state
- Handle their own events
- Need a full LiveView process to function

**Integrated Components** must be tested within their parent:
- They communicate with parent via `send_update/2`
- Share state or PubSub subscriptions
- Testing in isolation would miss critical interactions

The key insight: Choose your testing approach based on the component's coupling, not its complexity.

### Event Testing Philosophy

#### The Three Types of Events

**User Events** (`handle_event/3`): These come from browser interactions. Test these by simulating the actual user action:
```elixir
element(view, "#button") |> render_click()
form(view, "#form", %{field: "value"}) |> render_submit()
```

**Internal Messages** (`handle_info/2`): These come from other processes or PubSub. Test by sending actual messages:
```elixir
send(view.pid, {:notification, "content"})
Phoenix.PubSub.broadcast(MyApp.PubSub, "topic", {:event, data})
```

**Hook Events**: These come from JavaScript. Test with `render_hook/3`:
```elixir
render_hook(view, "chart-clicked", %{"point" => 1})
```

Why distinguish? Each type has different failure modes. User events can fail from HTML changes, internal messages from process crashes, and hooks from JavaScript errors.

### Testing Uploads and Streams: Understanding the Abstraction

#### File Upload Testing

File uploads in LiveView tests don't actually upload files - they simulate the upload protocol. This abstraction lets you test:
- File validation without filesystem access
- Progress reporting without actual transfers
- Error handling without network issues

The key insight: You're testing your upload logic, not the browser's upload capability. Focus on validation rules, file constraints, and error handling rather than the mechanics of file transfer.

#### Stream Testing

Streams optimize DOM updates for large lists, but testing them requires understanding their append-only nature:

- Streams never remove DOM elements directly; they mark them for deletion
- Order matters - streams maintain insertion order
- The stream ID becomes part of the DOM element ID

Common mistake: Testing stream items like regular assigns. Stream items exist in the DOM but not in assigns, so use DOM-based assertions:
```elixir
assert has_element?(view, "#stream-id-#{item_id}")
```

### Navigation Testing: The Three Types

**Live Navigation** (`push_navigate`): Stays within the LiveView router, maintaining the WebSocket connection. Test that state persists and no remount occurs.

**Live Patch** (`push_patch`): Updates URL without changing LiveView. Test that `handle_params/3` is called but `mount/3` isn't.

**Live Redirect** (`push_redirect`): Terminates current LiveView and starts new one. Test with `follow_redirect/2` to get the new view process.

Understanding these differences prevents confusing test failures where you're asserting on a terminated process or expecting state to persist across a redirect.

### Performance Testing Considerations

#### Why Performance Test LiveViews?

LiveViews hold state in memory and process events sequentially. Poor performance manifests as:
- Memory leaks from unbounded assign growth
- UI lag from slow event handlers
- Cascading timeouts from blocked processes

#### What to Measure

**Mount Time**: How long does initial render take with realistic data?
- Test with production-sized datasets
- Include association preloading
- Measure both disconnected and connected mounts

**Event Response Time**: How quickly do events process?
- Measure time from event trigger to render completion
- Test with realistic system load
- Include database queries and external service calls

**Memory Growth**: Does memory increase over time?
- Send many events in sequence
- Monitor process memory with `:erlang.process_info/2`
- Check for unreleased resources

### Common Anti-Patterns and Why They Fail

**Testing Implementation Instead of Behavior**: Accessing assigns directly makes tests brittle. The user doesn't see assigns; they see HTML.

**Ignoring the Disconnected Mount**: Bugs here cause SEO problems and flash-of-unstyled-content issues. Always test both mount types.

**Over-Mocking**: LiveView tests are integration tests. Mocking too much defeats their purpose. Only mock external services and slow operations.

**Insufficient Isolation**: Tests that depend on global state or database records from other tests become flaky. Each test should set up its own world.

**Timing-Dependent Assertions**: Never use `Process.sleep/1` for synchronization. It makes tests slow and doesn't guarantee synchronization. Use render cycles or message passing instead.

**Testing JavaScript in Elixir**: LiveView tests can't execute JavaScript. Don't test JavaScript behavior; test the server's response to JavaScript events. Use browser-based tests (Wallaby/Playwright) for JavaScript-heavy features.

### Test Organization Philosophy

Structure tests to tell a story about your feature:

1. **Setup describes context**: Make the starting conditions clear
2. **Actions describe user intent**: Use descriptive variable names and clear action sequences
3. **Assertions describe outcomes**: Focus on user-visible changes

This narrative structure makes tests serve as documentation, showing how the feature should work from a user's perspective.

The goal isn't 100% coverage but confidence that user-facing features work correctly. Test the paths users take, the errors they might encounter, and the edge cases that keep you up at night.