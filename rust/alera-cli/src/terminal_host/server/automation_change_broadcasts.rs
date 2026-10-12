use alera_core::runtime::{AutomationRun, AutomationRunStatus, AutomationSchedule};
use serde_json::json;

use crate::terminal_host::protocol::event;

use super::runtime_change_broadcasts::scope_payload;
use super::ServerActor;

/// Automation change events. A definition change carries its automation id
/// and only a bulk change (purge, a removed catalog) sends the wildcard; a run
/// change names the run and its new status so a watcher can refresh one row.
/// Both payloads are additive, so they never bump the protocol version.
impl ServerActor {
    pub(super) fn broadcast_automation_changed(&self, automation_id: Option<&str>) {
        self.broadcast_authenticated(event(
            "automationsChanged",
            scope_payload("automationId", automation_id),
        ));
    }

    pub(super) fn broadcast_automation_run_changed(&self, run: &AutomationRun) {
        self.broadcast_authenticated(event(
            "automationRunChanged",
            json!({
                "automationId": run.automation_id,
                "runId": run.id,
                "status": run.status.as_str(),
            }),
        ));
        // The store archives a one-time automation when its run ends.
        if run.status.is_final()
            && run.definition_snapshot.as_ref().is_some_and(|definition| {
                matches!(definition.schedule, AutomationSchedule::OneTime { .. })
            })
        {
            self.broadcast_automation_changed(Some(&run.automation_id));
        }
    }

    /// Moves a run to `status` and tells watchers. Errors are returned to the
    /// caller, which decides whether a failed write matters.
    pub(super) async fn set_automation_run_status(
        &self,
        run_id: &str,
        status: AutomationRunStatus,
        error: Option<String>,
    ) -> anyhow::Result<AutomationRun> {
        let run = self
            .runtime_store
            .update_automation_run_status(run_id, status, error)
            .await?;
        self.broadcast_automation_run_changed(&run);
        Ok(run)
    }
}
