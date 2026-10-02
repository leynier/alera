use super::server_command::ServerCommand;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::session::PtyEvent;
use std::fmt;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::Arc;
use tokio::sync::mpsc::error::TryRecvError;
use tokio::sync::mpsc::{self, UnboundedReceiver, UnboundedSender};
use tokio::sync::Notify;
#[path = "server_command_inbox_admission.rs"]
mod admission;
use admission::{Admission, AdmissionClass};
pub(crate) const SERVER_COMMAND_WORK_CAPACITY: usize = 256;
pub(crate) const SERVER_COMMAND_WORK_BYTES: usize = 64 * 1024 * 1024;
pub(crate) const SERVER_COMMAND_CONTROL_CAPACITY: usize = 128;
pub(crate) const SERVER_COMMAND_CONTROL_BYTES: usize = 16 * 1024 * 1024;
pub(crate) const SERVER_COMMAND_MAX_LINE_BYTES: usize = 1024 * 1024;
const REQUESTED_SHUTDOWN: u8 = 1;
const REQUESTED_RESTART: u8 = 2;
#[derive(Debug)]
struct ControlWake {
    pending: AtomicU8,
    notify: Notify,
}
impl ControlWake {
    fn request(&self, flag: u8) {
        if self
            .pending
            .compare_exchange(0, flag, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            self.notify.notify_one();
        }
    }
    fn take(&self) -> Option<ServerCommand> {
        let pending = self.pending.swap(0, Ordering::AcqRel);
        match pending {
            REQUESTED_SHUTDOWN => Some(ServerCommand::RequestedShutdown),
            REQUESTED_RESTART => Some(ServerCommand::RequestedRestart),
            _ => None,
        }
    }
}
#[derive(Clone, Debug)]
pub(crate) struct ServerInbox {
    tx: UnboundedSender<ServerCommand>,
    admission: Arc<Admission>,
    control_wake: Arc<ControlWake>,
}
#[derive(Debug)]
pub(crate) struct ServerInboxReceiver {
    receiver: UnboundedReceiver<ServerCommand>,
    inbox: ServerInbox,
}
impl Drop for ServerInboxReceiver {
    fn drop(&mut self) {
        self.inbox.close();
    }
}
impl ServerInboxReceiver {
    #[cfg(test)]
    pub(crate) async fn recv(&mut self) -> Option<ServerCommand> {
        self.inbox.clone().recv(self).await
    }
    #[cfg(test)]
    pub(crate) fn try_recv(&mut self) -> Result<ServerCommand, TryRecvError> {
        let command = self.receiver.try_recv()?;
        if let Ok(class) = command_admission_class(&command) {
            self.inbox.admission.release(class);
        }
        Ok(command)
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ServerInboxSendError {
    Full,
    Oversized,
    Closed,
}
impl fmt::Display for ServerInboxSendError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Full => formatter.write_str("server command inbox is full"),
            Self::Oversized => formatter.write_str("server command payload is too large"),
            Self::Closed => formatter.write_str("server command inbox is closed"),
        }
    }
}
impl std::error::Error for ServerInboxSendError {}
impl ServerInbox {
    pub(crate) fn channel() -> (Self, ServerInboxReceiver) {
        let (tx, rx) = mpsc::unbounded_channel();
        let inbox = Self {
            tx,
            admission: Arc::new(Admission::new()),
            control_wake: Arc::new(ControlWake {
                pending: AtomicU8::new(0),
                notify: Notify::new(),
            }),
        };
        (
            inbox.clone(),
            ServerInboxReceiver {
                receiver: rx,
                inbox,
            },
        )
    }
    pub(crate) fn close(&self) {
        self.admission.close();
    }
    pub(crate) fn send(&self, mut command: ServerCommand) -> Result<(), ServerInboxSendError> {
        bound_completion_result(&mut command);
        if let Some(flag) = control_signal(&command) {
            self.request_control(flag);
            return Ok(());
        }
        let class = command_admission_class(&command)?;
        let pty_session_id = pty_session(&command);
        let Some(reservation) = self.admission.try_acquire(class, pty_session_id) else {
            return Err(if self.admission.is_closed() {
                ServerInboxSendError::Closed
            } else {
                ServerInboxSendError::Full
            });
        };
        if self.tx.send(command).is_err() {
            drop(reservation);
            self.admission.release(class);
            return Err(ServerInboxSendError::Closed);
        }
        Ok(())
    }
    pub(crate) fn send_blocking(
        &self,
        mut command: ServerCommand,
    ) -> Result<(), ServerInboxSendError> {
        bound_completion_result(&mut command);
        if let Some(flag) = control_signal(&command) {
            self.request_control(flag);
            return Ok(());
        }
        let class = command_admission_class(&command)?;
        let pty_session_id = pty_session(&command);
        let Some(reservation) = self.admission.acquire_blocking(class, pty_session_id) else {
            return Err(ServerInboxSendError::Closed);
        };
        if self.tx.send(command).is_err() {
            drop(reservation);
            self.admission.release(class);
            return Err(ServerInboxSendError::Closed);
        }
        Ok(())
    }
    pub(crate) async fn send_wait(
        &self,
        mut command: ServerCommand,
    ) -> Result<(), ServerInboxSendError> {
        bound_completion_result(&mut command);
        if let Some(flag) = control_signal(&command) {
            self.request_control(flag);
            return Ok(());
        }
        let class = command_admission_class(&command)?;
        let pty_session_id = pty_session(&command).map(str::to_owned);
        let mut command = Some(command);
        loop {
            let notified = self.admission.capacity_notified();
            let mut notified = std::pin::pin!(notified);
            // Enable before predicates so a release or close cannot be missed.
            notified.as_mut().enable();
            if let Some(reservation) = self.admission.try_acquire(class, pty_session_id.as_deref())
            {
                if self
                    .tx
                    .send(command.take().expect("command is retained"))
                    .is_err()
                {
                    drop(reservation);
                    self.admission.release(class);
                    return Err(ServerInboxSendError::Closed);
                }
                return Ok(());
            }
            if self.admission.is_closed() {
                return Err(ServerInboxSendError::Closed);
            }
            #[cfg(test)]
            self.admission.async_waiter().notify_waiters();
            notified.await;
        }
    }
    fn request_control(&self, flag: u8) {
        self.admission.close();
        self.control_wake.request(flag);
    }
    pub(crate) fn pause_pty_session(&self, session_id: &str) {
        self.admission.pause_pty_session(session_id);
    }
    pub(crate) fn resume_pty_session(&self, session_id: &str) {
        self.admission.resume_pty_session(session_id);
    }
    pub(crate) async fn recv(&self, receiver: &mut ServerInboxReceiver) -> Option<ServerCommand> {
        loop {
            match receiver.receiver.try_recv() {
                Ok(command) => {
                    self.release_command(&command);
                    return Some(command);
                }
                Err(TryRecvError::Disconnected) => {
                    self.close();
                    return None;
                }
                Err(TryRecvError::Empty) => {}
            }
            if let Some(command) = self.control_wake.take() {
                return Some(command);
            }
            tokio::select! {
                biased;
                command = receiver.receiver.recv() => {
                    let Some(command) = command else {
                        self.close();
                        return None;
                    };
                    self.release_command(&command);
                    return Some(command);
                }
                _ = self.control_wake.notify.notified() => {}
            }
        }
    }
    fn release_command(&self, command: &ServerCommand) {
        if let Ok(class) = command_admission_class(command) {
            self.admission.release(class);
        }
    }
    #[cfg(test)]
    pub(crate) fn queued_counts(&self) -> (usize, usize, usize) {
        self.admission.queued_counts()
    }
}
fn control_signal(command: &ServerCommand) -> Option<u8> {
    match command {
        ServerCommand::RequestedShutdown => Some(REQUESTED_SHUTDOWN),
        ServerCommand::RequestedRestart => Some(REQUESTED_RESTART),
        _ => None,
    }
}
fn pty_session(command: &ServerCommand) -> Option<&str> {
    match command {
        ServerCommand::Pty { session_id, .. } => Some(session_id),
        _ => None,
    }
}
fn command_admission_class(
    command: &ServerCommand,
) -> Result<AdmissionClass, ServerInboxSendError> {
    match command {
        ServerCommand::ClientLine { line, .. }
        | ServerCommand::RelayClientLine { line, .. }
        | ServerCommand::HistoryRequestRetry { line, .. } => {
            if line.len() > SERVER_COMMAND_MAX_LINE_BYTES {
                return Err(ServerInboxSendError::Oversized);
            }
            Ok(AdmissionClass::Control {
                bytes: line.len().max(1),
            })
        }
        ServerCommand::Pty { event, .. } => match event {
            PtyEvent::Output(data) => {
                let bytes = data.len().max(1);
                if bytes > SERVER_COMMAND_WORK_BYTES {
                    return Err(ServerInboxSendError::Oversized);
                }
                Ok(AdmissionClass::Work { bytes })
            }
            _ => Ok(AdmissionClass::Work { bytes: 1 }),
        },
        _ => {
            let bytes = command_control_bytes(command);
            if bytes > SERVER_COMMAND_CONTROL_BYTES {
                return Err(ServerInboxSendError::Oversized);
            }
            Ok(AdmissionClass::Control { bytes })
        }
    }
}
fn command_control_bytes(command: &ServerCommand) -> usize {
    let bytes = match command {
        ServerCommand::RemoteTerminalLifecycleFinished {
            verb,
            payload,
            result,
            ..
        } => string_bytes(verb) + value_bytes(payload) + host_result_error_bytes(result),
        ServerCommand::OwnerTerminalLifecycleFinished {
            operation_id,
            result,
            ..
        } => string_bytes(operation_id) + host_result_value_bytes(result),
        ServerCommand::RemoteSetupFinished { result, .. }
        | ServerCommand::RemoteRecoveryFinished { result, .. }
        | ServerCommand::HostLinkRequestFinished { result, .. }
        | ServerCommand::ProjectCheckoutRegistered { result, .. }
        | ServerCommand::ManagedWorkspaceCreated { result, .. }
        | ServerCommand::WorkspaceStorageMeasured { result, .. }
        | ServerCommand::WorkspaceSetupFinished { result, .. }
        | ServerCommand::AiAssistFinished { result, .. }
        | ServerCommand::AiDictationFinished { result, .. }
        | ServerCommand::LinkedIssueRequestFinished { result, .. }
        | ServerCommand::MobileWorkspaceFileFinished { result, .. }
        | ServerCommand::MobilePromptFileFinished { result, .. }
        | ServerCommand::AgentQuotaFinished { result, .. }
        | ServerCommand::AgentQuotaClaudeTuiFinished { result, .. }
        | ServerCommand::AgentQuotaCodexResetFinished { result, .. }
        | ServerCommand::HostToolFinished { result, .. }
        | ServerCommand::WorkflowWorkspaceFinished { result, .. }
        | ServerCommand::RemoteProjectConfigRead { result, .. }
        | ServerCommand::RemoteResourceSnapshot { result, .. }
        | ServerCommand::RemoteAgentPresenceListed { result, .. } => {
            host_result_value_bytes(result)
        }
        ServerCommand::RelayStatus { payload, .. }
        | ServerCommand::HostLinkEvent { event: payload, .. }
        | ServerCommand::MobileStatusFinished { payload, .. }
        | ServerCommand::ResourceSampleReady { snapshot: payload }
        | ServerCommand::CodexMessage { message: payload } => value_bytes(payload),
        ServerCommand::AgentHookEvent { event, .. } => {
            string_bytes(&event.terminal_session_id)
                + string_bytes(&event.workspace_id)
                + string_bytes(&event.tab_id)
                + string_bytes(&event.agent_type)
                + event
                    .event_name
                    .as_deref()
                    .map(string_bytes)
                    .unwrap_or_default()
                + value_bytes(&event.payload)
        }
        ServerCommand::BufferGuardExpired { id }
        | ServerCommand::OwnerAutomationPrecheckFinished { operation_id: id }
        | ServerCommand::LinkedIssuesChanged { workspace_id: id }
        | ServerCommand::ProjectCloneChanged { job_id: id }
        | ServerCommand::ProjectCloneFinished { job_id: id }
        | ServerCommand::HubReverseRequestExpired { reverse_id: id }
        | ServerCommand::HostLinkStateChanged { host_id: id }
        | ServerCommand::HostLinkClosed { host_id: id, .. }
        | ServerCommand::CodexProcessExited { reason: id }
        | ServerCommand::CodexMalformed { reason: id } => string_bytes(id),
        ServerCommand::AgentTitleReady { tab_id, id }
        | ServerCommand::AgentTitleFinished { tab_id, id, .. } => {
            string_bytes(tab_id) + string_bytes(id)
        }
        ServerCommand::SshBootstrapFinished {
            target_id, job_id, ..
        } => string_bytes(target_id) + string_bytes(job_id),
        ServerCommand::ClientLine { line, .. }
        | ServerCommand::RelayClientLine { line, .. }
        | ServerCommand::HistoryRequestRetry { line, .. } => string_bytes(line),
        _ => 1,
    };
    bytes.max(1)
}
fn bound_completion_result(command: &mut ServerCommand) {
    let result = match command {
        ServerCommand::OwnerTerminalLifecycleFinished { result, .. }
        | ServerCommand::RemoteSetupFinished { result, .. }
        | ServerCommand::RemoteRecoveryFinished { result, .. }
        | ServerCommand::HostLinkRequestFinished { result, .. }
        | ServerCommand::ProjectCheckoutRegistered { result, .. }
        | ServerCommand::ManagedWorkspaceCreated { result, .. }
        | ServerCommand::WorkspaceStorageMeasured { result, .. }
        | ServerCommand::WorkspaceSetupFinished { result, .. }
        | ServerCommand::AiAssistFinished { result, .. }
        | ServerCommand::AiDictationFinished { result, .. }
        | ServerCommand::LinkedIssueRequestFinished { result, .. }
        | ServerCommand::MobileWorkspaceFileFinished { result, .. }
        | ServerCommand::MobilePromptFileFinished { result, .. }
        | ServerCommand::AgentQuotaFinished { result, .. }
        | ServerCommand::AgentQuotaClaudeTuiFinished { result, .. }
        | ServerCommand::AgentQuotaCodexResetFinished { result, .. }
        | ServerCommand::HostToolFinished { result, .. }
        | ServerCommand::WorkflowWorkspaceFinished { result, .. }
        | ServerCommand::RemoteProjectConfigRead { result, .. }
        | ServerCommand::RemoteResourceSnapshot { result, .. }
        | ServerCommand::RemoteAgentPresenceListed { result, .. } => result,
        _ => return,
    };
    if host_result_value_bytes(result) > SERVER_COMMAND_CONTROL_BYTES {
        // JSON escaping can expand a captured process output beyond its byte
        // budget. Preserve the request's completion with an explicit error.
        *result = Err(HostError::state(
            "Runtime response exceeds the 16 MiB command inbox budget".to_string(),
        ));
    }
}
fn string_bytes(value: &str) -> usize {
    value.len().saturating_add(1)
}
fn value_bytes(value: &serde_json::Value) -> usize {
    serde_json::to_vec(value)
        .map(|encoded| encoded.len().saturating_add(1))
        .unwrap_or(SERVER_COMMAND_CONTROL_BYTES.saturating_add(1))
}
fn host_result_value_bytes(result: &HostResult<serde_json::Value>) -> usize {
    match result {
        Ok(value) => value_bytes(value),
        Err(error) => host_error_bytes(error),
    }
}
fn host_result_error_bytes<T>(result: &HostResult<T>) -> usize {
    match result {
        Ok(_) => 1,
        Err(error) => host_error_bytes(error),
    }
}
fn host_error_bytes(error: &HostError) -> usize {
    match error {
        HostError::State(message) | HostError::Format(message) => string_bytes(message),
        HostError::Conflict {
            code,
            message,
            details,
        } => string_bytes(code) + string_bytes(message) + value_bytes(details),
    }
}
#[cfg(test)]
#[path = "server_command_inbox_tests.rs"]
mod tests;
