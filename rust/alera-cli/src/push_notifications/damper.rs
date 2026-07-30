use std::collections::HashMap;

use chrono::{DateTime, Duration, Utc};

const PUSH_COOLDOWN: Duration = Duration::seconds(60);
const TERMINAL_EXIT_RETENTION: Duration = Duration::hours(1);

pub(crate) struct PushDamper {
    armed_at: DateTime<Utc>,
    last_delivered: HashMap<(String, String), DateTime<Utc>>,
}

impl Default for PushDamper {
    fn default() -> Self {
        Self {
            armed_at: Utc::now(),
            last_delivered: HashMap::new(),
        }
    }
}

impl PushDamper {
    pub(crate) fn should_deliver(
        &mut self,
        session_id: &str,
        state: &str,
        state_started_at: DateTime<Utc>,
        transitioned: bool,
        now: DateTime<Utc>,
    ) -> bool {
        if !transitioned || state_started_at < self.armed_at {
            return false;
        }
        let key = (session_id.to_string(), state.to_string());
        if self
            .last_delivered
            .get(&key)
            .is_some_and(|previous| now.signed_duration_since(*previous) < PUSH_COOLDOWN)
        {
            return false;
        }
        self.last_delivered.insert(key, now);
        true
    }

    pub(crate) fn forget_session(&mut self, session_id: &str) {
        self.last_delivered
            .retain(|(candidate, state), _| candidate != session_id || state == "terminalExit");
    }

    /// A PTY exit and a later lifecycle cleanup can observe the same stopped
    /// session. Keep this marker until a new session with the handle starts.
    pub(crate) fn should_deliver_terminal_exit(
        &mut self,
        session_id: &str,
        now: DateTime<Utc>,
    ) -> bool {
        self.last_delivered.retain(|(_, state), delivered_at| {
            state != "terminalExit"
                || now.signed_duration_since(*delivered_at) < TERMINAL_EXIT_RETENTION
        });
        let key = (session_id.to_string(), "terminalExit".to_string());
        if self.last_delivered.contains_key(&key) {
            return false;
        }
        self.last_delivered.insert(key, now);
        true
    }

    pub(crate) fn reset_session(&mut self, session_id: &str) {
        self.last_delivered
            .retain(|(candidate, _), _| candidate != session_id);
    }
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, Utc};

    use super::PushDamper;

    #[test]
    fn rejects_replayed_and_repeated_agent_states() {
        let now = Utc::now();
        let mut damper = PushDamper::default();
        assert!(!damper.should_deliver(
            "session",
            "waiting",
            now - Duration::minutes(1),
            true,
            now
        ));
        assert!(damper.should_deliver(
            "session",
            "waiting",
            now + Duration::seconds(1),
            true,
            now + Duration::seconds(1)
        ));
        assert!(!damper.should_deliver(
            "session",
            "waiting",
            now + Duration::seconds(2),
            true,
            now + Duration::seconds(2)
        ));
        assert!(!damper.should_deliver(
            "session",
            "blocked",
            now + Duration::seconds(3),
            false,
            now + Duration::seconds(3)
        ));
    }

    #[test]
    fn terminal_exit_is_delivered_once_until_the_handle_restarts() {
        let now = Utc::now();
        let mut damper = PushDamper::default();

        assert!(damper.should_deliver_terminal_exit("session", now));
        assert!(!damper.should_deliver_terminal_exit("session", now + Duration::seconds(1)));

        // Agent cleanup must not reopen the duplicate window for a stopped PTY.
        damper.forget_session("session");
        assert!(!damper.should_deliver_terminal_exit("session", now + Duration::seconds(2)));

        damper.reset_session("session");
        assert!(damper.should_deliver_terminal_exit("session", now + Duration::seconds(3)));
    }
}
