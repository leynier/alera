use serde_json::Value;

use crate::agent_status::AgentHookEvent;
use crate::ssh_bootstrap::SshTargetBootstrapProgress;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::session::PtyEvent;
use alera_core::runtime::{SshBootstrapStatus, WorkflowRecipeSource};

use super::{
    account_requests, emulator_request_payloads, emulator_request_queue, push_delivery,
    runtime_mutations, ClientKind,
};

/// Messages processed serially by the single server actor. Every state mutation
/// happens here, which keeps session/client transitions deterministic.
pub enum ServerCommand {
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
    ManagedWorkspaceCreated {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
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
    EmulatorRequestFinished {
        client_id: u64,
        request_id: i64,
        completion: emulator_request_payloads::EmulatorRequestCompletion,
    },
    EmulatorMaintenanceFinished(emulator_request_queue::EmulatorMaintenanceCompletion),
    RuntimeMutationFinished(runtime_mutations::RuntimeMutationFinished),
    WorkflowCatalogChanged {
        source: WorkflowRecipeSource,
        catalog_revision: i64,
    },
    WorkflowPlanChanged,
    PrepareRuntimeMutation {
        request: runtime_mutations::RuntimeMutationRequest,
        completion: tokio::sync::oneshot::Sender<
            HostResult<crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown>,
        >,
    },
    EmulatorPointerTimeout {
        tab_id: String,
        client_id: u64,
        generation: u64,
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
    /// Wakes the durable automation scheduler to evaluate due occurrences.
    AutomationTick,
    BrowserRequestTimeout {
        correlation_id: String,
    },
    /// A notification or server request emitted by the shared Codex process.
    CodexMessage {
        message: Value,
    },
    CodexProcessExited {
        reason: String,
    },
    CodexMalformed {
        reason: String,
    },
    CodexPresenceTick,
    CodexFlush {
        tab_id: String,
    },
    CodexAutoResolve {
        tab_id: String,
        thread_id: String,
        request_id: Value,
        server_instance: std::sync::Arc<()>,
    },
    Account(account_requests::AccountCommand),
    Push(push_delivery::PushCommand),
}
