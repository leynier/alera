# Agent Chats

Use `alera agent-chat --json <operation>` for authorized human chat controls and host Settings. Bound agents use `alera chat` for lineage-scoped work; never remove their credential binding to reach human controls. There is no implicit workspace/chat/host from the terminal environment. Name exact `--chat-id`, `--workspace-id`, and `--host-id` selectors as applicable.

## Input And Retry Identity

Complex fields use one of `--payload '<json>'`, `--payload-file <path>`, or `--payload-stdin`. Input must be a JSON object of at most 256 KiB. Duplicate fields in flags and payload are rejected. The host supplies actor/scope; callers cannot impersonate either.

All mutations accept `--request-id <stable-id>`; choose it before the first attempt and reuse it with the same payload after an unclear result. Omission generates a fresh ID, so repeating a command without a key can duplicate effects. Send also derives `clientMessageId` from that key unless explicitly supplied. Settings writes require the current `expectedRevision` and reject stale edits.

## Catalog And Chat Controls

- `providers` reads the catalog. Payload `refresh:true` forces host status refresh; `refreshModels:true` requests discovery. `list` optionally takes `includeArchived:true`.
- `create --workspace-id <id>` persists a stopped draft without launching a provider. Optional payload fields are `providerInstanceId`, `provider`, `model`, `reasoningEffort`, `runtimeMode`, `interactionMode`, and `title`. The first `send` starts the provider. Unselected drafts require their own capability.
- `snapshot --chat-id <id>` reads state. `history` additionally needs the returned `before` token. `payload` needs `itemId` and optional nonnegative `index`. History, native payload, and approval-history pages default to 100, accept `--limit <1-500>`, and can be capped lower by the host.
- `send` needs text or validated attachments in its payload; `delivery` is `auto`, `queue`, or native `steer`.
- `configure` needs at least one of `provider`, `providerInstanceId`, `model`, `reasoningEffort`, `runtimeMode`, and `interactionMode`. Omit model on create/send for the provider default. On configure, omission preserves it; `--reset-model` or `model:null` resets it. `reasoningEffort:null` resets effort. Never send empty IDs; effort needs actual provider/model support and `agentChatEffortV1`.
- `rename` takes `title`; `interrupt` optionally takes `turnId`; `respond` takes `runtimeRequestId` and the exact offered `response`. `recover` takes optional supported `mode`. `close` discards a never-sent draft, otherwise archives it; `reopen` restores an archived chat.

Create, configure, recover, and close require `agentChatDeferredStartV1`. Acceptance proves persistence/admission, not provider authentication, inference success, or completion. Background work never selects a workspace/tab.

## Independent Queue And History Capabilities

`queue-cancel` takes `queueId`. `queue-edit` takes `queueId,text` and preserves attachments. `queue-steer` takes `queueId,turnId` and requires `agentChatQueueSteerV1` plus native steering support; stale turn IDs must not consume the entry. `fork` takes `turnId` and optional title; `rewind` takes `turnId`; `delete` requires an archived chat. They independently require `agentChatForkV1`, `agentChatRewindV1`, and `agentChatDeleteV1`. Conversation rewind does not imply filesystem rollback; inspect the host disclosure.

Rewind accepts payload `mode:transcript` (default) or explicit `mode:native`. Native mode independently requires `agentChatNativeRewindV1`, not the transcript gate. `rewind-files {turnId}` requires `agentChatRewindFilesV1` and changes provider-tracked files separately from conversation history. `file-checkpoints-configure {enabled}` requires a boolean and `agentChatFileCheckpointsV1`; the runtime verifies provider support and idle-state requirements. Acknowledgement of file rewind and verified file effects are separate results.

`native-history-operation {operationId?}` is read-only under `agentChatNativeHistoryV1`; omission reads the pending operation. After an ambiguous native result, timeout, or restart, inspect it instead of retrying provider rollback, even under a new ID. `native-history-reconcile {operationId,expectedRevision?,action}` uses the same capability and a new stable mutation retry ID. Action is exactly `finishAcknowledged`, `restartFromTranscript`, `cancelUnstarted`, or `continueFromCurrentFiles`, selected only from the host's offered recovery flags. Finish finalizes stored acknowledgement without native I/O; cancel applies only before native I/O starts; transcript restart and continuing from current files are explicit fallbacks for uncertainty. Never claim successful file reversion from an uncertain result. Supply a nonnegative revision only when authoritative evidence provides one.

`approval-history` takes optional `before,limit` with `agentChatApprovalHistoryV1`. `turn-diff` takes `turnId` with `agentChatTurnDiffV1` and reads retained provider changes. `mark-read` takes a nonnegative `cursor` with `agentChatReadCursorV1`, advancing host-shared read state. `queue-edit` needs `agentChatQueueEditV1`. Unsupported operations remain explicit errors; never substitute a different destructive operation.

## Host Preferences And Providers

`preferences-get` reads defaults, models and favorites. `preferences-update` takes `{expectedRevision,operations}`. Operations use `type`: `setDefaultSelection {selection}`, `setProjectDefault {projectId,selection}`, `setModels {providerInstanceId,hidden,order}`, or `setFavorites {favorites}`. Null selection clears a default. Remembered selection is host-owned. Require `agentChatPreferencesV1`.

`provider-instances-get` reads launch definitions with no secret values. `provider-instances-upsert` takes `{expectedRevision,instance}`, whose identity is `providerInstanceId`. Before authorized `provider-instances-remove {expectedRevision,providerInstanceId,allowInUse?}`, inspect `provider-instances-removal-impact {providerInstanceId}` and report affected chats. Require `agentChatProviderSettingsV1`.

`secrets-set {expectedRevision,providerInstanceId,name,value}` accepts a JSON file or stdin only. Never put secrets in arguments, transcripts, logs, or checked-in files. `secrets-clear` takes the same fields without `value`. Names must be declared by the instance. Values remain write-only. A paired phone can manage supported preferences, instance fields, and declared secrets, while launch-definition editing and instance removal remain desktop-only. Remote human administration names `hostId` explicitly and uses existing host permissions.
