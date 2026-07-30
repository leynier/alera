use serde_json::Value;

use crate::agent_status::AgentHookEvent;
use crate::ssh_bootstrap::SshTargetBootstrapProgress;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::session::PtyEvent;
use alera_core::runtime::SshBootstrapStatus;

use super::{
    emulator_request_payloads, emulator_request_queue, runtime_mutations, ClientHandle, ClientKind,
};

/// Messages processed serially by the single server actor. Every state mutation
/// happens here, which keeps session/client transitions deterministic.
pub enum ServerCommand {
    ClientConnected {
        id: u64,
        handle: ClientHandle,
        kind: ClientKind,
    },
    ClientLine {
        id: u64,
        line: String,
    },
    ClientDisconnected {
        id: u64,
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
    WorkspaceSetupFinished {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    AiTextGenerationFinished {
        client_id: u64,
        request_id: i64,
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
    BrowserRequestTimeout {
        correlation_id: String,
    },
}
