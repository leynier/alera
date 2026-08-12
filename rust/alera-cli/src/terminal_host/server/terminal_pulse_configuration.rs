use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::watcher::GitConfigEnvironment;
use super::{
    terminal_pulse_state, PendingTerminalPulseConfiguration, ServerActor, ServerCommand,
    TerminalPulseConfiguration, WorkspacePulseWatcher,
};

const WATCHER_START_TIMEOUT: Duration = Duration::from_secs(8);

impl ServerActor {
    pub(in crate::terminal_host::server) async fn start_terminal_pulse_configuration(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let session_id = self.require_session(payload)?;
        let configuration: TerminalPulseConfiguration = serde_json::from_value(
            payload
                .get("configuration")
                .cloned()
                .ok_or_else(|| HostError::format("Terminal Pulse configuration is required."))?,
        )
        .map_err(|error| HostError::format(error.to_string()))?;
        configuration.validate()?;
        let armed = payload
            .get("armed")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let (workspace_id, tab_id, session_instance_id) = {
            let session = self
                .sessions
                .get(&session_id)
                .expect("required session exists");
            if !session.running() && armed {
                return Err(HostError::state(
                    "Terminal Pulse cannot arm a terminal that is not running.",
                ));
            }
            (
                session.workspace_id.clone(),
                session.tab_id.clone(),
                session.instance_id(),
            )
        };
        let workspace_root = if armed {
            let workspace = self
                .runtime_store
                .find_workspace(&workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| HostError::state(format!("workspace not found: {workspace_id}")))?;
            Some(PathBuf::from(workspace.path))
        } else {
            None
        };
        let pending = PendingTerminalPulseConfiguration {
            client_id,
            request_id,
            session_id,
            workspace_id: workspace_id.clone(),
            tab_id,
            session_instance_id,
            configuration,
        };
        if !armed
            || self
                .terminal_pulses
                .watchers
                .contains_key(&pending.workspace_id)
        {
            self.cancel_pending_terminal_pulse_configuration(&pending.session_id);
            let cleanup_workspace_id = pending.workspace_id.clone();
            self.apply_terminal_pulse_configuration(pending, armed)
                .await;
            self.terminal_pulses
                .remove_unused_watcher(&cleanup_workspace_id);
            return Ok(());
        }

        if let Some(previous) = self.terminal_pulses.queue_configuration(pending) {
            self.client_write(
                previous.client_id,
                error_response(
                    previous.request_id,
                    &HostError::state("Terminal Pulse configuration was superseded."),
                ),
            );
        }
        if let Some(generation) = self.terminal_pulses.reserve_watcher_start(&workspace_id) {
            let inbox = self.inbox.clone();
            tokio::spawn(async move {
                let environment =
                    crate::login_shell_environment::login_shell_variables_with_process_overrides()
                        .await;
                let git_config_environment = GitConfigEnvironment::from_variables(&environment);
                let setup_cancelled = Arc::new(AtomicBool::new(false));
                let watcher_task = tokio::task::spawn_blocking({
                    let watcher_inbox = inbox.clone();
                    let watcher_workspace_id = workspace_id.clone();
                    let setup_cancelled = Arc::clone(&setup_cancelled);
                    move || {
                        WorkspacePulseWatcher::start_blocking_with_environment(
                            watcher_workspace_id,
                            workspace_root.expect("armed configuration has a workspace root"),
                            generation,
                            watcher_inbox,
                            git_config_environment,
                            setup_cancelled,
                        )
                    }
                });
                let result =
                    await_watcher_start(watcher_task, setup_cancelled, WATCHER_START_TIMEOUT).await;
                let _ = inbox.send(ServerCommand::TerminalPulseWatcherStarted {
                    workspace_id,
                    generation,
                    result,
                });
            });
        }
        Ok(())
    }

    pub(in crate::terminal_host::server) async fn handle_terminal_pulse_watcher_started(
        &mut self,
        workspace_id: String,
        generation: u64,
        result: HostResult<WorkspacePulseWatcher>,
    ) {
        match result {
            Ok(watcher) => {
                let Some(pending) =
                    self.terminal_pulses
                        .finish_watcher_start(&workspace_id, generation, watcher)
                else {
                    return;
                };
                for configuration in pending {
                    self.apply_terminal_pulse_configuration(configuration, true)
                        .await;
                }
                self.terminal_pulses.remove_unused_watcher(&workspace_id);
            }
            Err(error) => {
                let Some(pending) = self
                    .terminal_pulses
                    .fail_watcher_start(&workspace_id, generation)
                else {
                    return;
                };
                for configuration in pending {
                    self.client_write(
                        configuration.client_id,
                        error_response(configuration.request_id, &error),
                    );
                }
            }
        }
    }

    async fn apply_terminal_pulse_configuration(
        &mut self,
        pending: PendingTerminalPulseConfiguration,
        armed: bool,
    ) {
        let current_session = self.sessions.get(&pending.session_id);
        let session_is_current = current_session.is_some_and(|session| {
            session.workspace_id == pending.workspace_id
                && session.tab_id == pending.tab_id
                && session.instance_id() == pending.session_instance_id
                && (!armed || session.running())
        });
        if !session_is_current {
            self.client_write(
                pending.client_id,
                error_response(
                    pending.request_id,
                    &HostError::state(
                        "Terminal Pulse configuration became stale after the terminal changed.",
                    ),
                ),
            );
            return;
        }
        let disarmed_configuration = if armed {
            None
        } else {
            self.terminal_pulses.disarm(&pending.session_id)
        };
        if let Err(error) = self
            .persist_terminal_pulse_configuration(&pending.tab_id, &pending.configuration)
            .await
        {
            if let Some(configuration) = disarmed_configuration {
                self.broadcast_terminal_pulse_changed(
                    &pending.session_id,
                    &configuration,
                    false,
                    None,
                );
            }
            self.client_write(
                pending.client_id,
                error_response(pending.request_id, &error),
            );
            return;
        }
        if armed {
            self.terminal_pulses.arm(
                pending.session_id.clone(),
                pending.workspace_id.clone(),
                pending.session_instance_id,
                pending.configuration.clone(),
            );
        }
        self.broadcast_workspace_tabs_changed(Some(&pending.workspace_id));
        self.broadcast_terminal_pulse_changed(
            &pending.session_id,
            &pending.configuration,
            armed,
            None,
        );
        self.client_write(
            pending.client_id,
            ok_response(
                pending.request_id,
                terminal_pulse_state(pending.configuration, armed),
            ),
        );
    }

