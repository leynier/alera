use std::sync::{Arc, Mutex};
use std::time::Instant;

use serde_json::Value;
use tokio::task::JoinHandle;

use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::resources::{
    warming_snapshot, ResourceSampler, SessionPidRoot, RESOURCE_IDLE_STOP, RESOURCE_SAMPLE_INTERVAL,
};

/// Resource sampling state, driven lazily: nothing sweeps the process table
/// until a client asks, and the ticker stops itself once they stop asking.
#[derive(Default)]
pub(super) struct ResourceMonitorState {
    sampler: Arc<Mutex<ResourceSampler>>,
    ticker: Option<JoinHandle<()>>,
    last_snapshot: Option<Value>,
    last_request_at: Option<Instant>,
    sample_in_flight: bool,
    /// Pid of the app process to attribute, as reported by the last caller.
    app_pid: Option<u32>,
}

impl ResourceMonitorState {
    fn stop_ticker(&mut self) {
        if let Some(ticker) = self.ticker.take() {
            ticker.abort();
        }
        self.sample_in_flight = false;
    }
}

impl Drop for ResourceMonitorState {
    fn drop(&mut self) {
        self.stop_ticker();
    }
}

impl ServerActor {
    /// Answer `resources.snapshot` with the most recent sweep and keep the
    /// ticker alive for the caller.
    ///
    /// Never blocks on a sweep: a client polling every two seconds would
    /// otherwise serialize behind a process-table walk.
    pub(super) fn handle_resource_snapshot(&mut self, payload: &Value) -> HostResult<Value> {
        let app_pid = parse_app_pid(payload)?;
        if app_pid.is_some() {
            self.resources.app_pid = app_pid;
        }
        self.resources.last_request_at = Some(Instant::now());
        if self.resources.ticker.is_none() {
            self.start_resource_ticker();
        }
        Ok(self
            .resources
            .last_snapshot
            .clone()
            .unwrap_or_else(warming_snapshot))
    }

    fn start_resource_ticker(&mut self) {
        // The CPU numbers are deltas between refreshes. After an idle gap the
        // next delta would describe minutes of history as if it were the last
        // tick, so the baseline restarts with the ticker.
        if let Ok(mut sampler) = self.resources.sampler.lock() {
            sampler.reset_cpu_baseline();
        }
        let inbox = self.inbox.clone();
        self.resources.ticker = Some(tokio::spawn(async move {
            loop {
                tokio::time::sleep(RESOURCE_SAMPLE_INTERVAL).await;
                if inbox.send(ServerCommand::ResourceSampleTick).is_err() {
                    break;
                }
            }
        }));
    }

    /// One tick: stop if nobody is watching, otherwise start a sweep on a
    /// blocking thread.
    pub(super) fn handle_resource_sample_tick(&mut self) {
        let idle = self
            .resources
            .last_request_at
            .is_none_or(|at| at.elapsed() > RESOURCE_IDLE_STOP);
        if idle {
            self.resources.stop_ticker();
            return;
        }
        if self.resources.sample_in_flight {
            // A previous sweep is still running on a loaded machine. Skipping
            // keeps blocking threads from piling up.
            return;
        }
        self.resources.sample_in_flight = true;
        let roots = self.resource_session_roots();
        let sampler = Arc::clone(&self.resources.sampler);
        let host_pid = std::process::id();
        let app_pid = self.resources.app_pid;
        let inbox = self.inbox.clone();
        tokio::task::spawn_blocking(move || {
            let snapshot = match sampler.lock() {
                Ok(mut sampler) => sampler.sample(&roots, host_pid, app_pid),
                Err(_) => warming_snapshot(),
            };
            let _ = inbox.send(ServerCommand::ResourceSampleReady { snapshot });
        });
    }

    pub(super) fn handle_resource_sample_ready(&mut self, snapshot: Value) {
        self.resources.sample_in_flight = false;
        self.resources.last_snapshot = Some(snapshot);
    }

    fn resource_session_roots(&self) -> Vec<SessionPidRoot> {
        self.sessions
            .values()
            .map(|session| SessionPidRoot {
                session_id: session.id.clone(),
                workspace_id: session.workspace_id.clone(),
                tab_id: session.tab_id.clone(),
                running: session.running(),
                shell: session.shell(),
            })
            .collect()
    }
}

/// The app measures itself through the host because only the host runs the
/// sampler. The pid travels per request rather than in `configure`: it belongs
/// to one client, not to the host's shared configuration.
fn parse_app_pid(payload: &Value) -> HostResult<Option<u32>> {
    match payload.get("appPid") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_u64()
            .and_then(|pid| u32::try_from(pid).ok())
            .filter(|pid| *pid > 0)
            .map(Some)
            .ok_or_else(|| HostError::state("appPid must be a positive integer.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn an_absent_app_pid_is_accepted() {
        assert_eq!(parse_app_pid(&json!({})).unwrap(), None);
        assert_eq!(parse_app_pid(&json!({ "appPid": null })).unwrap(), None);
    }

    #[test]
    fn a_valid_app_pid_is_parsed() {
        assert_eq!(
            parse_app_pid(&json!({ "appPid": 4242 })).unwrap(),
            Some(4242)
        );
    }

    #[test]
    fn a_nonsense_app_pid_is_rejected() {
        assert!(parse_app_pid(&json!({ "appPid": 0 })).is_err());
        assert!(parse_app_pid(&json!({ "appPid": -1 })).is_err());
        assert!(parse_app_pid(&json!({ "appPid": "one" })).is_err());
    }
}
