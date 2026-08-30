use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqliteConnection};
use uuid::Uuid;

use super::RuntimeStore;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceSection {
    pub id: String,
    pub name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

pub(super) const SECTION_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS workspaceSections (
        id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
    )",
    "CREATE TABLE IF NOT EXISTS workspaceSectionAssignments (
        workspaceId TEXT PRIMARY KEY, sectionId TEXT NOT NULL
    )",
    "CREATE INDEX IF NOT EXISTS workspaceSectionMembersIdx ON workspaceSectionAssignments(sectionId)",
    // Triggers also cover workspace/project removal through older clients.
    "CREATE TRIGGER IF NOT EXISTS workspaceSectionWorkspaceDeleted AFTER DELETE ON workspaces BEGIN
        DELETE FROM workspaceSectionAssignments WHERE workspaceId = OLD.id;
    END",
    "CREATE TRIGGER IF NOT EXISTS workspaceSectionWorkspaceRemoved AFTER UPDATE OF status ON workspaces
     WHEN NEW.status = 'removed' BEGIN
        DELETE FROM workspaceSectionAssignments WHERE workspaceId = NEW.id;
    END",
    "CREATE TRIGGER IF NOT EXISTS workspaceSectionMemberDeleted AFTER DELETE ON workspaceSectionAssignments BEGIN
        UPDATE workspaceSections SET updatedAt = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = OLD.sectionId;
        DELETE FROM workspaceSections WHERE id = OLD.sectionId AND NOT EXISTS
            (SELECT 1 FROM workspaceSectionAssignments WHERE sectionId = OLD.sectionId);
    END",
    "CREATE TRIGGER IF NOT EXISTS workspaceSectionMemberMoved AFTER UPDATE OF sectionId ON workspaceSectionAssignments
     WHEN OLD.sectionId != NEW.sectionId BEGIN
        UPDATE workspaceSections SET updatedAt = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = OLD.sectionId;
        DELETE FROM workspaceSections WHERE id = OLD.sectionId AND NOT EXISTS
            (SELECT 1 FROM workspaceSectionAssignments WHERE sectionId = OLD.sectionId);
    END",
];

impl RuntimeStore {
    pub async fn list_workspace_sections(&self) -> Result<Vec<WorkspaceSection>> {
        let rows = sqlx::query("SELECT * FROM workspaceSections ORDER BY name COLLATE NOCASE, id")
            .fetch_all(self.pool())
            .await?;
        rows.into_iter()
            .map(|row| {
                Ok(WorkspaceSection {
                    id: row.try_get("id")?,
                    name: row.try_get("name")?,
                    created_at: row.try_get::<String, _>("createdAt")?.parse()?,
                    updated_at: row.try_get::<String, _>("updatedAt")?.parse()?,
                })
            })
            .collect()
    }

    pub async fn workspace_section_id(&self, workspace_id: &str) -> Result<Option<String>> {
        Ok(sqlx::query_scalar(
            "SELECT sectionId FROM workspaceSectionAssignments WHERE workspaceId = ?",
        )
        .bind(workspace_id)
        .fetch_optional(self.pool())
        .await?)
    }

    pub async fn create_workspace_section(
        &self,
        name: &str,
        workspace_id: &str,
    ) -> Result<WorkspaceSection> {
        let name = name.trim();
        if name.is_empty() {
            bail!("Section name cannot be empty.");
        }
        if name.eq_ignore_ascii_case("Others") {
            bail!("Others is reserved for workspaces without a section.");
        }
        let now = Utc::now();
        let section = WorkspaceSection {
            id: Uuid::new_v4().to_string(),
            name: name.to_owned(),
            created_at: now,
            updated_at: now,
        };
        let mut tx = self.pool().begin().await?;
        // The first statement takes the SQLite write lock before checking the name.
        let inserted = sqlx::query("INSERT INTO workspaceSections (id, name, createdAt, updatedAt) VALUES (?, ?, ?, ?) ON CONFLICT(name) DO NOTHING")
            .bind(&section.id).bind(name).bind(now.to_rfc3339()).bind(now.to_rfc3339())
            .execute(&mut *tx).await?;
        if inserted.rows_affected() == 0 {
            bail!("A section with that name already exists.");
        }
        // SQLite NOCASE only handles ASCII; keep Unicode names consistent with the apps.
        let other_names: Vec<String> =
            sqlx::query_scalar("SELECT name FROM workspaceSections WHERE id != ?")
                .bind(&section.id)
                .fetch_all(&mut *tx)
                .await?;
        if other_names
            .iter()
            .any(|existing| existing.to_lowercase() == name.to_lowercase())
        {
            bail!("A section with that name already exists.");
        }
        assign_section(&mut tx, workspace_id, Some(&section.id)).await?;
        tx.commit().await?;
        Ok(section)
    }

    pub async fn set_workspace_section(
        &self,
        workspace_id: &str,
        section_id: Option<&str>,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        // Acquire the write lock before validating references against concurrent writers.
        sqlx::query("UPDATE workspaceSections SET id = id WHERE id = ?")
            .bind(section_id)
            .execute(&mut *tx)
            .await?;
        assign_section(&mut tx, workspace_id, section_id).await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn remove_workspace_section(&self, section_id: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("DELETE FROM workspaceSectionAssignments WHERE sectionId = ?")
            .bind(section_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workspaceSections WHERE id = ?")
            .bind(section_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }
}

async fn assign_section(
    conn: &mut SqliteConnection,
    workspace_id: &str,
    section_id: Option<&str>,
) -> Result<()> {
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workspaces WHERE id = ? AND status != 'removed')",
    )
    .bind(workspace_id)
    .fetch_one(&mut *conn)
    .await?;
    if !exists {
        bail!("Workspace not found: {workspace_id}");
    }
    if let Some(id) = section_id {
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workspaceSections WHERE id = ?)")
                .bind(id)
                .fetch_one(&mut *conn)
                .await?;
        if !exists {
            bail!("Section no longer exists. Refresh and select another section.");
        }
        let changed = sqlx::query("INSERT INTO workspaceSectionAssignments (workspaceId, sectionId) VALUES (?, ?) ON CONFLICT(workspaceId) DO UPDATE SET sectionId = excluded.sectionId WHERE sectionId != excluded.sectionId")
            .bind(workspace_id).bind(id).execute(&mut *conn).await?;
        if changed.rows_affected() > 0 {
            sqlx::query("UPDATE workspaceSections SET updatedAt = ? WHERE id = ?")
                .bind(Utc::now().to_rfc3339())
                .bind(id)
                .execute(&mut *conn)
                .await?;
        }
    } else {
        sqlx::query("DELETE FROM workspaceSectionAssignments WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *conn)
            .await?;
    }
    Ok(())
}
