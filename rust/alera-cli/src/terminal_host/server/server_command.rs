use serde_json::Value;

use crate::agent_status::AgentHookEvent;
use crate::ssh_bootstrap::SshTargetBootstrapProgress;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::session::PtyEvent;
use alera_core::runtime::{SshBootstrapStatus, WorkflowRecipeSource};

use super::{account_requests, push_delivery, runtime_mutations, ClientKind};

/// Messages processed serially by the single server actor. Every state mutation
/// happens here, which keeps session/client transitions deterministic.
pub enum ServerCommand {
    OwnerAutomationPrecheckFinished {
        operation_id: String,
    },
    AutomationPrecheckFinished {
        definition: Box<alera_core::runtime::AutomationDefinition>,
        run: Box<alera_core::runtime::AutomationRun>,
        host_id: String,
        path: String,
        result: Result<bool, String>,
    },
    AutomationCheckoutPrepared {
        definition: Box<alera_core::runtime::AutomationDefinition>,
        run: Box<alera_core::runtime::AutomationRun>,
        project: Box<alera_core::runtime::Project>,
        result: HostResult<alera_core::runtime::Workspace>,
    },
    RemoteTerminalLifecycleFinished {
        client_id: u64,
        request_id: i64,
        verb: String,
        payload: Value,
        result: HostResult<alera_core::runtime::TerminalLifecycleOperation>,
    },
    OwnerTerminalLifecycleFinished {
        client_id: u64,
        request_id: i64,
        operation_id: String,
        shutdown: crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown,
        result: HostResult<Value>,
    },
    RemoteSetupFinished {
        client_id: u64,
        request_id: i64,
        operation: &'static str,
        result: HostResult<Value>,
    },
    RemoteRecoveryFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    BufferGuardExpired {
        id: String,
    },
    RelayActivity {
        generation: u64,
        at: chrono::DateTime<chrono::Utc>,
    },
    RelayStatus {
        generation: u64,
        payload: Value,
    },
    ClientConnected {
        id: u64,
        handle: ClientHandle,
        kind: ClientKind,
    },
    RelayClientConnected {
        id: u64,
        handle: ClientHandle,
        client_id: String,
    },
    ClientLine {
        id: u64,
        line: String,
    },
    RelayClientLine {
        id: u64,
        line: String,
        accepted: tokio::sync::oneshot::Sender<()>,
        expires_at: i64,
    },
    ClientDisconnected {
        id: u64,
    },
    MobileStatusFinished {
        client_id: u64,
        request_id: i64,
        payload: Value,
    },
    Pty {
        session_id: String,
        event: PtyEvent,
        handled: std::sync::mpsc::SyncSender<()>,
    },
    OutputBatchTick {
        session_id: String,
        generation: u64,
    },
    OutputResyncTick {
        session_id: String,
        client_id: u64,
    },
    DurableOutputBatchTick {
        session_id: String,
        generation: u64,
    },
    CheckpointTick {
        session_id: String,
        generation: u64,
    },
    ShutdownTick {
        generation: u64,
    },
    RequestedShutdown,
    RequestedRestart,
    AgentHookEvent {
        event: AgentHookEvent,
    },
    SshBootstrapProgress {
        progress: SshTargetBootstrapProgress,
    },
    SshBootstrapFinished {
        target_id: String,
        job_id: String,
        status: SshBootstrapStatus,
    },
    /// A satellite pushed an event over its host link.
    HostLinkEvent {
        host_id: String,
        event: Value,
    },
    /// A satellite answered the hub's read of its agent presence list.
    RemoteAgentPresenceListed {
        host_id: String,
        result: HostResult<Value>,
    },
    /// The ssh pipe behind a host link ended.
    HostLinkClosed {
        host_id: String,
        error: String,
    },
    /// A link started connecting, attached, failed or was dropped.
    HostLinkStateChanged {
        host_id: String,
    },
    /// A forwarded request or a link operation finished off the actor.
    HostLinkRequestFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    ProjectCheckoutRegistered {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    ManagedWorkspaceCreated {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
        /// When set, this create was a hand off: chdir+notify sessions on the
        /// source workspace after the child exists.
        handoff_source_workspace_id: Option<String>,
    },
    WorkspaceStorageMeasured {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    WorkspaceSetupFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    AgentTitleReady {
        tab_id: String,
        id: String,
    },
    AgentTitleFinished {
        tab_id: String,
        id: String,
        result: HostResult<String>,
    },
    AiAssistFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    AiDictationFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    LinkedIssueRequestFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    /// A workspace's linked issue was stored or its cached metadata changed.
    LinkedIssuesChanged {
        workspace_id: String,
    },
    MobileWorkspaceFileFinished {
        client_id: u64,
        request_id: i64,
        request_type: String,
        result: HostResult<Value>,
    },
    MobilePromptFileFinished {
        client_id: u64,
        request_id: i64,
        request_type: String,
        upload_id: Option<String>,
        result: HostResult<Value>,
    },
    AgentQuotaFinished {
        client_id: u64,
        request_id: i64,
        environment_signature: u64,
        result: HostResult<Value>,
    },
    AgentQuotaClaudeTuiFinished {
        client_id: u64,
        request_id: i64,
        environment_signature: u64,
        result: HostResult<Value>,
    },
    AgentQuotaCodexResetFinished {
        client_id: u64,
        request_id: i64,
        environment_signature: u64,
        result: HostResult<Value>,
    },
    HostToolFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
        operation_id: Option<String>,
        skill: Option<String>,
    },
    RuntimeMutationFinished(runtime_mutations::RuntimeMutationFinished),
    WorkflowCatalogChanged {
        source: WorkflowRecipeSource,
        catalog_revision: i64,
    },
    WorkflowPlanChanged,
    WorkflowWorkspaceRecoveryFinished,
    WorkflowWorkspaceFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
        mutated: bool,
    },
    PrepareRuntimeMutation {
        request: runtime_mutations::RuntimeMutationRequest,
        completion: tokio::sync::oneshot::Sender<
            HostResult<crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown>,
        >,
    },
    /// A parked `check --wait`/`ask` request hit its server-side deadline.
    OrchestrationWaitTimeout {
        waiter_id: u64,
        effective_timeout_ms: u64,
    },
    OrchestrationStateWaitPoll(u64),
    /// Fires the deferred Enter after an injected orchestration banner.
    OrchestrationDeferredEnter {
        session_id: String,
        session_instance_id: u64,
        message_ids: Vec<String>,
        force_submit: bool,
    },
    TerminalStartupInput {
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    },
    TerminalStartupSubmit {
        session_id: String,
        session_instance_id: u64,
    },
    TerminalPulseFileChanged {
        workspace_id: String,
        watcher_generation: u64,
        event_sequence: u64,
    },
    TerminalPulseWatcherStarted {
        workspace_id: String,
        generation: u64,
        result: HostResult<super::terminal_pulse::WorkspacePulseWatcher>,
    },
    TerminalPulseWatcherFailed {
        workspace_id: String,
        watcher_generation: u64,
        error: String,
    },
    TerminalPulseDue {
        session_id: String,
        session_instance_id: u64,
        generation: u64,
    },
    ProjectCloneChanged {
        job_id: String,
    },
    ProjectCloneFinished {
        job_id: String,
    },
    /// One coordinator loop iteration, enqueued by the ticker task.
    CoordinatorTick {
        run_id: String,
    },
    /// One resource sampling iteration, enqueued by the ticker task.
    ResourceSampleTick,
    /// A finished sweep coming back from its blocking thread.
    ResourceSampleReady {
        snapshot: Value,
    },
    /// The hub finished reading a remote-only project's `alera.toml`.
    RemoteProjectConfigRead {
        project_id: String,
        result: HostResult<Value>,
    },
    /// A question forwarded to the hub went unanswered for too long.
    HubReverseRequestExpired {
        reverse_id: String,
    },
    /// A satellite answered the hub's resource poll.
    RemoteResourceSnapshot {
        host_id: String,
        result: HostResult<Value>,
    },
    /// Wakes the durable automation scheduler to evaluate due occurrences.
    PullRequestWatchTick,
    PullRequestWatchSnapshot {
        watch: Box<alera_core::runtime::PullRequestWatch>,
        generation: uuid::Uuid,
        result: HostResult<Value>,
    },
    PullRequestWatchMerged {
        watch: Box<alera_core::runtime::PullRequestWatch>,
        generation: uuid::Uuid,
        result: HostResult<String>,
    },
    AutomationTick,
    AutomationSharedCleanupFinished {
        attempt: Box<alera_core::runtime::AutomationCleanupAttempt>,
        result: Result<Value, String>,
    },
    /// A notification or server request emitted by the shared Codex process.
    CodexMessage {
        #[allow(dead_code)]
        message: Value,
    },
    CodexProcessExited {
        reason: String,
    },
    CodexMalformed {
        reason: String,
    },
    Account(account_requests::AccountCommand),
    Push(push_delivery::PushCommand),
    VoiceRealtime {
        generation: u64,
        event: super::voice_realtime::VoiceRealtimeEvent,
    },
    VoiceRealtimeReconnect {
        generation: u64,
    },
    VoiceGeminiTranscriptSettle {
        generation: u64,
        token: u64,
    },
    VoiceTurnFinished {
        client_id: u64,
        request_id: i64,
        job_id: u64,
        session_generation: u64,
        from_realtime: bool,
        cancel_home: Option<bool>,
        result: HostResult<String>,
    },
    VoiceSynthesizeFinished {
        client_id: u64,
        request_id: i64,
        job_id: u64,
        session_generation: u64,
        result: HostResult<Value>,
    },
}
