use anyhow::Result;
use sqlx::{Sqlite, Transaction};

pub(super) async fn remove_workspace_in_transaction(
    tx: &mut Transaction<'_, Sqlite>,
    workspace_id: &str,
    cascade_tabs: bool,
) -> Result<()> {
    if cascade_tabs {
        sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut **tx)
            .await?;
    }
    for statement in [
        "DELETE FROM linkedReviews WHERE workspaceId = ?",
        "DELETE FROM workbenchLayouts WHERE workspaceId = ?",
        "DELETE FROM workspaceTagAssignments WHERE workspaceId = ?",
    ] {
        sqlx::query(statement)
            .bind(workspace_id)
            .execute(&mut **tx)
            .await?;
    }
    sqlx::query(
        "DELETE FROM workspaceRelations WHERE parentWorkspaceId = ? OR childWorkspaceId = ?",
    )
    .bind(workspace_id)
    .bind(workspace_id)
    .execute(&mut **tx)
    .await?;
    sqlx::query("DELETE FROM workspaces WHERE id = ?")
        .bind(workspace_id)
        .execute(&mut **tx)
        .await?;
    Ok(())
}
