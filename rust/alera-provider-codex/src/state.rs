use crate::provider::CodexProvider;
use alera_provider_protocol::{EventKind, ProviderEvent, SessionStatus};

impl<T> CodexProvider<T> {
    pub(crate) fn app_thread_id(&self, native_thread_id: Option<&str>) -> String {
        if let Some(native_thread_id) = native_thread_id {
            if let Some(session) = &self.session {
                if session.native_thread_id == native_thread_id {
                    return session.thread_id.clone();
                }
                // Every registered descendant belongs to this session.
                if self.native_child_parents.contains_key(native_thread_id) {
                    return session.thread_id.clone();
                }
            }
            if let Some(thread_id) = &self.pending_thread_id {
                return thread_id.clone();
            }
            return native_thread_id.to_owned();
        }
        self.session
            .as_ref()
            .map(|session| session.thread_id.clone())
            .or_else(|| self.pending_thread_id.clone())
            .unwrap_or_else(|| self.config.instance_id.clone())
    }

    pub(crate) fn apply_notification_state(&mut self, method: &str, turn_id: Option<&str>) {
        if matches!(method, "turn/completed" | "turn/aborted") {
            self.pending_requests.clear();
            self.terminal_event_pending = true;
        }
        let Some(session) = self.session.as_mut() else {
            return;
        };
        match method {
            "thread/started" => session.status = SessionStatus::Ready,
            "turn/started" => {
                session.status = SessionStatus::Running;
                session.active_turn_id = turn_id.map(ToOwned::to_owned);
            }
            "turn/completed" | "turn/aborted" => {
                session.status = SessionStatus::Ready;
                session.active_turn_id = None;
            }
            _ => {}
        }
    }

    pub(crate) fn mark_waiting(&mut self) {
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Waiting;
        }
    }

    pub(crate) fn mark_event_consumed(&mut self, event: &ProviderEvent) {
        if matches!(
            &event.kind,
            EventKind::TurnCompleted | EventKind::TurnAborted
        ) {
            self.terminal_event_pending = false;
        }
    }
}
