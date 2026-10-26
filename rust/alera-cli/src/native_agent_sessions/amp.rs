//! Amp threads belong to the account and sync across machines, so removing a
//! local workspace archives them (reversible) rather than deleting them, and
//! there is no per-path store to sweep.

use std::collections::BTreeMap;

use super::cleanup_context::CleanupContext;
use super::{AgentCleanupRequest, AgentOutcome};

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let mut outcomes = Vec::new();
    for id in request.registered_ids() {
        let result = context
            .run_command("amp", &["threads", "archive", id], &BTreeMap::new())
            .await;
        outcomes.push(AgentOutcome::new(id, result));
    }
    outcomes
}
