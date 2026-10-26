# Agent Chats

These four tools belong to the ordinary local/cloud MCP catalog for human-authorized work. They are excluded from the private credential-bound chat server. Never remove a binding or reconnect with broader authority to bypass a refusal. Name the edge's `runtime` when ambiguous; name `hostId`, `workspaceId`, and `chatId` explicitly inside the payload as applicable. Caller identity is host-derived, never a supplied actor or scope.

Every tool takes `{operation,payload}`. The payload is a canonical Agent Chat request object of at most 256 KiB and travels on stdin. Mutable calls take `clientRequestId` outside the payload, mapped to the host retry ID. Choose it before the first attempt and reuse it with unchanged fields after an unclear answer. Do not pass `requestId` in the payload. Settings edits also require the current `expectedRevision`; reconcile conflicts before retrying.

## Read And Control Chats

`agent_chat_query` requires read access. Operations are `providers`, `list`, `snapshot`, `history`, `payload`, `approval-history`, `turn-diff`, and `native-history-operation`.

- `providers` accepts optional `hostId`, `workspaceId`, `refresh:true`, and `refreshModels:true`. Refresh explicitly rechecks host status; model discovery needs provider support.
- `list` accepts optional selectors and `includeArchived:true`. `snapshot` needs `chatId`.
- `history` needs `chatId,before` using the returned history token. Native `payload` needs `chatId,itemId` and optional nonnegative `index`. These pages and approval history default to 100 items and accept `limit` from 1 to 500; the host can cap lower.
- `approval-history` needs `chatId` and optional `before,limit`, gated by `agentChatApprovalHistoryV1`. `turn-diff` needs `chatId,turnId` with `agentChatTurnDiffV1`; it reads retained provider changes, not proof of filesystem rollback.

`agent_chat_control` requires full/execute access. Its operation enum includes `create`, `send`, `configure`, `rename`, `interrupt`, `respond`, `recover`, `close`, `reopen`, `queue-cancel`, `queue-edit`, `queue-steer`, `fork`, `rewind`, `rewind-files`, `file-checkpoints-configure`, `native-history-reconcile`, `delete`, and `mark-read`. The shared tool advertises destructive operations conservatively; perform only the requested scope.

- `create` needs `workspaceId`; optional selection fields are `providerInstanceId`, `provider`, `model`, `reasoningEffort`, `runtimeMode`, `interactionMode`, and `title`. It persists a stopped draft; first send starts the provider. Creating an unselected draft additionally requires `agentChatUnselectedDraftV1`.
- `send` needs `chatId` and text or attachments; optional `delivery` is `auto`, `queue`, or native `steer`. Acceptance proves persistence/admission, not provider authentication, inference success, or completion.
- `configure` needs `chatId` and at least one selection field. Omit model on create/send for provider default; configure omission preserves it, while `model:null` resets it. `reasoningEffort:null` resets effort on configure. Never send an empty ID. Effort needs `agentChatEffortV1` and actual adapter/model support.
- `rename` needs `chatId,title`; `interrupt` needs `chatId` with optional `turnId`; `respond` needs `chatId,runtimeRequestId,response` using exact offered decisions; when the request lists `supportsFeedback`, a `decline` or `cancel` may add `feedback` text for the agent that asked. `recover` takes `chatId` and optional supported mode. `close` discards a never-sent draft or archives history; `reopen` restores an archived chat. Creation/configure/recover/close require `agentChatDeferredStartV1`.
- `queue-cancel` needs `chatId,queueId`. `queue-edit` additionally needs `text` with `agentChatQueueEditV1` and preserves attachments. `queue-steer` needs exact `chatId,queueId,turnId` with `agentChatQueueSteerV1`; it is atomic and native-only, never emulated by cancel plus send.
- `fork` needs `chatId,turnId` and optional `title`; `rewind` needs `chatId,turnId`; `delete` needs an archived `chatId`. Their independent gates are `agentChatForkV1`, `agentChatRewindV1`, and `agentChatDeleteV1`. Conversation rewind does not promise file reversion; inspect the host disclosure. Unsupported providers refuse rather than pretending success.
- `mark-read` needs `chatId` and nonnegative `cursor` with `agentChatReadCursorV1`; read state is shared by the host. Background events never select a workspace or chat.

## Native History And Ambiguity

Rewind's optional `mode` is `transcript` by default; only explicit `mode:native` performs native conversation rollback with independent `agentChatNativeRewindV1`. `rewind-files {chatId,turnId}` uses `agentChatRewindFilesV1` and changes provider-tracked files separately from conversation history. `file-checkpoints-configure {chatId,enabled}` requires an explicit boolean and `agentChatFileCheckpointsV1`; host/provider support and idle-state checks remain authoritative. Provider acknowledgement does not establish verified file effects.

Read `native-history-operation {chatId,operationId?}` through the query tool under `agentChatNativeHistoryV1`. Omit operationId for the current pending operation. After a timeout, interrupted process, or uncertain native result, do not repeat rollback or file rewind, even with a new ID. MCP failures for native rewind, file rewind, and reconciliation are non-retryable and direct callers to inspect the durable operation first. Operation reads can be retried safely.

Use `native-history-reconcile {chatId,operationId,expectedRevision?,action}` through the control tool, with the same capability and its own stable `clientRequestId`. The action must be one offered by the host's recovery flags: `finishAcknowledged` finalizes a stored acknowledgement without provider I/O; `cancelUnstarted` cancels a prepared intent before provider I/O; `restartFromTranscript` explicitly falls back after uncertain conversation rollback; `continueFromCurrentFiles` explicitly keeps current files after uncertain file rewind. Never claim file reversion from an uncertain result. Expected revision is optional, nonnegative, and supplied only from authoritative evidence. Exact native operation schemas reject unknown fields or actions.

## Host Settings

`agent_chat_settings_read` requires admin access because launch definitions expose host configuration. Operations are `preferences-get`, `provider-instances-get`, and `provider-instances-removal-impact`. The impact payload needs `providerInstanceId`; inspect it before authorized instance removal and report affected chats. Provider envelopes never contain secret values.

`agent_chat_settings_update` requires admin access, `clientRequestId`, and `expectedRevision` in the payload. Preference operations require `agentChatPreferencesV1`; provider/secret operations require `agentChatProviderSettingsV1`.

- `preferences-update` takes nonempty `operations` using `type`: `setDefaultSelection {selection}`, `setProjectDefault {projectId,selection}`, `setModels {providerInstanceId,hidden,order}`, and `setFavorites {favorites}`. Null selection clears a default. Remembered selection remains host-owned.
- `provider-instances-upsert` takes `instance` with `providerInstanceId`. `provider-instances-remove` takes `providerInstanceId` and optional `allowInUse`; do not infer removal permission from a request to inspect Settings.
- `secrets-set` takes `providerInstanceId,name,value`; `secrets-clear` omits value. The instance must declare the name. Values remain write-only and travel on stdin, never arguments. Never repeat them in responses, logs, or diagnostics.

Paired phones can change supported preferences, instance fields, and declared secrets, while launch-definition editing and instance removal remain desktop-only. An explicit `hostId` targets a connected host under existing permissions. Chat-bound agents have none of these Settings tools or permissions.
