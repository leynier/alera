use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::Value;

use super::{ServerActor, ServerCommand};
use crate::terminal_host::demand_driven_ticker::DemandDrivenTicker;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::resources::{
    clamp_resource_interval, resource_idle_stop_for, warming_snapshot, ResourceSampler,
    SessionPidRoot, RESOURCE_IDLE_STOP, RESOURCE_SAMPLE_INTERVAL,
};

/// Resource sampling state, driven lazily: nothing sweeps the process table
/// until a client asks, and the ticker stops itself once they stop asking.
pub(super) struct ResourceMonitorState {
    sampler: Arc<Mutex<ResourceSampler>>,
    ticker: DemandDrivenTicker,
    last_snapshot: Option<Value>,
    sample_in_flight: bool,
    release_sampler_when_ready: bool,
    /// Pid of the app process to attribute, as reported by the last caller.
    app_pid: Option<u32>,
    /// Cadence the ticker is currently running at, following what callers say
    /// they poll at rather than a fixed value.
    interval: Duration,
}

impl Default for ResourceMonitorState {
    fn default() -> Self {
        ResourceMonitorState {
            sampler: Arc::default(),
            ticker: DemandDrivenTicker::new(RESOURCE_IDLE_STOP),
            last_snapshot: None,
            sample_in_flight: false,
            release_sampler_when_ready: false,
            app_pid: None,
            interval: RESOURCE_SAMPLE_INTERVAL,
        }
    }
}

impl ResourceMonitorState {
    fn stop_ticker(&mut self) {
        self.ticker.stop();
        self.last_snapshot = None;
        self.app_pid = None;
        self.interval = RESOURCE_SAMPLE_INTERVAL;
        if self.sample_in_flight {
            self.release_sampler_when_ready = true;
        } else if let Ok(mut sampler) = self.sampler.lock() {
            sampler.release_process_cache();
        }
    }

    fn finish_sample(&mut self, snapshot: Value) {
        self.sample_in_flight = false;
        if self.release_sampler_when_ready {
            self.release_sampler_when_ready = false;
            if let Ok(mut sampler) = self.sampler.lock() {
                sampler.release_process_cache();
            }
            if self.ticker.is_idle() {
                return;
            }
        }
        self.last_snapshot = Some(snapshot);
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
        let interval = parse_sample_interval(payload)?.unwrap_or(RESOURCE_SAMPLE_INTERVAL);
        self.resources
            .ticker
            .set_idle_stop(resource_idle_stop_for(interval));
        self.resources.ticker.note_request();
        let running = self.resources.ticker.is_running();
        if !running || self.resources.interval != interval {
            self.resources.interval = interval;
            self.start_resource_ticker(!running);
        }
        Ok(self
            .resources
            .last_snapshot
            .clone()
            .unwrap_or_else(warming_snapshot))
    }

    /// (Re)start the ticker at the current cadence.
    ///
    /// `reset_baseline` is what distinguishes the two reasons to do this. The
    /// CPU numbers are deltas between refreshes, so after an idle gap the next
    /// delta would describe minutes of history as if it were the last tick and
    /// the baseline has to restart with the ticker. A cadence change on a
    /// ticker that never stopped has no such gap, and resetting there would put
    /// the panel back into "measuring" every time the user hovers it.
    fn start_resource_ticker(&mut self, reset_baseline: bool) {
        if reset_baseline {
            if let Ok(mut sampler) = self.resources.sampler.lock() {
                sampler.reset_cpu_baseline();
            }
        }
        let inbox = self.inbox.clone();
        self.resources
            .ticker
            .start(self.resources.interval, move || {
                inbox.send(ServerCommand::ResourceSampleTick).is_ok()
            });
    }

    /// One tick: stop if nobody is watching, otherwise start a sweep on a
    /// blocking thread.
    pub(super) fn handle_resource_sample_tick(&mut self) {
        if self.resources.ticker.is_idle() {
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
        self.resources.finish_sample(snapshot);
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
/// The cadence the caller says it polls at, clamped to what the sampler serves.
///
/// Additive: a client that sends nothing gets the host's own default, which is
/// what an app predating this expects.
fn parse_sample_interval(payload: &Value) -> HostResult<Option<Duration>> {
    match payload.get("intervalMs") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_u64()
            .filter(|milliseconds| *milliseconds > 0)
            .map(|milliseconds| Some(clamp_resource_interval(Duration::from_millis(milliseconds))))
            .ok_or_else(|| HostError::state("intervalMs must be a positive integer.")),
    }
}

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

    #[test]
    fn an_absent_interval_leaves_the_host_default_in_place() {
        assert_eq!(parse_sample_interval(&json!({})).unwrap(), None);
        assert_eq!(
            parse_sample_interval(&json!({ "intervalMs": null })).unwrap(),
            None
        );
    }

    #[test]
    fn a_stated_interval_is_parsed_and_clamped() {
        assert_eq!(
            parse_sample_interval(&json!({ "intervalMs": 15_000 })).unwrap(),
            Some(Duration::from_secs(15))
        );
        assert_eq!(
            parse_sample_interval(&json!({ "intervalMs": 50 })).unwrap(),
            Some(RESOURCE_SAMPLE_INTERVAL)
        );
    }

    #[test]
    fn a_nonsense_interval_is_rejected() {
        assert!(parse_sample_interval(&json!({ "intervalMs": 0 })).is_err());
        assert!(parse_sample_interval(&json!({ "intervalMs": -1 })).is_err());
        assert!(parse_sample_interval(&json!({ "intervalMs": "fast" })).is_err());
    }

    #[test]
    fn stopping_an_idle_monitor_releases_cached_resources() {
        let mut resources = ResourceMonitorState::default();
        resources
            .sampler
            .lock()
            .unwrap()
            .sample(&[], std::process::id(), None);
        resources.last_snapshot = Some(json!({"sample": true}));
        resources.app_pid = Some(42);

        resources.stop_ticker();

        assert!(resources.last_snapshot.is_none());
        assert!(resources.app_pid.is_none());
        assert_eq!(
            resources
                .sampler
                .lock()
                .unwrap()
                .sample(&[], std::process::id(), None)["warming"],
            json!(true)
        );
    }

    #[test]
    fn an_in_flight_idle_sample_is_discarded_before_releasing_its_cache() {
        let mut resources = ResourceMonitorState::default();
        resources
            .sampler
            .lock()
            .unwrap()
            .sample(&[], std::process::id(), None);
        resources.sample_in_flight = true;

        resources.stop_ticker();
        assert!(resources.release_sampler_when_ready);

        resources.finish_sample(json!({"stale": true}));

        assert!(!resources.sample_in_flight);
        assert!(!resources.release_sampler_when_ready);
        assert!(resources.last_snapshot.is_none());
        assert_eq!(
            resources
                .sampler
                .lock()
                .unwrap()
                .sample(&[], std::process::id(), None)["warming"],
            json!(true)
        );
    }
}
