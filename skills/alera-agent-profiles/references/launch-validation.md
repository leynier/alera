# Launch Validation

Run smoke tests only when requested. Read [managed profiles](managed-profiles.md) for command-generation and adapter-specific diagnostics. Use one bounded read-only prompt per changed profile and verify startup, model selection, response, tab existence, and agent status separately.

## Validation Rules

- A tab existing does not prove that Alera recognized it as an agent. Check both the tab and terminal agent metadata.
- A model's self-reported name is weak evidence. Prefer the persisted profile, generated command, CLI footer or model indicator, and process arguments.
- If a CLI silently falls back to another model, treat the smoke test as failed even if it answers.
- If agent status is missing, inspect the integration path independently from model launch. For wrapper-based integrations such as Cursor, confirm the wrapper or required plugin argument actually reached the child process after shell startup changed `PATH`.
- Record each profile as passed, failed, or passed with a specific status-integration issue. Do not collapse those outcomes into a single launch result.

## Smoke Tests

Use a bounded prompt such as:

```text
Reply with one sentence confirming this Alera Agent Profile smoke test. Name the model you are using. Do not edit files.
```

For each profile verify:

1. The persisted profile and its generated or explicit command contain the intended model and flags.
2. A terminal tab is created and the process stays alive long enough to answer.
3. The CLI's own model indicator or process arguments match the requested model.
4. The response arrives without editing files.
5. Alera reports the expected `agentType` and lifecycle state when hooks are enabled.

Do not reuse adapter-specific prompt flags blindly. Inspect the current CLI and Alera launch behavior first. Keep smoke prompts read-only and close test tabs created for validation when they are no longer needed, unless the user asked to keep them.
