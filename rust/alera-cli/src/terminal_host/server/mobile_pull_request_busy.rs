//! One pull request write per workspace at a time, shared by every
//! `mobile.pullRequest.*` write verb.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use serde_json::json;

use crate::terminal_host::host_error::{HostError, HostResult};

/// One pull request write per workspace at a time: two phones (or one phone
/// retrying) must not merge and close the same review concurrently.
pub(super) struct BusyGuard(String);

impl BusyGuard {
    pub(super) fn acquire(workspace_id: &str) -> HostResult<Self> {
        let mut active = active_writes()
            .lock()
            .map_err(|_| HostError::state("Pull request state is unavailable."))?;
        if !active.insert(workspace_id.to_string()) {
            return Err(HostError::conflict(
                "pullRequestBusy",
                "Another pull request action is already running for this workspace.",
                json!({}),
            ));
        }
        Ok(Self(workspace_id.to_string()))
    }
}

impl Drop for BusyGuard {
    fn drop(&mut self) {
        if let Ok(mut active) = active_writes().lock() {
            active.remove(&self.0);
        }
    }
}

fn active_writes() -> &'static Mutex<HashSet<String>> {
    static ACTIVE: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    ACTIVE.get_or_init(Default::default)
}
