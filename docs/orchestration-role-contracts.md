# Orchestration Role Contracts

Role contracts define the purpose, instructions, concrete inputs and completion requirements of a task. They are portable data, not agent launch configurations. A contract does not choose a provider, model, command, credential or execution environment; Agent Profiles continue to control launches.

[Recipes](recipes.md) embed these contracts with exact role references in Built-in, Personal and Project catalogs, and every task of an isolated [run](runs.md) carries the contract of its role. Catalog compilation is separate from task creation and does not launch workers.

## Creation And Frozen Context

A coordinator freezes a contract on a delegated task with `alera orchestration delegate --profile <name> --spec "<task brief>" --contract '<contract JSON>' --contract-inputs '<input JSON>'`. Both JSON flags are required together and are parsed before anything is created.

The CLI uses the distinct `orchestration.taskCreateContracted` RPC, so a host without that operation rejects it instead of silently creating an uncontracted task. `orchestration.taskCreate` creates uncontracted tasks and rejects contract fields.

The runtime validates the contract and inputs before inserting the task. It stores the whole definition and concrete inputs in an immutable `role_contract` snapshot with version and SHA-256 digest. Object-key ordering does not change the digest. Editing the source definition or retrying a worker does not replace the snapshot; changing a task's requirements requires a new task. Existing tasks have no snapshot and retain their original completion behavior.

Task reads include the snapshot. Worker context, dispatch preambles and coordinator dispatches include the frozen instructions and inputs. The bootstrap a delegated worker receives directs it to this context before starting. Profile launch snapshots remain independent; role contracts do not change profile resolution.

## Contract Format

This minimal example requires a report artifact and passing test evidence:

```json
{
  "version": 1,
  "id": "implementer",
  "revision": 1,
  "name": "Implementer",
  "purpose": "Implement a scoped change.",
  "instructions": "Preserve unrelated work and run focused tests.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "objective": { "type": "string", "minLength": 1 }
    },
    "required": ["objective"],
    "additionalProperties": false
  },
  "resultSchema": {
    "type": "object",
    "properties": {
      "summary": { "type": "string", "minLength": 1 }
    },
    "required": ["summary"]
  },
  "requiredArtifacts": ["docs/result.md"],
  "checklist": [
    { "id": "tests", "description": "Focused tests pass." }
  ]
}
```

The corresponding inputs are `{"objective":"Fix the reported bug"}`. Contract and checklist identifiers contain 1-80 ASCII letters, digits, dots, hyphens or underscores. Revisions are positive integers. Unknown contract fields are rejected. Artifacts are exact, forward-slash-separated workspace-relative file paths: absolute paths, traversal, empty components, backslashes, control characters, Git metadata and nonportable Windows names are rejected. Artifact declarations cannot collide case-insensitively.

## Supported Schemas And Limits

Both schemas have an object root and use the following explicit JSON Schema 2020-12 subset. Each schema node declares one string-valued `type`:

| Type | Supported constraints |
| --- | --- |
| All | `title`, `description`, `enum`, `const` |
| Object | `properties`, `required`, boolean `additionalProperties`, `minProperties`, `maxProperties` |
| Array | Required `items` schema, `minItems`, `maxItems` |
| String | `minLength`, `maxLength` |
| Integer or number | `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum` |
| Boolean or null | No additional type-specific constraints |

Required property names must have definitions. References, remote includes, regular expressions, formats, schema combinators and executable hooks are not supported. The contract is at most 64 KiB; each input or result is at most 256 KiB. JSON has at most 4,096 nodes and depth 24; each schema has at most 128 schema nodes and depth 12. Contracts allow at most 64 required artifacts and 64 checklist entries. Limits bound runtime validation work independently of repository size.

## Completion Evidence

Use `complete` with a nonempty `--summary` (the kind defaults to `success`), an `--artifacts` JSON array of relative path strings and a `--validation` JSON array of objects. These fields are optional for an uncontracted task and required here. Every checklist id must occur exactly once, with `passed: true` and nonempty `evidence`. Each required artifact must be present exactly as declared. `filesModified` (`--files`, comma-separated) remains an array of strings, and additional schema-defined result fields can be supplied with `--result-extra`.

```bash
alera orchestration complete --summary "Fixed the bug; focused tests pass." --artifacts '["docs/result.md"]' --validation '[{"id":"tests","passed":true,"evidence":"cargo test: 3 passed"}]' --files "src/feature.rs"
```

The result must also satisfy `resultSchema`. Omitted standard arrays are stored as `[]` before validation. A schema using `additionalProperties: false` must explicitly allow the standard result fields: `summary`, `completionKind`, `artifacts`, `filesModified` and `validation`. Completion validates reported structured evidence; it does not execute tests, prove an artifact's filesystem contents or attest that a worker's claims are true.

Validation occurs before task and dispatch completion in the same store transaction. Invalid completion leaves the task and dispatch active and dependents pending. Generic task status edits and messages cannot bypass this requirement. Repeated successful dispatch completion is idempotent and cannot replace persisted evidence; completed contracted tasks cannot be reopened through the generic status setter.

Failure reporting through `complete --kind failure` and cancellation remain available without successful artifacts or checklist evidence. A retry retains the original snapshot. On its own, a contract adds no plan approval, stage gates, task worktrees or integration; those belong to [runs](runs.md) and their recipes.
