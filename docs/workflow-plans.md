# Reviewed workflow plans

Workflow plans extend the Rust orchestration runtime. They do not replace it or introduce another model client. The coordinator proposes a concrete DAG using the selected recipe and existing Agent Profiles. Preparation is durable and creates no executable tasks. Human approval atomically materializes immutable contracted tasks.

## Compatibility and rollout

The additive `workflowReviewedPlansV1` capability is independent of `orchestrationRunBoardV1` and `workflowRecipeCatalogV1`. Strict protocol versions are unchanged. A client must show Update Required when its host lacks the required capability; it must not fall back to legacy policy approval.

This layer supports preparation and authenticated review. Execution intentionally remains blocked until managed task worktrees and serial integration are implemented. Approval does not start a worker in the owner's shared workspace. The desktop launch and review screens are delivered in a later stack layer.

## Preparing a plan

Use `alera orchestration plans prepare --stdin` with a JSON document containing `requestId`, `workspaceId`, optional `runId` and `expectedRevision`, and `proposal`. Reuse the same request ID and contents after a timeout. A reused ID with different contents is rejected. Read the result with `alera orchestration plans show --run <id>`, optionally `--revision <number>`.

The proposal contains `objective`, an exact lowercase `sourceSha`, `recipeSource`, `expectedRecipeDigest`, `coordinatorProfileId`, a `roleProfiles` map, `maxConcurrent` (default four, maximum sixteen), and `tasks`. Each task declares `id`, `title`, `spec`, `stageId`, `roleId`, `dependsOn`, `inputs`, and optional `correctsTaskId`. Maximum plan size is 1 MiB and 128 tasks, subject to the contract JSON complexity limits.

Every recipe stage and role must be represented. Stage prerequisite edges are expanded into concrete task dependencies, then cycles and references are validated. Profiles, managed launch configuration, contracts and contract inputs must validate before persistence. The source commit must exist in the active local Git workspace. Uncommitted changes are excluded and left untouched.

The reviewed candidate contains exact recipe, contract and effective profile snapshots. Approval freezes those same reviewed contents, not a fresh catalog lookup. Later catalog edits cannot change the run. Frozen profile commands are local runtime data, not portable recipe exports.

## Desktop authorization

The control-file token authenticates ordinary local runtime access but cannot approve workflows. Neither `actor: app` nor the self-declared `clientKind` is evidence of desktop authorization.

The desktop native bridge and runtime use a separate 32-byte credential in the private runtime directory. It is published atomically, read without following symlinks, and kept out of control files, Dart values, worker environments, prompts and exports. Unix directories/files must be private; Windows additionally protects the file contents with user-scoped DPAPI, including in custom runtime locations. Raw key bytes have no logging or serialization API.

The runtime issues a five-minute challenge bound to the process boot, authenticated connection, run, revision, scope, plan digest, evidence digest and integration SHA. After explicit user action the local desktop bridge signs the complete decision and reason with HMAC-SHA256 and domain separation. The runtime verifies that proof, freshness and the current durable evidence in one serialized transaction. The CLI and RPC expose no signing operation. A consumed challenge returns its durable receipt on an exact retry, including after reconnect, without repeating mutations.

This authenticates possession of the desktop credential, not physical human presence. Worktrees are not OS sandboxes, and a malicious process with arbitrary access to the same OS user's files is outside this boundary. Strong same-user process isolation or hardware-backed attestation would be a separate security project.

## Revisions and human gates

Foundation and Product gates are always human decisions. A stage scope is `stage:<recipe-stage-id>`; the plan scope is `plan`. Stage gates require completed results and recorded integration and artifact evidence for that stage and its ancestors. Changed evidence or integration SHA invalidates an outstanding challenge.

Reject keeps dispatch blocked. Request Changes creates a traceable revision with the review reason and requires a new coordinator proposal before approval. Pending work is cancelled; completed evidence is not silently reopened. Corrections reference tasks from the same run and retain the original source commit. Active attempts must be stopped before a correction can be prepared.

Legacy policy-resolution and task mutation routes cannot bypass workflow membership, immutable definitions or the dispatch barrier. Creation, approval and retry receipts survive runtime reconnects and restarts. Orchestration reset removes run state while preserving the recipe and profile catalogs.
