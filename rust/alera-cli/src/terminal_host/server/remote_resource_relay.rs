//! Resource metrics for terminals whose processes run on another host.
//!
//! On the hub a remote terminal is an `ssh` child, so a local sweep measures
//! the pipe and not the agent behind it. The satellite runs the real sampler
//! over the same session ids, so on every sampling tick the hub asks each
//! attached satellite for its snapshot and, when answering a client, replaces
//! the rows of the sessions it proxies with the satellite's numbers.
//!
//! The request carries the hub's `intervalMs`, which is what keeps the
//! satellite's demand-driven ticker alive exactly as long as someone is looking
//! at the hub's panel. `cpuPercent` stays per core on the wire, so a relayed row
//! also carries the core count of the machine it was measured on; the app
//! cannot normalize a remote row with the hub's count.

use std::collections::HashMap;

use serde_json::{json, Value};

use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::HostResult;

impl ServerActor {
    /// Asks every attached satellite for its snapshot. Never opens a link: a
    /// resource panel is not a reason to start an ssh session.
    pub(super) fn start_remote_resource_samples(&self, interval_ms: u64) {
        for host_id in self.host_links.attached_host_ids() {
            let links = self.host_links.clone();
            let inbox = self.inbox.clone();
            tokio::spawn(async move {
                let result = async {
                    let link = links.link(&host_id).await?;
                    link.request_with_timeout(
                        "resources.snapshot",
                        json!({ "intervalMs": interval_ms }),
                        crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
                    )
                    .await
                }
                .await;
                let _ = inbox.send(ServerCommand::RemoteResourceSnapshot { host_id, result });
            });
        }
    }

    pub(super) fn finish_remote_resource_sample(
        &mut self,
        host_id: String,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(snapshot) => {
                self.resources.note_remote_snapshot(host_id, snapshot);
            }
            Err(_) => self.resources.forget_remote_snapshot(&host_id),
        }
    }
}

/// Replaces the rows of proxied sessions with the satellite's measurement.
/// Rows the satellite does not report keep the hub's own (unmeasurable) row,
/// and satellite rows the hub does not proxy are left out: they belong to the
/// satellite's own clients.
pub(super) fn merge_remote_sessions(snapshot: &mut Value, remote: &HashMap<String, Value>) {
    if remote.is_empty() {
        return;
    }
    let Some(sessions) = snapshot.get_mut("sessions").and_then(Value::as_array_mut) else {
        return;
    };
    for row in sessions {
        let Some(session_id) = row.get("sessionId").and_then(Value::as_str) else {
            continue;
        };
        let Some((host_id, measured, cores)) = remote.iter().find_map(|(host_id, snapshot)| {
            if snapshot.get("warming").and_then(Value::as_bool) == Some(true) {
                return None;
            }
            let measured = snapshot
                .get("sessions")?
                .as_array()?
                .iter()
                .find(|candidate| {
                    candidate.get("sessionId").and_then(Value::as_str) == Some(session_id)
                })?;
            Some((host_id, measured, snapshot["host"]["cpuCoreCount"].clone()))
        }) else {
            continue;
        };
        for key in [
            "running",
            "shellPid",
            "measured",
            "cpuPercent",
            "memoryBytes",
            "processCount",
            "history",
        ] {
            if let Some(value) = measured.get(key) {
                row[key] = value.clone();
            }
        }
        row["hostId"] = json!(host_id);
        row["cpuCoreCount"] = cores;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hub_snapshot() -> Value {
        json!({
            "warming": false,
            "host": {"cpuCoreCount": 8},
            "sessions": [
                {"sessionId": "proxied", "workspaceId": "w-remote", "tabId": "t1",
                    "running": true, "measured": true, "cpuPercent": 0.1,
                    "memoryBytes": 4096, "processCount": 1, "history": [4096]},
                {"sessionId": "local", "workspaceId": "w-local", "tabId": "t2",
                    "running": true, "measured": true, "cpuPercent": 50.0,
                    "memoryBytes": 1000, "processCount": 2, "history": []},
            ],
        })
    }

    fn satellite_snapshot(warming: bool) -> Value {
        json!({
            "warming": warming,
            "host": {"cpuCoreCount": 32},
            "sessions": [
                {"sessionId": "proxied", "workspaceId": "w-remote", "tabId": "t1",
                    "running": true, "measured": true, "cpuPercent": 310.5,
                    "memoryBytes": 2_000_000, "processCount": 9, "history": [1, 2]},
                {"sessionId": "satellite-only", "measured": true, "cpuPercent": 99.0},
            ],
        })
    }

    #[test]
    fn proxied_rows_take_the_satellite_measurement_and_its_core_count() {
        let mut snapshot = hub_snapshot();
        let remote = HashMap::from([("ssh-1".to_string(), satellite_snapshot(false))]);
        merge_remote_sessions(&mut snapshot, &remote);
        let rows = snapshot["sessions"].as_array().unwrap();
        assert_eq!(rows.len(), 2, "satellite-only rows are not the hub's");
        assert_eq!(rows[0]["cpuPercent"], 310.5);
        assert_eq!(rows[0]["memoryBytes"], 2_000_000);
        assert_eq!(rows[0]["processCount"], 9);
        assert_eq!(rows[0]["hostId"], "ssh-1");
        assert_eq!(rows[0]["cpuCoreCount"], 32);
        assert_eq!(rows[0]["workspaceId"], "w-remote");
        assert_eq!(rows[1]["cpuPercent"], 50.0);
        assert!(rows[1].get("hostId").is_none());
    }

    #[test]
    fn a_warming_satellite_changes_nothing() {
        let mut snapshot = hub_snapshot();
        let remote = HashMap::from([("ssh-1".to_string(), satellite_snapshot(true))]);
        merge_remote_sessions(&mut snapshot, &remote);
        assert_eq!(snapshot, hub_snapshot());
        merge_remote_sessions(&mut snapshot, &HashMap::new());
        assert_eq!(snapshot, hub_snapshot());
    }
}
