use std::time::Duration;

use serde_json::Value;

use crate::terminal_host::protocol::error_response;
use crate::terminal_host::protocol::event;
use crate::terminal_host::session::{PtyWriteCompletion, Session};

use super::{terminal_pulse_state, ServerActor, ServerCommand, TerminalPulseConfiguration};
use crate::terminal_host::server::TERMINAL_INPUT_BACKPRESSURE_CODE;

const RETRY_DELAY: Duration = Duration::from_millis(50);

impl ServerActor {
    pub(in crate::terminal_host::server) fn handle_terminal_pulse_file_changed(
        &mut self,
        workspace_id: &str,
        watcher_generation: u64,
        event_sequence: u64,
    ) {
        if !self
            .terminal_pulses
            .accepts_watcher_command(workspace_id, watcher_generation)
        {
            return;
        }
        for schedule in self.terminal_pulses.schedule(workspace_id, event_sequence) {
            let inbox = self.inbox.clone();
            tokio::spawn(async move {
                tokio::time::sleep(schedule.delay).await;
                let _ = inbox.send(ServerCommand::TerminalPulseDue {
                    session_id: schedule.session_id,
                    session_instance_id: schedule.session_instance_id,
                    generation: schedule.generation,
                });
            });
        }
    }

    pub(in crate::terminal_host::server) fn handle_terminal_pulse_watcher_failed(
        &mut self,
        workspace_id: &str,
        watcher_generation: u64,
        error: &str,
    ) {
        if !self
            .terminal_pulses
            .accepts_watcher_command(workspace_id, watcher_generation)
        {
            if let Some(pending) = self
                .terminal_pulses
                .fail_watcher_start(workspace_id, watcher_generation)
            {
                let failure = crate::terminal_host::host_error::HostError::state(format!(
                    "Terminal Pulse watcher could not start: {error}"
                ));
                for configuration in pending {
                    self.client_write(
                        configuration.client_id,
                        error_response(configuration.request_id, &failure),
                    );
                }
            }
            return;
        }
        let message = format!("Terminal Pulse watcher stopped: {error}");
        for change in self.terminal_pulses.fail_workspace(workspace_id) {
            self.broadcast_terminal_pulse_changed(
                &change.session_id,
                &change.configuration,
                false,
                Some(&message),
            );
        }
    }

    pub(in crate::terminal_host::server) fn disarm_terminal_pulse(&mut self, session_id: &str) {
        self.cancel_pending_terminal_pulse_configuration(session_id);
        if let Some(configuration) = self.terminal_pulses.disarm(session_id) {
            self.broadcast_terminal_pulse_changed(session_id, &configuration, false, None);
        }
    }

    pub(in crate::terminal_host::server) fn handle_terminal_pulse_due(
        &mut self,
        session_id: String,
        session_instance_id: u64,
        generation: u64,
    ) {
        let Some(write) =
            self.terminal_pulses
                .due_write(&session_id, session_instance_id, generation)
        else {
            return;
        };
        let current = self.sessions.get(&session_id).map(Session::instance_id);
        if current != Some(session_instance_id) {
            self.disarm_terminal_pulse(&session_id);
            return;
        }
        let completion = PtyWriteCompletion::TerminalPulse {
            session_instance_id,
            active: write.active,
        };
        if let Some(session) = self.sessions.get_mut(&session_id) {
            match session.queue_write(completion, &write.bytes) {
                Ok(()) => {
                    self.terminal_pulses
                        .complete_due(&session_id, session_instance_id, generation)
                }
                Err(error)
                    if error
                        .wire_message()
                        .starts_with(TERMINAL_INPUT_BACKPRESSURE_CODE) =>
                {
                    if let Some(generation) =
                        self.terminal_pulses
                            .retry_due(&session_id, session_instance_id, generation)
                    {
                        let inbox = self.inbox.clone();
                        tokio::spawn(async move {
                            tokio::time::sleep(RETRY_DELAY).await;
                            let _ = inbox.send(ServerCommand::TerminalPulseDue {
                                session_id,
                                session_instance_id,
                                generation,
                            });
                        });
                    }
                }
                Err(error) => {
                    self.terminal_pulses
                        .complete_due(&session_id, session_instance_id, generation);
                    self.broadcast_terminal_error(&session_id, error.wire_message());
                }
            }
        }
    }

    pub(super) fn broadcast_terminal_pulse_changed(
        &self,
        session_id: &str,
        configuration: &TerminalPulseConfiguration,
        armed: bool,
        error: Option<&str>,
    ) {
        let mut payload = terminal_pulse_state(configuration.clone(), armed);
        payload["sessionId"] = Value::String(session_id.to_string());
        if let Some(error) = error {
            payload["error"] = Value::String(error.to_string());
        }
        self.broadcast_authenticated_local(event("terminalPulseChanged", payload));
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;
    use crate::terminal_host::client::ClientHandle;
    use crate::terminal_host::server::actor_test_harness::{
        local_client, mobile_client, test_actor,
    };

    #[tokio::test]
    async fn pulse_state_with_terminal_input_is_broadcast_only_to_local_clients() {
        let dir = tempfile::tempdir().unwrap();
        let (local_handle, mut local_receiver) = ClientHandle::test_channels();
        let (mobile_handle, mut mobile_receiver) = ClientHandle::test_channels();
        let actor = test_actor(
            &dir,
            HashMap::from([
                (1, local_client(local_handle)),
                (2, mobile_client(mobile_handle, "phone-1")),
            ]),
            HashMap::new(),
        )
        .await;

        actor.broadcast_terminal_pulse_changed(
            "session-1",
            &TerminalPulseConfiguration::default(),
            true,
            None,
        );

        let local = local_receiver.recv().await.unwrap().as_json().unwrap();
        assert_eq!(local["event"], "terminalPulseChanged");
        assert_eq!(local["payload"]["configuration"]["command"], "r");
        assert!(mobile_receiver.try_recv().is_err());
    }
}
