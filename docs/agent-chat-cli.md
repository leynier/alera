# Agent Chat CLI And MCP

The human-facing CLI group is `alera agent-chat`; live agent delegation remains `alera chat`. Both use the runtime host. The ordinary local and cloud MCP catalogs expose Agent Chat controls separately from the private `chat_*` tools injected into provider sessions. A chat-bound credential cannot use direct controls or administer Settings. Never remove its binding or start an unbound server to bypass a refusal.

## Request Input And Retries

Use `alera agent-chat --json <operation>` with optional `--chat-id`, `--workspace-id`, and `--host-id` selectors. There is no implicit workspace, chat, or host selection from a terminal's environment. Complex fields use exactly one of `--payload '<json>'`, `--payload-file <path>`, or `--payload-stdin`. The payload must be a JSON object of at most 256 KiB. A field supplied in both the payload and a flag is rejected. The host derives caller identity; `actor` and `scope` are refused.

Every mutation carries `requestId`. Pass `--request-id <stable-id>` before the first call and reuse it with the same payload after a timeout or unclear response. A fresh ID is generated when omitted. `send` uses that ID as `clientMessageId` unless supplied explicitly. A new retry ID can duplicate an action. Settings edits additionally require the current `expectedRevision`; after a conflict, reread and reconcile the intended edit before trying again.

## Catalog And Lifecycle

| Operation | Payload fields beyond selectors | Behavior |
| --- | --- | --- |
| `providers` | `refresh?`, `refreshModels?` | Read provider status/models; `refresh:true` explicitly refreshes host status. |
| `list` | `includeArchived?` | Read active or archived chat summaries. |
| `create` | `workspaceId`, `provider?`, `providerInstanceId?`, `model?`, `reasoningEffort?`, `runtimeMode?`, `interactionMode?`, `title?` | Persist a stopped draft. No provider starts until its first send. |
| `snapshot` | `chatId` | Read the bounded current state. |
| `history` | `chatId`, `before`, `limit?` | Page older transcript items using the host's `historyBefore` token. |
| `payload` | `chatId`, `itemId`, `index?`, `limit?` | Explicitly load retained native data in bounded pages; `index` starts at zero. |
| `send` | `chatId`, `text?`, `attachments?`, `delivery?`, `model?`, `reasoningEffort?`, `interactionMode?`, `clientMessageId?` | Require text or attachments. Delivery is `auto`, `queue`, or native `steer`. |
| `configure` | `chatId`, at least one of `provider`, `providerInstanceId`, `model`, `reasoningEffort`, `runtimeMode`, `interactionMode` | Change selection without starting the selected provider. |
| `rename` | `chatId`, `title` | Persist a user title. |
| `interrupt` | `chatId`, `turnId?` | Interrupt the active turn without archiving. |
| `respond` | `chatId`, `runtimeRequestId`, `response` | Use exactly the decisions and response shape the runtime offered. |
| `recover` | `chatId`, `mode?` | Recover using a supported mode; never-sent drafts remain stopped. |
| `close` | `chatId` | Discard a never-sent draft, otherwise archive and stop its provider. |
| `reopen` | `chatId` | Reopen an archived chat. |

Omit `model` on create/send to use the instance or provider default. On configure, omission preserves selection and `model:null` resets it. `--reset-model` expresses that reset; never send an empty model ID. `reasoningEffort:null` similarly resets effort on configure. Effort requires `agentChatEffortV1` and actual provider/model support. Unselected draft creation additionally requires `agentChatUnselectedDraftV1`. Creation, configure, recover, and close require `agentChatDeferredStartV1` so the CLI does not promise deferred behavior against an older runtime.

History, approval history, and native payload pages default to 100 items and accept 1 to 500, also expressible as `--limit`; host-specific caps may be lower. Use returned cursors instead of reconstructing them. Snapshots and provider payloads remain bounded by the host. Chat acceptance proves persistence/admission, not provider authentication, inference success, or completed work.

```sh
alera agent-chat --json create --workspace-id <workspace-id> --request-id draft-1
alera agent-chat --json configure --chat-id <chat-id> --reset-model --request-id model-default-1
alera agent-chat --json send --chat-id <chat-id> --payload-file message.json --request-id message-1
```

## Queue And History Operations

| Operation | Required payload fields beyond `chatId` | Capability |
| --- | --- | --- |
| `queue-cancel` | `queueId` | `agentChatV1` |
| `queue-edit` | `queueId`, `text` | `agentChatQueueEditV1` |
| `queue-steer` | `queueId`, exact active `turnId` | `agentChatQueueSteerV1` |
| `fork` | `turnId`, optional `title` | `agentChatForkV1` |
| `rewind` | `turnId`, optional `mode:transcript` (default) | `agentChatRewindV1` |
| `rewind` with `mode:native` | `turnId`, explicit `mode:native` | `agentChatNativeRewindV1` |
| `rewind-files` | `turnId` | `agentChatRewindFilesV1` |
| `file-checkpoints-configure` | Boolean `enabled` | `agentChatFileCheckpointsV1` |
| `native-history-operation` (read) | Optional `operationId` | `agentChatNativeHistoryV1` |
| `native-history-reconcile` | `operationId`, `action`, optional nonnegative `expectedRevision` | `agentChatNativeHistoryV1` |
| `delete` | None; the chat must be archived | `agentChatDeleteV1` |
| `approval-history` | Optional `before`, `limit` | `agentChatApprovalHistoryV1` |
| `turn-diff` | `turnId` | `agentChatTurnDiffV1` |
| `mark-read` | Nonnegative `cursor` | `agentChatReadCursorV1` |

