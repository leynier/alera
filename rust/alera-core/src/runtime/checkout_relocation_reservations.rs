use anyhow::Result;

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_checkout_relocation_reservations(&self) -> Result<()> {
        // A Hand On releases its old binding before physical cleanup. Keep that
        // directory reserved until the journal confirms cleanup, across projects.
        for (name, operation) in [
            ("reserveRelocationCheckoutInsert", "INSERT"),
            ("reserveRelocationCheckoutUpdate", "UPDATE"),
        ] {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "CREATE TRIGGER IF NOT EXISTS {name} BEFORE {operation} ON workspaceCheckoutBindings
                 WHEN EXISTS (
                   SELECT 1 FROM repositoryCheckouts c JOIN workspaceRelocations r ON r.hostId = c.hostId
                   WHERE c.id = NEW.checkoutId AND r.completed = 0 AND r.workspaceId != NEW.workspaceId
                   AND ((json_extract(r.dataJson, '$.source.kind') = 'linked' AND json_extract(r.dataJson, '$.source.path') = c.path)
                     OR (json_extract(r.dataJson, '$.destination.kind') = 'linked' AND json_extract(r.dataJson, '$.destination.path') = c.path)))
                 BEGIN SELECT RAISE(ABORT, 'Checkout is reserved by an unfinished relocation; recover it before adopting this path'); END"
            ))).execute(self.pool()).await?;
        }
        sqlx::query(
            "CREATE TRIGGER IF NOT EXISTS reserveRelocationCheckoutOwner BEFORE INSERT ON workspaceRelocations
             WHEN EXISTS (
               SELECT 1 FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b ON b.checkoutId = c.id
               WHERE c.hostId = NEW.hostId AND b.workspaceId != NEW.workspaceId
               AND ((json_extract(NEW.dataJson, '$.source.kind') = 'linked' AND json_extract(NEW.dataJson, '$.source.path') = c.path)
                 OR (json_extract(NEW.dataJson, '$.destination.kind') = 'linked' AND json_extract(NEW.dataJson, '$.destination.path') = c.path)))
             BEGIN SELECT RAISE(ABORT, 'Relocation checkout belongs to another workspace'); END"
        ).execute(self.pool()).await?;
        sqlx::query(
            "CREATE TRIGGER IF NOT EXISTS reserveRelocationCheckoutIntent BEFORE INSERT ON workspaceRelocations
             WHEN EXISTS (
               SELECT 1 FROM workspaceRelocations r,
                 json_each(json_array(json_extract(r.dataJson, '$.source'), json_extract(r.dataJson, '$.destination'))) oldLocation,
                 json_each(json_array(json_extract(NEW.dataJson, '$.source'), json_extract(NEW.dataJson, '$.destination'))) newLocation
               WHERE r.hostId = NEW.hostId AND r.completed = 0
                 AND json_extract(oldLocation.value, '$.path') = json_extract(newLocation.value, '$.path')
                 AND (json_extract(oldLocation.value, '$.kind') = 'linked' OR json_extract(newLocation.value, '$.kind') = 'linked'))
             BEGIN SELECT RAISE(ABORT, 'Checkout is reserved by another unfinished relocation'); END"
        ).execute(self.pool()).await?;
        Ok(())
    }
}
