//! CLI request metadata shared with the administrative MCP surface.

use crate::agent_chat_commands_args::{AgentChatAction, AgentChatRequestArgs};

pub(crate) const QUERY_OPERATIONS: &[&str] = &[
    "providers",
    "list",
    "snapshot",
    "history",
    "payload",
    "approval-history",
    "turn-diff",
    "native-history-operation",
];
pub(crate) const CONTROL_OPERATIONS: &[&str] = &[
    "create",
    "send",
    "configure",
    "rename",
    "interrupt",
    "respond",
    "recover",
    "close",
    "reopen",
    "queue-cancel",
    "queue-edit",
    "queue-steer",
    "fork",
    "rewind",
    "rewind-files",
    "file-checkpoints-configure",
    "native-history-reconcile",
    "delete",
    "mark-read",
];
pub(crate) const SETTINGS_READ_OPERATIONS: &[&str] = &[
    "preferences-get",
    "provider-instances-get",
    "provider-instances-removal-impact",
];
pub(crate) const SETTINGS_UPDATE_OPERATIONS: &[&str] = &[
    "preferences-update",
    "provider-instances-upsert",
    "provider-instances-remove",
    "secrets-set",
    "secrets-clear",
];

pub(crate) struct RequestSpec {
    pub(crate) suffix: &'static str,
    pub(crate) capability: &'static str,
    pub(crate) required: &'static [&'static str],
    pub(crate) fields: &'static [&'static str],
}

pub(crate) fn spec(operation: &str) -> RequestSpec {
    let (suffix, capability, required, fields): (_, _, &[&str], &[&str]) = match operation {
        "providers" => (
            "providers",
            "agentChatV1",
            &[],
            &["refresh", "refreshModels"],
        ),
        "list" => ("list", "agentChatV1", &[], &["includeArchived"]),
        "create" => (
            "create",
            "agentChatDeferredStartV1",
            &["workspaceId"],
            &[
                "provider",
                "providerInstanceId",
                "model",
                "reasoningEffort",
                "runtimeMode",
                "interactionMode",
                "title",
            ],
        ),
        "snapshot" => ("snapshot", "agentChatV1", &["chatId"], &[]),
        "history" => (
            "history",
            "agentChatV1",
            &["chatId", "before"],
            &["before", "limit"],
        ),
        "payload" => (
            "payload",
            "agentChatV1",
            &["chatId", "itemId"],
            &["itemId", "index", "limit"],
        ),
        "send" => (
            "send",
            "agentChatV1",
            &["chatId"],
            &[
                "text",
                "attachments",
                "delivery",
                "clientMessageId",
                "model",
                "reasoningEffort",
                "interactionMode",
            ],
        ),
        "configure" => (
            "configure",
            "agentChatDeferredStartV1",
            &["chatId"],
            &[
                "provider",
                "providerInstanceId",
                "model",
                "reasoningEffort",
                "runtimeMode",
                "interactionMode",
            ],
        ),
        "rename" => ("rename", "agentChatV1", &["chatId", "title"], &["title"]),
        "interrupt" => ("interrupt", "agentChatV1", &["chatId"], &["turnId"]),
        "respond" => (
            "respond",
            "agentChatV1",
            &["chatId", "runtimeRequestId", "response"],
            &["runtimeRequestId", "response"],
        ),
        "recover" => (
            "recover",
            "agentChatDeferredStartV1",
            &["chatId"],
            &["mode"],
        ),
        "close" => ("close", "agentChatDeferredStartV1", &["chatId"], &[]),
        "reopen" => ("reopen", "agentChatV1", &["chatId"], &[]),
        "queue-cancel" => (
            "queueCancel",
            "agentChatV1",
            &["chatId", "queueId"],
            &["queueId"],
        ),
        "queue-edit" => (
            "queueEdit",
            "agentChatQueueEditV1",
            &["chatId", "queueId", "text"],
            &["queueId", "text"],
        ),
        "queue-steer" => (
            "queueSteer",
            "agentChatQueueSteerV1",
            &["chatId", "queueId", "turnId"],
            &["queueId", "turnId"],
        ),
        "fork" => (
            "fork",
            "agentChatForkV1",
            &["chatId", "turnId"],
            &["turnId", "title"],
        ),
        "rewind" => (
            "rewind",
            "agentChatRewindV1",
            &["chatId", "turnId"],
            &["turnId", "mode"],
        ),
        "rewind-files" => (
            "rewindFiles",
            "agentChatRewindFilesV1",
            &["chatId", "turnId"],
            &["turnId"],
        ),
        "file-checkpoints-configure" => (
            "fileCheckpoints.configure",
            "agentChatFileCheckpointsV1",
            &["chatId", "enabled"],
            &["enabled"],
        ),
        "native-history-operation" => (
            "nativeHistory.operation",
            "agentChatNativeHistoryV1",
            &["chatId"],
            &["operationId"],
        ),
        "native-history-reconcile" => (
            "nativeHistory.reconcile",
            "agentChatNativeHistoryV1",
            &["chatId", "operationId", "action"],
            &["operationId", "expectedRevision", "action"],
        ),
        "delete" => ("delete", "agentChatDeleteV1", &["chatId"], &[]),
        "approval-history" => (
            "approvalHistory",
            "agentChatApprovalHistoryV1",
            &["chatId"],
            &["before", "limit"],
        ),
        "turn-diff" => (
            "turnDiff",
            "agentChatTurnDiffV1",
            &["chatId", "turnId"],
            &["turnId"],
        ),
        "mark-read" => (
            "markRead",
            "agentChatReadCursorV1",
            &["chatId", "cursor"],
            &["cursor"],
        ),
        "preferences-get" => ("preferences.get", "agentChatPreferencesV1", &[], &[]),
        "preferences-update" => (
            "preferences.update",
            "agentChatPreferencesV1",
            &["expectedRevision", "operations"],
            &["expectedRevision", "operations"],
        ),
        "provider-instances-get" => (
            "providerInstances.get",
            "agentChatProviderSettingsV1",
            &[],
            &[],
        ),
        "provider-instances-upsert" => (
            "providerInstances.upsert",
            "agentChatProviderSettingsV1",
            &["expectedRevision", "instance"],
            &["expectedRevision", "instance"],
        ),
        "provider-instances-removal-impact" => (
            "providerInstances.removalImpact",
            "agentChatProviderSettingsV1",
            &["providerInstanceId"],
            &["providerInstanceId"],
        ),
        "provider-instances-remove" => (
            "providerInstances.remove",
            "agentChatProviderSettingsV1",
            &["expectedRevision", "providerInstanceId"],
            &["expectedRevision", "providerInstanceId", "allowInUse"],
        ),
        "secrets-set" => (
            "secrets.set",
            "agentChatProviderSettingsV1",
            &["expectedRevision", "providerInstanceId", "name", "value"],
            &["expectedRevision", "providerInstanceId", "name", "value"],
        ),
        "secrets-clear" => (
            "secrets.clear",
            "agentChatProviderSettingsV1",
            &["expectedRevision", "providerInstanceId", "name"],
            &["expectedRevision", "providerInstanceId", "name"],
        ),
        _ => unreachable!("CLI and MCP operation names are closed enums"),
    };
    RequestSpec {
        suffix,
        capability,
        required,
        fields,
    }
}

