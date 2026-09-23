use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Row, Sqlite, Transaction};

use super::RuntimeStore;

pub(super) const FINAL_RUNS: &str = "'precheckSkipped','misfireSkipped','overlapSkipped','queueLimitSkipped','success','failure','blocked','timeout','cancelled'";

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectAutomationDependency {
    pub id: String,
    pub name: String,
    pub active_runs: i64,
    pub requires_pause: bool,
}

impl RuntimeStore {
    pub(super) async fn migrate_project_automation_dependencies(&self) -> Result<()> {
        let references = format!(
            "CREATE VIEW IF NOT EXISTS automationProjectReferencesV1 AS
             SELECT id AS automationId, COALESCE(json_extract(dataJson, '$.target.projectCheckout.projectId'), json_extract(dataJson, '$.target.projectCheckout.project_id')) AS projectId FROM automations
             UNION SELECT id, COALESCE(json_extract(dataJson, '$.projectId'), json_extract(dataJson, '$.project_id')) FROM automations
             UNION SELECT a.id, w.projectId FROM automations a JOIN workspaces w ON w.id = COALESCE(json_extract(a.dataJson, '$.target.existingTab.workspaceId'), json_extract(a.dataJson, '$.target.existingTab.workspace_id'), json_extract(a.dataJson, '$.target.freshTab.workspaceId'), json_extract(a.dataJson, '$.target.freshTab.workspace_id'), json_extract(a.dataJson, '$.target.managedWorkspace.sourceWorkspaceId'), json_extract(a.dataJson, '$.target.managedWorkspace.source_workspace_id'))
             UNION SELECT r.automationId, w.projectId FROM automationRuns r JOIN workspaces w ON w.id IN (json_extract(r.dataJson, '$.workspaceId'), json_extract(r.dataJson, '$.targetIdentity.workspaceId')) WHERE r.status NOT IN ({FINAL_RUNS})
             UNION SELECT r.automationId, json_extract(a.workspaceJson, '$.projectId') FROM automationRuns r JOIN automationSharedWorkspaceAllocations a ON a.runId = r.id WHERE r.status NOT IN ({FINAL_RUNS})"
        );
        sqlx::query(sqlx::AssertSqlSafe(references))
            .execute(self.pool())
            .await?;
        let predicate = "COALESCE(json_extract(NEW.dataJson, '$.target.projectCheckout.projectId'), json_extract(NEW.dataJson, '$.target.projectCheckout.project_id'))";
        for (event, name) in [("INSERT", "Insert"), ("UPDATE", "Update")] {
            let guard = format!("CREATE TRIGGER IF NOT EXISTS projectCheckoutAutomation{name}Guard BEFORE {event} ON automations WHEN NEW.state = 'active' AND {predicate} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM projects WHERE id = {predicate}) BEGIN SELECT RAISE(ABORT, 'Automation target project no longer exists'); END");
            sqlx::query(sqlx::AssertSqlSafe(guard))
                .execute(self.pool())
                .await?;
            let guard = format!("CREATE TRIGGER IF NOT EXISTS projectCheckoutRun{name}Guard BEFORE {event} ON automationRuns WHEN NEW.status NOT IN ({FINAL_RUNS}) AND EXISTS (SELECT 1 FROM automations a WHERE a.id = NEW.automationId AND COALESCE(json_extract(a.dataJson, '$.target.projectCheckout.projectId'), json_extract(a.dataJson, '$.target.projectCheckout.project_id')) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM projects p WHERE p.id = COALESCE(json_extract(a.dataJson, '$.target.projectCheckout.projectId'), json_extract(a.dataJson, '$.target.projectCheckout.project_id')))) BEGIN SELECT RAISE(ABORT, 'Automation target project no longer exists'); END");
            sqlx::query(sqlx::AssertSqlSafe(guard))
                .execute(self.pool())
                .await?;
        }
        let guard = format!("CREATE TRIGGER IF NOT EXISTS preserveProjectAutomationDependencies BEFORE DELETE ON projects WHEN EXISTS (SELECT 1 FROM automationProjectReferencesV1 d JOIN automations a ON a.id = d.automationId WHERE d.projectId = OLD.id AND (a.state = 'active' OR EXISTS (SELECT 1 FROM automationRuns r WHERE r.automationId = a.id AND r.status NOT IN ({FINAL_RUNS})))) BEGIN SELECT RAISE(ABORT, 'Pause dependent automations and cancel their active runs before removing the project'); END");
        sqlx::query(sqlx::AssertSqlSafe(guard))
            .execute(self.pool())
            .await?;
        Ok(())
    }

    pub async fn project_automation_dependencies(
        &self,
        project_id: &str,
    ) -> Result<Vec<ProjectAutomationDependency>> {
        let mut tx = self.pool().begin().await?;
        let dependencies = project_dependencies(&mut tx, project_id).await?;
        tx.commit().await?;
        Ok(dependencies)
    }

    pub async fn require_project_automation_idle(&self, project_id: &str) -> Result<()> {
        require_idle(self.project_automation_dependencies(project_id).await?)
    }
}

pub(super) async fn require_project_automation_idle_in_transaction(
    tx: &mut Transaction<'_, Sqlite>,
    project_id: &str,
) -> Result<()> {
    require_idle(project_dependencies(tx, project_id).await?)
}

fn require_idle(dependencies: Vec<ProjectAutomationDependency>) -> Result<()> {
    let active: Vec<_> = dependencies
        .into_iter()
        .filter(|dependency| dependency.requires_pause)
        .map(|dependency| {
            format!(
                "{} ({}, {} active runs)",
                dependency.name, dependency.id, dependency.active_runs
            )
        })
        .collect();
    if !active.is_empty() {
        bail!("Pause dependent automations and cancel their active runs before removing the project: {}", active.join(", "));
    }
    Ok(())
}

async fn project_dependencies(
    tx: &mut Transaction<'_, Sqlite>,
    project_id: &str,
) -> Result<Vec<ProjectAutomationDependency>> {
    let query = format!("SELECT DISTINCT a.id, COALESCE(json_extract(a.dataJson, '$.name'), a.id) AS name, a.state, (SELECT count(*) FROM automationRuns r WHERE r.automationId = a.id AND r.status NOT IN ({FINAL_RUNS})) AS activeRuns FROM automationProjectReferencesV1 d JOIN automations a ON a.id = d.automationId WHERE d.projectId = ? ORDER BY a.id");
    sqlx::query(sqlx::AssertSqlSafe(query))
        .bind(project_id)
        .fetch_all(&mut **tx)
        .await?
        .into_iter()
        .map(|row| {
            let active_runs: i64 = row.try_get("activeRuns")?;
            let state: String = row.try_get("state")?;
            Ok(ProjectAutomationDependency {
                id: row.try_get("id")?,
                name: row.try_get("name")?,
                active_runs,
                requires_pause: state == "active" || active_runs > 0,
            })
        })
        .collect()
}