    pub(in crate::terminal_host::server) fn cancel_pending_terminal_pulse_configuration(
        &mut self,
        session_id: &str,
    ) {
        if let Some(pending) = self
            .terminal_pulses
            .cancel_pending_configuration(session_id)
        {
            self.client_write(
                pending.client_id,
                error_response(
                    pending.request_id,
                    &HostError::state(
                        "Terminal Pulse configuration was cancelled because the terminal changed.",
                    ),
                ),
            );
        }
    }
}

async fn await_watcher_start<T: Send + 'static>(
    mut watcher_task: tokio::task::JoinHandle<HostResult<T>>,
    setup_cancelled: Arc<AtomicBool>,
    start_timeout: Duration,
) -> HostResult<T> {
    match tokio::time::timeout(start_timeout, &mut watcher_task).await {
        Err(_) => {
            setup_cancelled.store(true, Ordering::Release);
            tokio::spawn(async move {
                let _ = watcher_task.await;
            });
            Err(HostError::state(
                "Terminal Pulse watcher setup timed out before it could be armed.",
            ))
        }
        Ok(Err(error)) => Err(HostError::state(format!(
            "Terminal Pulse watcher task failed: {error}"
        ))),
        Ok(Ok(result)) => result,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;
    use crate::terminal_host::client::ClientHandle;
    use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
    use crate::terminal_host::session::Session;

    #[derive(Debug)]
    struct DropProbe(Arc<AtomicBool>);

    impl Drop for DropProbe {
        fn drop(&mut self) {
            self.0.store(true, Ordering::Release);
        }
    }

    #[tokio::test]
    async fn watcher_timeout_returns_before_and_discards_the_late_result() {
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let cancelled = Arc::new(AtomicBool::new(false));
        let dropped = Arc::new(AtomicBool::new(false));
        let task_dropped = Arc::clone(&dropped);
        let task = tokio::task::spawn_blocking(move || {
            release_rx.recv().unwrap();
            Ok::<_, HostError>(DropProbe(task_dropped))
        });

        let result = tokio::time::timeout(
            Duration::from_millis(200),
            await_watcher_start(task, Arc::clone(&cancelled), Duration::from_millis(10)),
        )
        .await
        .expect("watcher timeout must not await its blocking task");

        assert!(result.unwrap_err().wire_message().contains("timed out"));
        assert!(cancelled.load(Ordering::Acquire));
        release_tx.send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(1), async {
            while !dropped.load(Ordering::Acquire) {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("late watcher result must be discarded by the reaper");
    }

    #[tokio::test]
    async fn watcher_setup_completed_before_timeout_returns_its_result() {
        let cancelled = Arc::new(AtomicBool::new(false));
        let task = tokio::task::spawn_blocking(|| Ok::<_, HostError>("watching"));

        let result =
            await_watcher_start(task, Arc::clone(&cancelled), Duration::from_secs(1)).await;

        assert_eq!(result.unwrap(), "watching");
        assert!(!cancelled.load(Ordering::Acquire));
    }

    #[tokio::test]
    async fn failed_disarm_persistence_still_cancels_the_live_rule() {
        let dir = tempfile::tempdir().unwrap();
        let (client, mut receiver) = ClientHandle::test_channels();
        let session = Session::driver_test_stub("session-1", 80, 24);
        let session_instance_id = session.instance_id();
        let mut actor = test_actor(
            &dir,
            HashMap::from([(1, local_client(client))]),
            HashMap::from([("session-1".to_string(), session)]),
        )
        .await;
        actor.terminal_pulses.arm(
            "session-1".to_string(),
            "workspace".to_string(),
            session_instance_id,
            TerminalPulseConfiguration::default(),
        );
        let active = Arc::clone(&actor.terminal_pulses.rules.get("session-1").unwrap().active);
        actor.runtime_store.pool().close().await;

        actor
            .apply_terminal_pulse_configuration(
                PendingTerminalPulseConfiguration {
                    client_id: 1,
                    request_id: 41,
                    session_id: "session-1".to_string(),
                    workspace_id: "workspace".to_string(),
                    tab_id: "tab-session-1".to_string(),
                    session_instance_id,
                    configuration: TerminalPulseConfiguration::default(),
                },
                false,
            )
            .await;

        assert!(!active.load(Ordering::Acquire));
        assert!(!actor.terminal_pulses.rules.contains_key("session-1"));
        let event = receiver.recv().await.unwrap().as_json().unwrap();
        assert_eq!(event["event"], "terminalPulseChanged");
        assert_eq!(event["payload"]["armed"], false);
        let response = receiver.recv().await.unwrap().as_json().unwrap();
        assert_eq!(response["id"], 41);
        assert_eq!(response["ok"], false);
        assert!(receiver.try_recv().is_err());
    }
}
