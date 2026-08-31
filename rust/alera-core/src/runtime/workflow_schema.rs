use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_workflows(&self) -> Result<()> {
        self.migrate_workflow_catalog().await?;
        self.migrate_workflow_plans().await?;
        self.migrate_workflow_workspaces().await?;
        self.migrate_workflow_integrations().await
    }
}
