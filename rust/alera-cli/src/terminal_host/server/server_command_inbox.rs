use super::server_command::ServerCommand;
use std::fmt;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::Arc;
use tokio::sync::mpsc::error::TryRecvError;
use tokio::sync::mpsc::{self, UnboundedReceiver, UnboundedSender};
use tokio::sync::Notify;

#[path = "server_command_inbox_admission.rs"]
mod admission;
use admission::{Admission, AdmissionClass};
#[path = "server_command_inbox_budget.rs"]
mod budget;
use budget::{bound_completion_result, command_admission_class};
#[path = "server_client_disconnect.rs"]
mod client_disconnect;
pub(crate) use client_disconnect::ServerClientDisconnect;

pub(crate) const SERVER_COMMAND_WORK_CAPACITY: usize = 256;
pub(crate) const SERVER_COMMAND_WORK_BYTES: usize = 64 * 1024 * 1024;
pub(crate) const SERVER_COMMAND_CONTROL_CAPACITY: usize = 128;
pub(crate) const SERVER_COMMAND_CONTROL_BYTES: usize = 16 * 1024 * 1024;
/// Deferred results get their own bounded lane so normal control pressure
/// cannot discard a response after the corresponding job was admitted.
pub(crate) const SERVER_COMMAND_COMPLETION_CAPACITY: usize = 128;
pub(crate) const SERVER_COMMAND_COMPLETION_BYTES: usize = 16 * 1024 * 1024;
// Base64 dictation carries up to 25 MiB of audio; large requests use work capacity.
pub(crate) const SERVER_COMMAND_MAX_LINE_BYTES: usize = SERVER_COMMAND_WORK_BYTES;
pub(crate) const SERVER_COMMAND_SMALL_LINE_BYTES: usize = 1024 * 1024;

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
        self.inbox.admission.receiver_closed();
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
        let is_completion = matches!(class, AdmissionClass::Completion { .. });
        let reservation = if is_completion {
            self.admission.try_acquire_completion(class)
        } else {
            self.admission.try_acquire(class, pty_session_id)
        };
        let Some(reservation) = reservation else {
            return Err(
                if self.tx.is_closed() || (!is_completion && self.admission.is_closed()) {
                    ServerInboxSendError::Closed
                } else {
                    ServerInboxSendError::Full
                },
            );
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
        let is_completion = matches!(class, AdmissionClass::Completion { .. });
        let reservation = if is_completion {
            self.admission.acquire_completion_blocking(class)
        } else {
            self.admission.acquire_blocking(class, pty_session_id)
        };
        let Some(reservation) = reservation else {
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
        let is_completion = matches!(class, AdmissionClass::Completion { .. });
        let pty_session_id = pty_session(&command).map(str::to_owned);
        let mut command = Some(command);
        loop {
            let notified = self.admission.capacity_notified();
            let mut notified = std::pin::pin!(notified);
            // Enable before predicates so a release or close cannot be missed.
            notified.as_mut().enable();
            let reservation = if is_completion {
                self.admission.try_acquire_completion(class)
            } else {
                self.admission.try_acquire(class, pty_session_id.as_deref())
            };
            if let Some(reservation) = reservation {
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
            drop(reservation);
            if self.tx.is_closed() || (!is_completion && self.admission.is_closed()) {
                return Err(ServerInboxSendError::Closed);
            }
            #[cfg(test)]
            self.admission.async_waiter().notify_waiters();
            tokio::select! {
                _ = notified.as_mut() => {}
                _ = self.tx.closed() => return Err(ServerInboxSendError::Closed),
            }
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

    #[cfg(test)]
    pub(crate) fn completion_counts(&self) -> (usize, usize) {
        self.admission.completion_counts()
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

#[cfg(test)]
#[path = "server_command_inbox_completion_tests.rs"]
mod completion_tests;
#[cfg(test)]
#[path = "server_command_inbox_deferred_additional_tests.rs"]
mod deferred_additional_tests;
#[cfg(test)]
#[path = "server_command_inbox_deferred_tests.rs"]
mod deferred_tests;
#[cfg(test)]
#[path = "server_command_inbox_managed_completion_tests.rs"]
mod managed_completion_tests;
#[cfg(test)]
#[path = "server_command_inbox_tests.rs"]
mod tests;
