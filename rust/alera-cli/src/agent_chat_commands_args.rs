use clap::{Args, Subcommand};

use crate::cli::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct AgentChatCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: AgentChatAction,
}

#[derive(Debug, Subcommand)]
pub enum AgentChatAction {
    /// Read the provider catalog; payload can request refresh or refreshModels.
    Providers(AgentChatRequestArgs),
    /// List chats, optionally including archived chats.
    List(AgentChatRequestArgs),
    /// Persist a draft without starting a provider.
    Create(AgentChatRequestArgs),
    /// Read a bounded chat snapshot.
    Snapshot(AgentChatRequestArgs),
    /// Read an older history page using before and limit.
    History(AgentChatRequestArgs),
    /// Read a bounded native-data continuation page.
    Payload(AgentChatRequestArgs),
    /// Send text and optional validated attachments.
    Send(AgentChatRequestArgs),
    /// Configure an idle chat; --reset-model selects the provider default.
    Configure(AgentChatRequestArgs),
    /// Rename a chat without replacing a user title later.
    Rename(AgentChatRequestArgs),
    /// Interrupt a turn without closing the chat.
    Interrupt(AgentChatRequestArgs),
    /// Answer a runtime approval, question or elicitation.
    Respond(AgentChatRequestArgs),
    /// Recover a stopped chat; a never-sent draft starts no provider.
    Recover(AgentChatRequestArgs),
    /// Close a chat, discarding a never-sent draft or archiving history.
    Close(AgentChatRequestArgs),
    /// Reopen an archived chat.
    Reopen(AgentChatRequestArgs),
    /// Remove one queued message.
    QueueCancel(AgentChatRequestArgs),
    /// Edit queued text while retaining its attachments.
    QueueEdit(AgentChatRequestArgs),
    /// Atomically steer queueId into the exact active turnId, natively only.
    QueueSteer(AgentChatRequestArgs),
    /// Fork at a turn if the provider supports native fork.
    Fork(AgentChatRequestArgs),
    /// Rewind conversation history if the provider supports it.
    Rewind(AgentChatRequestArgs),
    /// Explicitly rewind provider-tracked files without conversation rollback.
    RewindFiles(AgentChatRequestArgs),
    /// Enable or disable native file checkpoints for subsequent work.
    FileCheckpointsConfigure(AgentChatRequestArgs),
    /// Read the durable native history operation before resolving ambiguity.
    NativeHistoryOperation(AgentChatRequestArgs),
    /// Explicitly reconcile a native operation using the offered action.
    NativeHistoryReconcile(AgentChatRequestArgs),
    /// Delete an archived chat independently of workspace deletion.
    Delete(AgentChatRequestArgs),
    /// Read approval history with independent capability detection.
    ApprovalHistory(AgentChatRequestArgs),
    /// Read a turn's file-change projection.
    TurnDiff(AgentChatRequestArgs),
    /// Advance the host-shared read cursor.
    MarkRead(AgentChatRequestArgs),
    /// Read host-shared chat preferences.
    PreferencesGet(AgentChatRequestArgs),
    /// Apply preference operations with expectedRevision.
    PreferencesUpdate(AgentChatRequestArgs),
    /// Read provider launch definitions without secret values.
    ProviderInstancesGet(AgentChatRequestArgs),
    /// Upsert an instance with expectedRevision.
    ProviderInstancesUpsert(AgentChatRequestArgs),
    /// Preview the chats affected by instance removal.
    ProviderInstancesRemovalImpact(AgentChatRequestArgs),
    /// Remove an instance with expectedRevision after checking its impact.
    ProviderInstancesRemove(AgentChatRequestArgs),
    /// Set a write-only secret from a JSON file or stdin, never an argument.
    SecretsSet(AgentChatRequestArgs),
    /// Clear a declared secret with expectedRevision.
    SecretsClear(AgentChatRequestArgs),
}

#[derive(Debug, Args)]
#[command(group(clap::ArgGroup::new("payload-source")
    .multiple(false).args(["payload", "payload_file", "payload_stdin"])))]
pub struct AgentChatRequestArgs {
    /// Structured request fields. See the Agent Chat CLI reference.
    #[arg(long, value_name = "json")]
    pub payload: Option<String>,
    #[arg(long = "payload-file", value_name = "path")]
    pub payload_file: Option<String>,
    #[arg(long = "payload-stdin")]
    pub payload_stdin: bool,
    /// Stable retry key; a fresh id is generated for mutations when omitted.
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    #[arg(long = "model", conflicts_with = "reset_model")]
    pub model: Option<String>,
    /// Configure only: send model:null rather than omitting model.
    #[arg(long = "reset-model")]
    pub reset_model: bool,
    #[arg(long, value_parser = clap::value_parser!(u64).range(1..=500))]
    pub limit: Option<u64>,
}