Queue edit preserves attachments. Queue steering is atomic and uses native steering only; unsupported providers refuse it and stale turn IDs must not consume the queue entry. Fork, rewind, and delete are independently gated. Declaring a provider method does not establish support. Conversation rewind must not be described as filesystem rollback; inspect the result's filesystem-reversion disclosure. Turn diff is the retained provider projection, not proof that files were reverted. Mark Read advances host-shared read state.

Transcript rewind is the default and never becomes native implicitly. Native conversation rewind requires the provider's exact supported boundary; file rewind is a separate operation and changes files without rolling conversation history back. File checkpoint configuration takes an explicit boolean and relies on the host/provider's availability and idle-state checks. Provider acknowledgement and verified file effects remain separate evidence; missing file-effect evidence does not establish a successful file rollback.

Native mutations carry a stable `requestId`. After a timeout, restart, or uncertain provider result, do not repeat native rewind/file rewind, including with a new ID. Read `native-history-operation` first, using the retained `operationId` when known. A missing operation ID reads the current pending operation. MCP failures for native rewind, file rewind, and reconciliation are marked non-retryable and direct callers to this observation step. Choose only an action the operation's `recovery` flags allow, as a new explicit reconciliation request with its own stable retry ID. `expectedRevision` is optional; use it only when an authoritative revision is available.

| Reconciliation action | Allowed evidence and effect |
| --- | --- |
| `finishAcknowledged` | The provider acknowledgement is stored; finalize locally without repeating provider I/O. |
| `cancelUnstarted` | The intent is still prepared and no provider call began; cancel it. |
| `restartFromTranscript` | A native conversation rewind is uncertain; explicitly restart from the retained transcript instead of replaying native rollback. |
| `continueFromCurrentFiles` | A file rewind is uncertain; explicitly continue with current files, without claiming they were reverted. |

## Preferences, Instances, And Secrets

`preferences-get` reads host-shared preferences. `preferences-update` takes `expectedRevision` and a nonempty `operations` array. Each operation uses `type`: `setDefaultSelection {selection}`, `setProjectDefault {projectId,selection}`, `setModels {providerInstanceId,hidden,order}`, or `setFavorites {favorites}`. A null selection clears a default. Remembered selection is written by the host after first send, not by callers. These operations require `agentChatPreferencesV1`.

`provider-instances-get` reads Settings envelopes without secret values. `provider-instances-upsert` takes `expectedRevision` and `instance`, whose identity is `providerInstanceId`. `provider-instances-removal-impact` takes `providerInstanceId`; inspect it before authorized `provider-instances-remove {expectedRevision,providerInstanceId,allowInUse?}`. Removal can affect existing chats; do not infer permission from a request to inspect Settings. These verbs require `agentChatProviderSettingsV1`.

`secrets-set` takes `{expectedRevision,providerInstanceId,name,value}` from `--payload-file` or `--payload-stdin` only. Never put a secret into an argument, transcript, log, or checked-in file. `secrets-clear` takes the same identity/revision without `value`. Secret names must be declared by the instance. Secret values are write-only and are absent from Settings responses and events. Paired phones can change preferences, supported instance fields, and declared secrets; launch-definition editing and instance removal remain desktop-only. Remote human administration uses an explicit `hostId` and the target host's existing permissions.

## MCP Parity

Every tool takes `{operation,payload}` and the cloud edge adds its normal `runtime` selector. The payload uses the same canonical fields as the CLI and travels on stdin. Mutable tools accept `clientRequestId`, mapped to `--request-id`; never put `requestId` into their payload.

- `agent_chat_query`: `providers`, `list`, `snapshot`, `history`, `payload`, `approval-history`, `turn-diff`, `native-history-operation`; read access.
- `agent_chat_control`: creation, messaging, configuration, runtime responses, recovery, close/reopen, queue controls, fork/rewind/delete, `rewind-files`, `file-checkpoints-configure`, `native-history-reconcile`, and mark-read; execute access. The tool conservatively advertises destructive operations because close, rewind, file rewind, and delete share this group. Native history bodies expose exact modes/actions and fields in the schema.
- `agent_chat_settings_read`: preferences, instances, and removal impact; admin access because launch definitions can expose host configuration.
- `agent_chat_settings_update`: preference operations, instance upsert/remove, and secret set/clear; admin access, retry ID, and revision required.

The injected chat server contains none of these four tools. Its existing `chat_configure` accepts `resetModel:true` or `resetReasoningEffort:true`, separately from concrete selection values, and preserves its caller's lineage and runtime-mode ceiling. Background task/wake delivery remains idle-only and never selects a workspace or tab.
