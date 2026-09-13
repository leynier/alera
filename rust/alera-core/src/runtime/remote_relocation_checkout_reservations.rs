use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_remote_relocation_checkout_reservations(&self) -> Result<()> {
        sqlx::query("CREATE VIEW IF NOT EXISTS remoteRelocationLinkedPaths AS SELECT id, workspaceId, hostId, json_extract(dataJson, '$.source.path') AS path FROM remoteWorkspaceRelocationIntents WHERE completed = 0 AND json_extract(dataJson, '$.source.kind') = 'linked' UNION ALL SELECT id, workspaceId, hostId, json_extract(dataJson, '$.destinationPath') AS path FROM remoteWorkspaceRelocationIntents WHERE completed = 0 AND json_extract(dataJson, '$.intent.toProjectCheckout') = 0")
            .execute(self.pool()).await?;
        for (name, operation) in [
            ("reserveRemoteRelocationBindingInsert", "INSERT"),
            ("reserveRemoteRelocationBindingUpdate", "UPDATE"),
        ] {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "CREATE TRIGGER IF NOT EXISTS {name} BEFORE {operation} ON workspaceCheckoutBindings
                 WHEN EXISTS (SELECT 1 FROM repositoryCheckouts c JOIN remoteRelocationLinkedPaths r ON r.hostId = c.hostId AND r.path = c.path
                              WHERE c.id = NEW.checkoutId AND r.workspaceId != NEW.workspaceId)
                 BEGIN SELECT RAISE(ABORT, 'Checkout is reserved by an unfinished SSH relocation'); END"
            ))).execute(self.pool()).await?;
        }
        for statement in [
            "CREATE TRIGGER IF NOT EXISTS reserveRemoteRelocationLinkedOwner BEFORE INSERT ON remoteWorkspaceRelocationIntents
             WHEN EXISTS (SELECT 1 FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b ON b.checkoutId = c.id
                          WHERE c.hostId = NEW.hostId AND b.workspaceId != NEW.workspaceId
                          AND c.path = CASE WHEN json_extract(NEW.dataJson, '$.intent.toProjectCheckout') = 1 THEN json_extract(NEW.dataJson, '$.source.path') ELSE json_extract(NEW.dataJson, '$.destinationPath') END)
             BEGIN SELECT RAISE(ABORT, 'SSH relocation worktree belongs to another task'); END",
            "CREATE TRIGGER IF NOT EXISTS reserveRemoteRelocationLinkedIntent BEFORE INSERT ON remoteWorkspaceRelocationIntents
             WHEN EXISTS (SELECT 1 FROM remoteRelocationLinkedPaths r WHERE r.hostId = NEW.hostId
                          AND r.path IN (json_extract(NEW.dataJson, '$.source.path'), json_extract(NEW.dataJson, '$.destinationPath')))
             OR EXISTS (SELECT 1 FROM workspaceRelocations r WHERE r.hostId = NEW.hostId AND r.completed = 0
                        AND ((json_extract(r.dataJson, '$.source.kind') = 'linked' AND json_extract(r.dataJson, '$.source.path') IN (json_extract(NEW.dataJson, '$.source.path'), json_extract(NEW.dataJson, '$.destinationPath')))
                          OR (json_extract(r.dataJson, '$.destination.kind') = 'linked' AND json_extract(r.dataJson, '$.destination.path') IN (json_extract(NEW.dataJson, '$.source.path'), json_extract(NEW.dataJson, '$.destinationPath')))))
             BEGIN SELECT RAISE(ABORT, 'Checkout is reserved by another unfinished relocation'); END",
            "CREATE TRIGGER IF NOT EXISTS reserveWorkspaceRelocationAgainstRemotePaths BEFORE INSERT ON workspaceRelocations
             WHEN EXISTS (SELECT 1 FROM remoteRelocationLinkedPaths r WHERE r.hostId = NEW.hostId AND r.id != NEW.id
                          AND r.path IN (json_extract(NEW.dataJson, '$.source.path'), json_extract(NEW.dataJson, '$.destination.path')))
             BEGIN SELECT RAISE(ABORT, 'Checkout is reserved by an unfinished SSH relocation'); END",
        ] {
            sqlx::query(statement).execute(self.pool()).await?;
        }
        Ok(())
    }
}