pub(crate) fn is_mutation(operation: &str) -> bool {
    CONTROL_OPERATIONS.contains(&operation) || SETTINGS_UPDATE_OPERATIONS.contains(&operation)
}

pub(crate) fn required_capability(operation: &str, payload: &serde_json::Value) -> &'static str {
    if operation == "rewind" && payload["mode"] == "native" {
        "agentChatNativeRewindV1"
    } else {
        spec(operation).capability
    }
}

impl AgentChatAction {
    pub(crate) fn into_parts(self) -> (&'static str, AgentChatRequestArgs) {
        match self {
            Self::Providers(args) => ("providers", args),
            Self::List(args) => ("list", args),
            Self::Create(args) => ("create", args),
            Self::Snapshot(args) => ("snapshot", args),
            Self::History(args) => ("history", args),
            Self::Payload(args) => ("payload", args),
            Self::Send(args) => ("send", args),
            Self::Configure(args) => ("configure", args),
            Self::Rename(args) => ("rename", args),
            Self::Interrupt(args) => ("interrupt", args),
            Self::Respond(args) => ("respond", args),
            Self::Recover(args) => ("recover", args),
            Self::Close(args) => ("close", args),
            Self::Reopen(args) => ("reopen", args),
            Self::QueueCancel(args) => ("queue-cancel", args),
            Self::QueueEdit(args) => ("queue-edit", args),
            Self::QueueSteer(args) => ("queue-steer", args),
            Self::Fork(args) => ("fork", args),
            Self::Rewind(args) => ("rewind", args),
            Self::RewindFiles(args) => ("rewind-files", args),
            Self::FileCheckpointsConfigure(args) => ("file-checkpoints-configure", args),
            Self::NativeHistoryOperation(args) => ("native-history-operation", args),
            Self::NativeHistoryReconcile(args) => ("native-history-reconcile", args),
            Self::Delete(args) => ("delete", args),
            Self::ApprovalHistory(args) => ("approval-history", args),
            Self::TurnDiff(args) => ("turn-diff", args),
            Self::MarkRead(args) => ("mark-read", args),
            Self::PreferencesGet(args) => ("preferences-get", args),
            Self::PreferencesUpdate(args) => ("preferences-update", args),
            Self::ProviderInstancesGet(args) => ("provider-instances-get", args),
            Self::ProviderInstancesUpsert(args) => ("provider-instances-upsert", args),
            Self::ProviderInstancesRemovalImpact(args) => {
                ("provider-instances-removal-impact", args)
            }
            Self::ProviderInstancesRemove(args) => ("provider-instances-remove", args),
            Self::SecretsSet(args) => ("secrets-set", args),
            Self::SecretsClear(args) => ("secrets-clear", args),
        }
    }
}
