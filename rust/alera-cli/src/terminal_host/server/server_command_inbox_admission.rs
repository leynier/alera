use std::collections::HashSet;
#[cfg(test)]
use std::sync::Arc;
use std::sync::{Condvar, Mutex, MutexGuard};

use tokio::sync::Notify;

use super::{
    SERVER_COMMAND_CONTROL_BYTES, SERVER_COMMAND_CONTROL_CAPACITY, SERVER_COMMAND_WORK_BYTES,
    SERVER_COMMAND_WORK_CAPACITY,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum AdmissionClass {
    Work { bytes: usize },
    Control { bytes: usize },
}

#[derive(Debug, Default)]
pub(super) struct AdmissionState {
    work_commands: usize,
    work_bytes: usize,
    control_commands: usize,
    control_bytes: usize,
    closed: bool,
    paused_pty_sessions: HashSet<String>,
}

#[derive(Debug)]
pub(super) struct Admission {
    state: Mutex<AdmissionState>,
    changed: Condvar,
    async_changed: Notify,
    #[cfg(test)]
    blocking_wait_hook: Mutex<Option<Arc<std::sync::Barrier>>>,
    #[cfg(test)]
    async_wait_hook: Notify,
}

impl Admission {
    pub(super) fn new() -> Self {
        Self {
            state: Mutex::default(),
            changed: Condvar::new(),
            async_changed: Notify::new(),
            #[cfg(test)]
            blocking_wait_hook: Mutex::new(None),
            #[cfg(test)]
            async_wait_hook: Notify::new(),
        }
    }

    pub(super) fn try_acquire(
        &self,
        class: AdmissionClass,
        pty_session_id: Option<&str>,
    ) -> Option<MutexGuard<'_, AdmissionState>> {
        let mut state = self.state.lock().expect("server inbox admission lock");
        if state.closed || !Self::can_acquire(&state, class, pty_session_id) {
            return None;
        }
        Self::acquire(&mut state, class);
        Some(state)
    }

    pub(super) fn acquire_blocking(
        &self,
        class: AdmissionClass,
        pty_session_id: Option<&str>,
    ) -> Option<MutexGuard<'_, AdmissionState>> {
        let mut state = self.state.lock().expect("server inbox admission lock");
        while !state.closed && !Self::can_acquire(&state, class, pty_session_id) {
            #[cfg(test)]
            if let Some(hook) = self
                .blocking_wait_hook
                .lock()
                .expect("server inbox blocking wait hook")
                .take()
            {
                hook.wait();
            }
            state = self
                .changed
                .wait(state)
                .expect("server inbox admission lock");
        }
        if state.closed {
            return None;
        }
        Self::acquire(&mut state, class);
        Some(state)
    }

    pub(super) fn close(&self) {
        let mut state = self.state.lock().expect("server inbox admission lock");
        state.closed = true;
        drop(state);
        self.notify_waiters();
    }

    pub(super) fn pause_pty_session(&self, session_id: &str) {
        let mut state = self.state.lock().expect("server inbox admission lock");
        if !state.closed {
            state.paused_pty_sessions.insert(session_id.to_string());
        }
        drop(state);
        self.notify_waiters();
    }

    pub(super) fn resume_pty_session(&self, session_id: &str) {
        let mut state = self.state.lock().expect("server inbox admission lock");
        state.paused_pty_sessions.remove(session_id);
        drop(state);
        self.notify_waiters();
    }

    pub(super) fn is_closed(&self) -> bool {
        self.state
            .lock()
            .expect("server inbox admission lock")
            .closed
    }

    pub(super) fn capacity_notified(&self) -> tokio::sync::futures::Notified<'_> {
        self.async_changed.notified()
    }

    pub(super) fn release(&self, class: AdmissionClass) {
        let mut state = self.state.lock().expect("server inbox admission lock");
        match class {
            AdmissionClass::Work { bytes } => {
                state.work_commands = state.work_commands.saturating_sub(1);
                state.work_bytes = state.work_bytes.saturating_sub(bytes);
            }
            AdmissionClass::Control { bytes } => {
                state.control_commands = state.control_commands.saturating_sub(1);
                state.control_bytes = state.control_bytes.saturating_sub(bytes);
            }
        }
        drop(state);
        self.changed.notify_one();
        self.async_changed.notify_one();
    }

    fn notify_waiters(&self) {
        self.changed.notify_all();
        self.async_changed.notify_waiters();
    }

    #[cfg(test)]
    pub(super) fn set_blocking_wait_hook(&self, hook: Arc<std::sync::Barrier>) {
        *self
            .blocking_wait_hook
            .lock()
            .expect("server inbox blocking wait hook") = Some(hook);
    }

    #[cfg(test)]
    pub(super) fn async_waiter(&self) -> &Notify {
        &self.async_wait_hook
    }

    #[cfg(test)]
    pub(super) fn queued_counts(&self) -> (usize, usize, usize) {
        let state = self.state.lock().expect("server inbox admission lock");
        (
            state.work_commands,
            state.work_bytes,
            state.control_commands,
        )
    }

    fn can_acquire(
        state: &AdmissionState,
        class: AdmissionClass,
        pty_session_id: Option<&str>,
    ) -> bool {
        if pty_session_id.is_some_and(|id| state.paused_pty_sessions.contains(id)) {
            return false;
        }
        match class {
            AdmissionClass::Work { bytes } => {
                state.work_commands < SERVER_COMMAND_WORK_CAPACITY
                    && bytes <= SERVER_COMMAND_WORK_BYTES.saturating_sub(state.work_bytes)
            }
            AdmissionClass::Control { bytes } => {
                state.control_commands < SERVER_COMMAND_CONTROL_CAPACITY
                    && bytes <= SERVER_COMMAND_CONTROL_BYTES.saturating_sub(state.control_bytes)
            }
        }
    }

    fn acquire(state: &mut AdmissionState, class: AdmissionClass) {
        match class {
            AdmissionClass::Work { bytes } => {
                state.work_commands += 1;
                state.work_bytes += bytes;
            }
            AdmissionClass::Control { bytes } => {
                state.control_commands += 1;
                state.control_bytes += bytes;
            }
        }
    }
}
