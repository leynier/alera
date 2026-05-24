# AGENTS

## Scope

This file applies to `test/`.

## Test Rules

- Prefer focused unit tests for pure domain, controller, parser, and service behavior.
- Use widget tests for user-visible UI state, layout contracts, and interactions.
- Do not add a widget test when a unit test can cover the same behavior with less setup.
- For platform-specific behavior, cover each supported platform branch when the branch affects command construction, paths, update selection, or visible copy.
- Assertions should target behavior or visible UI, not only implementation details.

## Fixtures

- Keep fixtures small and local to the test file unless reused by multiple suites.
- Use in-memory repositories and fake services instead of touching real user data.
- Do not depend on network access in tests.
