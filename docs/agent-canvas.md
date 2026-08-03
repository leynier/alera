# Agent Canvas

Agent Canvas is the shared runtime surface for structured agent progress, decisions, validation results, and registered artifacts. The public feature name is Agent Canvas. The CLI entry point is `alera canvas`, and the installable agent skill is `agent-canvas`.

## Runtime contract

The runtime host owns the durable canvas state. A canvas is identified by the workspace id and terminal session id, with an optional tab id and agent type. Revisions are monotonic and use optimistic `expectedRevision` checks. A failed publish leaves the last valid revision visible. Identical consecutive documents are coalesced.

The host advertises the additive `agentCanvasV1` capability and serves `agentCanvas.*` requests. This capability does not change the terminal host protocol version, so an older host remains usable for existing features. The app shows a compatibility message when the connected host does not support Agent Canvas.

Active canvases are grouped as Waiting or Live. Completed and orphaned canvases remain available for 24 hours unless pinned. Closing freezes a canvas. A pinned canvas remains available until the user removes it.

## Publishing

Agents can publish one JSON document or JSON Lines through the CLI:

```text
alera canvas publish --workspace-id WORKSPACE_ID --terminal-session-id TERMINAL_SESSION_ID --file canvas.json
alera canvas publish --workspace-id WORKSPACE_ID --terminal-session-id TERMINAL_SESSION_ID --stdin
```

The document is data only. The accepted component set is `AgentRunHeader`, `TaskProgress`, `DecisionRequest`, `ChangeSummary`, `FileReferenceList`, `ValidationResults`, `RiskSummary`, `ArtifactCard`, `Notice`, and `ActionGroup`. The host enforces document size, component count, decision count, revision expectations, and publish rate limits.

Decision gates are durable and idempotent. `alera canvas wait` polls without cancelling the gate when its timeout expires. A timeout reports `cancelled: false`; the agent can continue waiting or inspect the canvas later.

## Actions and safety

Canvas actions are typed and allowlisted. Immediate actions include opening workspace-local files or diffs, focusing the owning terminal, opening a pull request or registered artifact, copying text, and switching context panels. Controlled actions require confirmation. Destructive actions require strong confirmation and are scoped to the owning canvas and registered resources.

Arbitrary shell commands, functions, source code, URLs, process requests, absolute paths, and workspace deletion are not part of the Agent Canvas contract. The Flutter renderer treats documents as data and renders only the pinned component version.

## CLI discovery

Use `alera canvas capabilities`, `alera canvas catalog`, and `alera canvas examples` to discover the supported contract. Use `alera canvas events --follow` for reconnectable event polling, and `alera canvas complete` or `alera canvas close` to finalize a run.
