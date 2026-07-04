use std::collections::{BTreeSet, VecDeque};
use std::path::Path;

use anyhow::Result;
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use sqlx::{Row, SqlitePool};
use thiserror::Error;
use uuid::Uuid;

use super::{
    CascadePreview, Project, ProjectConfig, ProjectConfigMap, ProjectConfigRecord, ProjectKind,
    RuntimeSettings, SshAuthKind, SshBootstrapStatus, SshTarget, WorkbenchLayoutRecord, Workspace,
    WorkspaceKind, WorkspaceRelation, WorkspaceStatus, WorkspaceTabRecord, WorkspaceTag,
};

pub const RUNTIME_DATABASE_FILE_NAME: &str = "runtime.sqlite";
pub const LOCAL_HOST_ID: &str = "local";

#[derive(Debug, Error)]
pub enum RuntimeStoreError {
    #[error("{0}")]
    Message(String),
}

#[derive(Clone)]
pub struct RuntimeStore {
    pool: SqlitePool,
}

pub struct SshTargetBootstrapStateUpdate<'a> {
    pub status: SshBootstrapStatus,
    pub install_dir: Option<&'a str>,
    pub runtime_version: Option<&'a str>,
    pub runtime_platform: Option<&'a str>,
    pub runtime_arch: Option<&'a str>,
    pub last_error: Option<&'a str>,
}

impl RuntimeStore {
    pub async fn open(runtime_dir: &Path) -> Result<Self> {
        if !runtime_dir.exists() {
            std::fs::create_dir_all(runtime_dir)?;
        }
        let path = runtime_dir.join(RUNTIME_DATABASE_FILE_NAME);
        let options = SqliteConnectOptions::new()
            .filename(path)
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal);
        let pool = SqlitePoolOptions::new().connect_with(options).await?;
        let store = RuntimeStore { pool };
        store.migrate().await?;
        Ok(store)
    }

    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    async fn migrate(&self) -> Result<()> {
        for statement in RUNTIME_SCHEMA {
            sqlx::query(statement).execute(&self.pool).await?;
        }
        self.ensure_column("sshTargets", "installDir", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "runtimeVersion", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "runtimePlatform", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "runtimeArch", "TEXT")
            .await?;
        self.ensure_column(
            "sshTargets",
            "bootstrapStatus",
            "TEXT NOT NULL DEFAULT 'notInstalled'",
        )
        .await?;
        self.ensure_column("sshTargets", "lastBootstrapAt", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "lastCheckedAt", "TEXT")
            .await?;
        self.ensure_column("sshTargets", "lastError", "TEXT")
            .await?;
        Ok(())
    }

    async fn ensure_column(&self, table: &str, column: &str, definition: &str) -> Result<()> {
        let rows = sqlx::query(&format!("PRAGMA table_info({table})"))
            .fetch_all(&self.pool)
            .await?;
        let exists = rows.iter().any(|row| {
            row.try_get::<String, _>("name")
                .is_ok_and(|name| name == column)
        });
        if !exists {
            sqlx::query(&format!(
                "ALTER TABLE {table} ADD COLUMN {column} {definition}"
            ))
            .execute(&self.pool)
            .await?;
        }
        Ok(())
    }

    pub async fn get_metadata(&self, key: &str) -> Result<Option<String>> {
        let row = sqlx::query("SELECT value FROM runtimeMetadata WHERE key = ?")
            .bind(key)
            .fetch_optional(&self.pool)
            .await?;
        row.map(|row| row.try_get("value"))
            .transpose()
            .map_err(Into::into)
    }

    pub async fn set_metadata(&self, key: &str, value: &str) -> Result<()> {
        sqlx::query(
            "INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
        )
        .bind(key)
        .bind(value)
        .bind(format_timestamp(Utc::now()))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn runtime_settings(&self) -> Result<RuntimeSettings> {
        Ok(RuntimeSettings {
            workspace_directory: self.get_workspace_directory().await?,
        })
    }

    pub async fn get_workspace_directory(&self) -> Result<Option<String>> {
        self.get_metadata("settings.general.workspaceDirectory")
            .await
    }

    pub async fn set_workspace_directory(&self, path: Option<&str>) -> Result<RuntimeSettings> {
        match path.map(str::trim).filter(|value| !value.is_empty()) {
            Some(value) => {
                self.set_metadata("settings.general.workspaceDirectory", value)
                    .await?;
            }
            None => {
                sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
                    .bind("settings.general.workspaceDirectory")
                    .execute(&self.pool)
                    .await?;
            }
        }
        self.runtime_settings().await
    }

    pub async fn list_projects(&self) -> Result<Vec<Project>> {
        let rows = sqlx::query(
            "SELECT id, name, repoPath, createdAt, updatedAt, kind \
             FROM projects ORDER BY updatedAt DESC, name COLLATE NOCASE ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(project_from_row).collect()
    }

    pub async fn find_project(&self, project_id: &str) -> Result<Option<Project>> {
        let row = sqlx::query(
            "SELECT id, name, repoPath, createdAt, updatedAt, kind FROM projects WHERE id = ?",
        )
        .bind(project_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(project_from_row).transpose()
    }

    pub async fn upsert_project(&self, project: Project) -> Result<Project> {
        sqlx::query(
            "INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind) \
             VALUES (?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             name = excluded.name, repoPath = excluded.repoPath, \
             updatedAt = excluded.updatedAt, kind = excluded.kind",
        )
        .bind(&project.id)
        .bind(&project.name)
        .bind(&project.repo_path)
        .bind(format_timestamp(project.created_at))
        .bind(format_timestamp(project.updated_at))
        .bind(project.kind.as_str())
        .execute(&self.pool)
        .await?;
        Ok(project)
    }

    pub async fn remove_project(&self, project_id: &str) -> Result<()> {
        let workspace_ids: Vec<String> =
            sqlx::query("SELECT id FROM workspaces WHERE projectId = ?")
                .bind(project_id)
                .fetch_all(&self.pool)
                .await?
                .into_iter()
                .map(|row| row.try_get("id"))
                .collect::<Result<Vec<String>, _>>()?;
        let mut tx = self.pool.begin().await?;
        for workspace_id in workspace_ids {
            sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ?")
                .bind(&workspace_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query(
                "DELETE FROM workspaceRelations \
                 WHERE parentWorkspaceId = ? OR childWorkspaceId = ?",
            )
            .bind(&workspace_id)
            .bind(&workspace_id)
            .execute(&mut *tx)
            .await?;
        }
        sqlx::query("DELETE FROM workspaces WHERE projectId = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM projects WHERE id = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM projectConfigs WHERE projectId = ?")
            .bind(project_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn find_project_config(&self, project_id: &str) -> Result<Option<ProjectConfig>> {
        let row = sqlx::query("SELECT dataJson FROM projectConfigs WHERE projectId = ?")
            .bind(project_id)
            .fetch_optional(&self.pool)
            .await?;
        row.map(project_config_from_row).transpose()
    }

    pub async fn list_project_configs(&self) -> Result<ProjectConfigMap> {
        let rows = sqlx::query("SELECT projectId, dataJson FROM projectConfigs")
            .fetch_all(&self.pool)
            .await?;
        let mut configs = ProjectConfigMap::new();
        for row in rows {
            let project_id: String = row.try_get("projectId")?;
            configs.insert(project_id, project_config_from_row(row)?);
        }
        Ok(configs)
    }

    pub async fn upsert_project_config(
        &self,
        project_id: &str,
        config: ProjectConfig,
        updated_at: DateTime<Utc>,
    ) -> Result<ProjectConfigRecord> {
        sqlx::query(
            "INSERT INTO projectConfigs (projectId, dataJson, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(projectId) DO UPDATE SET dataJson = excluded.dataJson, updatedAt = excluded.updatedAt",
        )
        .bind(project_id)
        .bind(serde_json::to_string(&config)?)
        .bind(format_timestamp(updated_at))
        .execute(&self.pool)
        .await?;
        Ok(ProjectConfigRecord {
            project_id: project_id.to_string(),
            config,
            updated_at,
        })
    }

    pub async fn remove_project_config(&self, project_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM projectConfigs WHERE projectId = ?")
            .bind(project_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn list_workspaces(&self, project_id: &str) -> Result<Vec<Workspace>> {
        let rows = sqlx::query(
            "SELECT id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
             kind, status, sourceBranch, reusesExistingBranch \
             FROM workspaces WHERE projectId = ? AND status = 'active' \
             ORDER BY CASE kind WHEN 'main' THEN 0 ELSE 1 END, createdAt ASC, name COLLATE NOCASE ASC",
        )
        .bind(project_id)
        .fetch_all(&self.pool)
        .await?;
        self.workspace_rows(rows).await
    }

    pub async fn list_all_workspaces(&self) -> Result<Vec<Workspace>> {
        let rows = sqlx::query(
            "SELECT id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
             kind, status, sourceBranch, reusesExistingBranch \
             FROM workspaces WHERE status = 'active' \
             ORDER BY projectId ASC, CASE kind WHEN 'main' THEN 0 ELSE 1 END, createdAt ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        self.workspace_rows(rows).await
    }

    pub async fn find_workspace(&self, workspace_id: &str) -> Result<Option<Workspace>> {
        let row = sqlx::query(
            "SELECT id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
             kind, status, sourceBranch, reusesExistingBranch FROM workspaces WHERE id = ?",
        )
        .bind(workspace_id)
        .fetch_optional(&self.pool)
        .await?;
        match row {
            Some(row) => Ok(Some(self.workspace_from_row(row).await?)),
            None => Ok(None),
        }
    }

    pub async fn upsert_workspace(&self, mut workspace: Workspace) -> Result<Workspace> {
        if workspace.instance_id.trim().is_empty() {
            workspace.instance_id = Uuid::new_v4().to_string();
        }
        if workspace.host_id.trim().is_empty() {
            workspace.host_id = LOCAL_HOST_ID.to_string();
        }
        sqlx::query(
            "INSERT INTO workspaces \
             (id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
              kind, status, sourceBranch, reusesExistingBranch) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             instanceId = excluded.instanceId, hostId = excluded.hostId, projectId = excluded.projectId, \
             name = excluded.name, branch = excluded.branch, path = excluded.path, \
             updatedAt = excluded.updatedAt, kind = excluded.kind, status = excluded.status, \
             sourceBranch = excluded.sourceBranch, reusesExistingBranch = excluded.reusesExistingBranch",
        )
        .bind(&workspace.id)
        .bind(&workspace.instance_id)
        .bind(&workspace.host_id)
        .bind(&workspace.project_id)
        .bind(&workspace.name)
        .bind(&workspace.branch)
        .bind(&workspace.path)
        .bind(format_timestamp(workspace.created_at))
        .bind(format_timestamp(workspace.updated_at))
        .bind(workspace.kind.as_str())
        .bind(workspace.status.as_str())
        .bind(&workspace.source_branch)
        .bind(if workspace.reuses_existing_branch { 1_i64 } else { 0_i64 })
        .execute(&self.pool)
        .await?;
        self.find_workspace(&workspace.id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "workspace not found after upsert: {}",
                workspace.id
            )))
        })
    }

    pub async fn remove_workspace(&self, workspace_id: &str, cascade_tabs: bool) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        if cascade_tabs {
            sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
                .bind(workspace_id)
                .execute(&mut *tx)
                .await?;
        }
        sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "DELETE FROM workspaceRelations WHERE parentWorkspaceId = ? OR childWorkspaceId = ?",
        )
        .bind(workspace_id)
        .bind(workspace_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM workspaces WHERE id = ?")
            .bind(workspace_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn remove_workspaces_for_project(&self, project_id: &str) -> Result<()> {
        let workspaces = self.list_workspaces(project_id).await?;
        for workspace in workspaces {
            self.remove_workspace(&workspace.id, true).await?;
        }
        Ok(())
    }

    pub async fn list_workspace_tabs(&self, workspace_id: &str) -> Result<Vec<WorkspaceTabRecord>> {
        let rows = sqlx::query(
            "SELECT id, workspaceId, kind, title, createdAt, updatedAt, payloadJson \
             FROM workspaceTabs WHERE workspaceId = ? ORDER BY createdAt ASC",
        )
        .bind(workspace_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(tab_from_row).collect()
    }

    pub async fn find_workspace_tab(&self, tab_id: &str) -> Result<Option<WorkspaceTabRecord>> {
        let row = sqlx::query(
            "SELECT id, workspaceId, kind, title, createdAt, updatedAt, payloadJson \
             FROM workspaceTabs WHERE id = ?",
        )
        .bind(tab_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(tab_from_row).transpose()
    }

    pub async fn upsert_workspace_tab(
        &self,
        mut tab: WorkspaceTabRecord,
    ) -> Result<WorkspaceTabRecord> {
        if tab.payload.is_null() {
            tab.payload = serde_json::json!({});
        }
        sqlx::query(
            "INSERT INTO workspaceTabs (id, workspaceId, kind, title, createdAt, updatedAt, payloadJson) \
             VALUES (?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             workspaceId = excluded.workspaceId, kind = excluded.kind, title = excluded.title, \
             updatedAt = excluded.updatedAt, payloadJson = excluded.payloadJson",
        )
        .bind(&tab.id)
        .bind(&tab.workspace_id)
        .bind(&tab.kind)
        .bind(&tab.title)
        .bind(format_timestamp(tab.created_at))
        .bind(format_timestamp(tab.updated_at))
        .bind(serde_json::to_string(&tab.payload)?)
        .execute(&self.pool)
        .await?;
        Ok(tab)
    }

    pub async fn remove_workspace_tab(&self, tab_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workspaceTabs WHERE id = ?")
            .bind(tab_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn remove_workspace_tabs_for_workspace(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workspaceTabs WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn find_workbench_layout(
        &self,
        workspace_id: &str,
    ) -> Result<Option<WorkbenchLayoutRecord>> {
        let row =
            sqlx::query("SELECT workspaceId, dataJson FROM workbenchLayouts WHERE workspaceId = ?")
                .bind(workspace_id)
                .fetch_optional(&self.pool)
                .await?;
        row.map(layout_from_row).transpose()
    }

    pub async fn upsert_workbench_layout(
        &self,
        layout: WorkbenchLayoutRecord,
    ) -> Result<WorkbenchLayoutRecord> {
        sqlx::query(
            "INSERT INTO workbenchLayouts (workspaceId, dataJson) VALUES (?, ?) \
             ON CONFLICT(workspaceId) DO UPDATE SET dataJson = excluded.dataJson",
        )
        .bind(&layout.workspace_id)
        .bind(serde_json::to_string(&layout.data)?)
        .execute(&self.pool)
        .await?;
        Ok(layout)
    }

    pub async fn remove_workbench_layout(&self, workspace_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workbenchLayouts WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn list_tags(&self) -> Result<Vec<WorkspaceTag>> {
        let rows = sqlx::query(
            "SELECT id, name, color, createdAt, updatedAt FROM workspaceTags \
             ORDER BY name COLLATE NOCASE ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(tag_from_row).collect()
    }

    pub async fn upsert_tag(&self, tag: WorkspaceTag) -> Result<WorkspaceTag> {
        // Tag names are unique (COLLATE NOCASE). Callers mint a fresh id per
        // create, so a duplicate name must reuse the existing row instead of
        // tripping the unique name index.
        if let Some(row) = sqlx::query(
            "SELECT id, name, color, createdAt, updatedAt FROM workspaceTags \
             WHERE name = ? COLLATE NOCASE AND id != ?",
        )
        .bind(&tag.name)
        .bind(&tag.id)
        .fetch_optional(&self.pool)
        .await?
        {
            return tag_from_row(row);
        }
        sqlx::query(
            "INSERT INTO workspaceTags (id, name, color, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, color = excluded.color, updatedAt = excluded.updatedAt",
        )
        .bind(&tag.id)
        .bind(&tag.name)
        .bind(&tag.color)
        .bind(format_timestamp(tag.created_at))
        .bind(format_timestamp(tag.updated_at))
        .execute(&self.pool)
        .await?;
        Ok(tag)
    }

    pub async fn remove_tag(&self, tag_id: &str) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE tagId = ?")
            .bind(tag_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM workspaceTags WHERE id = ?")
            .bind(tag_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn assign_tag(&self, workspace_id: &str, tag_id: &str) -> Result<()> {
        sqlx::query(
            "INSERT OR IGNORE INTO workspaceTagAssignments (workspaceId, tagId) VALUES (?, ?)",
        )
        .bind(workspace_id)
        .bind(tag_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn unassign_tag(&self, workspace_id: &str, tag_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM workspaceTagAssignments WHERE workspaceId = ? AND tagId = ?")
            .bind(workspace_id)
            .bind(tag_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn list_relations(&self) -> Result<Vec<WorkspaceRelation>> {
        let rows = sqlx::query(
            "SELECT id, parentWorkspaceId, parentInstanceId, childWorkspaceId, childInstanceId, createdAt \
             FROM workspaceRelations ORDER BY createdAt ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(relation_from_row).collect()
    }

    pub async fn link_workspaces(
        &self,
        parent_workspace_id: &str,
        child_workspace_id: &str,
    ) -> Result<WorkspaceRelation> {
        if parent_workspace_id == child_workspace_id {
            return Err(RuntimeStoreError::Message(
                "Workspace cannot be related to itself".to_string(),
            )
            .into());
        }
        let parent = self
            .find_workspace(parent_workspace_id)
            .await?
            .ok_or_else(|| RuntimeStoreError::Message("Parent workspace not found".to_string()))?;
        let child = self
            .find_workspace(child_workspace_id)
            .await?
            .ok_or_else(|| RuntimeStoreError::Message("Child workspace not found".to_string()))?;
        if self
            .descendant_ids(child_workspace_id)
            .await?
            .contains(parent_workspace_id)
        {
            return Err(RuntimeStoreError::Message(
                "Workspace relation would create a cycle".to_string(),
            )
            .into());
        }
        let existing_parent: Option<String> = sqlx::query(
            "SELECT parentWorkspaceId FROM workspaceRelations WHERE childWorkspaceId = ?",
        )
        .bind(child_workspace_id)
        .fetch_optional(&self.pool)
        .await?
        .map(|row| row.try_get("parentWorkspaceId"))
        .transpose()?;
        if existing_parent
            .as_deref()
            .is_some_and(|existing| existing != parent_workspace_id)
        {
            return Err(RuntimeStoreError::Message(
                "Child workspace already has a parent".to_string(),
            )
            .into());
        }
        let now = Utc::now();
        let relation = WorkspaceRelation {
            id: existing_relation_id(&self.pool, parent_workspace_id, child_workspace_id)
                .await?
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
            parent_workspace_id: parent.id,
            parent_instance_id: parent.instance_id,
            child_workspace_id: child.id,
            child_instance_id: child.instance_id,
            created_at: now,
        };
        sqlx::query(
            "INSERT OR IGNORE INTO workspaceRelations \
             (id, parentWorkspaceId, parentInstanceId, childWorkspaceId, childInstanceId, createdAt) \
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&relation.id)
        .bind(&relation.parent_workspace_id)
        .bind(&relation.parent_instance_id)
        .bind(&relation.child_workspace_id)
        .bind(&relation.child_instance_id)
        .bind(format_timestamp(relation.created_at))
        .execute(&self.pool)
        .await?;
        Ok(relation)
    }

    pub async fn unlink_workspaces(
        &self,
        parent_workspace_id: &str,
        child_workspace_id: &str,
    ) -> Result<()> {
        sqlx::query(
            "DELETE FROM workspaceRelations WHERE parentWorkspaceId = ? AND childWorkspaceId = ?",
        )
        .bind(parent_workspace_id)
        .bind(child_workspace_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn cascade_preview(
        &self,
        root_workspace_ids: &[String],
        tag_ids: &[String],
        include_descendants: bool,
        include_tags: bool,
    ) -> Result<CascadePreview> {
        let mut ids = BTreeSet::<String>::new();
        for id in root_workspace_ids {
            ids.insert(id.clone());
            if include_descendants {
                ids.extend(self.descendant_ids(id).await?);
            }
        }
        if include_tags {
            for tag_id in tag_ids {
                let rows =
                    sqlx::query("SELECT workspaceId FROM workspaceTagAssignments WHERE tagId = ?")
                        .bind(tag_id)
                        .fetch_all(&self.pool)
                        .await?;
                for row in rows {
                    ids.insert(row.try_get("workspaceId")?);
                }
            }
        }
        Ok(CascadePreview {
            workspace_ids: ids.into_iter().collect(),
        })
    }

    pub async fn list_ssh_targets(&self) -> Result<Vec<SshTarget>> {
        let rows = sqlx::query(
            "SELECT id, alias, host, port, username, platform, arch, authKind, createdAt, updatedAt, lastStatus, \
             installDir, runtimeVersion, runtimePlatform, runtimeArch, bootstrapStatus, lastBootstrapAt, lastCheckedAt, lastError \
             FROM sshTargets ORDER BY alias COLLATE NOCASE ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter().map(ssh_target_from_row).collect()
    }

    pub async fn find_ssh_target(&self, target_id: &str) -> Result<Option<SshTarget>> {
        let row = sqlx::query(
            "SELECT id, alias, host, port, username, platform, arch, authKind, createdAt, updatedAt, lastStatus, \
             installDir, runtimeVersion, runtimePlatform, runtimeArch, bootstrapStatus, lastBootstrapAt, lastCheckedAt, lastError \
             FROM sshTargets WHERE id = ?",
        )
        .bind(target_id)
        .fetch_optional(&self.pool)
        .await?;
        row.map(ssh_target_from_row).transpose()
    }

    pub async fn upsert_ssh_target(&self, target: SshTarget) -> Result<SshTarget> {
        sqlx::query(
            "INSERT INTO sshTargets \
             (id, alias, host, port, username, platform, arch, authKind, createdAt, updatedAt, lastStatus, \
              installDir, runtimeVersion, runtimePlatform, runtimeArch, bootstrapStatus, lastBootstrapAt, lastCheckedAt, lastError) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             alias = excluded.alias, host = excluded.host, port = excluded.port, username = excluded.username, \
             platform = excluded.platform, arch = excluded.arch, authKind = excluded.authKind, \
             updatedAt = excluded.updatedAt, lastStatus = excluded.lastStatus, installDir = excluded.installDir",
        )
        .bind(&target.id)
        .bind(&target.alias)
        .bind(&target.host)
        .bind(target.port)
        .bind(&target.username)
        .bind(&target.platform)
        .bind(&target.arch)
        .bind(target.auth_kind.as_str())
        .bind(format_timestamp(target.created_at))
        .bind(format_timestamp(target.updated_at))
        .bind(&target.last_status)
        .bind(&target.install_dir)
        .bind(&target.runtime_version)
        .bind(&target.runtime_platform)
        .bind(&target.runtime_arch)
        .bind(target.bootstrap_status.as_str())
        .bind(target.last_bootstrap_at.map(format_timestamp))
        .bind(target.last_checked_at.map(format_timestamp))
        .bind(&target.last_error)
        .execute(&self.pool)
        .await?;
        self.find_ssh_target(&target.id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found after upsert: {}",
                target.id
            )))
        })
    }

    pub async fn update_ssh_target_bootstrap_state(
        &self,
        target_id: &str,
        update: SshTargetBootstrapStateUpdate<'_>,
    ) -> Result<SshTarget> {
        let now = format_timestamp(Utc::now());
        sqlx::query(
            "UPDATE sshTargets SET \
             bootstrapStatus = ?, installDir = COALESCE(?, installDir), runtimeVersion = COALESCE(?, runtimeVersion), \
             runtimePlatform = COALESCE(?, runtimePlatform), runtimeArch = COALESCE(?, runtimeArch), \
             lastError = ?, lastBootstrapAt = ?, updatedAt = ? WHERE id = ?",
        )
        .bind(update.status.as_str())
        .bind(update.install_dir)
        .bind(update.runtime_version)
        .bind(update.runtime_platform)
        .bind(update.runtime_arch)
        .bind(update.last_error)
        .bind(&now)
        .bind(&now)
        .bind(target_id)
        .execute(&self.pool)
        .await?;
        self.find_ssh_target(target_id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found: {target_id}"
            )))
        })
    }

    pub async fn mark_ssh_target_checked(&self, target_id: &str) -> Result<SshTarget> {
        let now = format_timestamp(Utc::now());
        sqlx::query("UPDATE sshTargets SET lastCheckedAt = ?, updatedAt = ? WHERE id = ?")
            .bind(&now)
            .bind(&now)
            .bind(target_id)
            .execute(&self.pool)
            .await?;
        self.find_ssh_target(target_id).await?.ok_or_else(|| {
            anyhow::anyhow!(RuntimeStoreError::Message(format!(
                "ssh target not found: {target_id}"
            )))
        })
    }

    pub async fn remove_ssh_target(&self, target_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM sshTargets WHERE id = ?")
            .bind(target_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn workspace_rows(&self, rows: Vec<sqlx::sqlite::SqliteRow>) -> Result<Vec<Workspace>> {
        let mut workspaces = Vec::with_capacity(rows.len());
        for row in rows {
            workspaces.push(self.workspace_from_row(row).await?);
        }
        Ok(workspaces)
    }

    async fn workspace_from_row(&self, row: sqlx::sqlite::SqliteRow) -> Result<Workspace> {
        let id: String = row.try_get("id")?;
        let tag_ids = self.tag_ids_for_workspace(&id).await?;
        let tag_names = self.tag_names_for_workspace(&id).await?;
        let parent_workspace_id = sqlx::query(
            "SELECT parentWorkspaceId FROM workspaceRelations WHERE childWorkspaceId = ?",
        )
        .bind(&id)
        .fetch_optional(&self.pool)
        .await?
        .map(|row| row.try_get("parentWorkspaceId"))
        .transpose()?;
        let child_count: i64 = sqlx::query(
            "SELECT COUNT(*) AS childCount FROM workspaceRelations WHERE parentWorkspaceId = ?",
        )
        .bind(&id)
        .fetch_one(&self.pool)
        .await?
        .try_get("childCount")?;
        Ok(Workspace {
            id,
            instance_id: row.try_get("instanceId")?,
            host_id: row.try_get("hostId")?,
            project_id: row.try_get("projectId")?,
            name: row.try_get("name")?,
            branch: empty_to_none(row.try_get("branch")?),
            path: row.try_get("path")?,
            created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
            updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
            kind: WorkspaceKind::from_db(row.try_get::<String, _>("kind")?.as_str()),
            status: WorkspaceStatus::from_db(row.try_get::<String, _>("status")?.as_str()),
            source_branch: empty_to_none(row.try_get("sourceBranch")?),
            reuses_existing_branch: row.try_get::<i64, _>("reusesExistingBranch")? == 1,
            tag_ids,
            tag_names,
            parent_workspace_id,
            child_count,
        })
    }

    async fn tag_ids_for_workspace(&self, workspace_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            "SELECT tagId FROM workspaceTagAssignments WHERE workspaceId = ? ORDER BY tagId ASC",
        )
        .bind(workspace_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| row.try_get("tagId"))
            .collect::<Result<Vec<String>, _>>()
            .map_err(Into::into)
    }

    async fn tag_names_for_workspace(&self, workspace_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            "SELECT tags.name AS tagName \
             FROM workspaceTagAssignments assignments \
             JOIN workspaceTags tags ON tags.id = assignments.tagId \
             WHERE assignments.workspaceId = ? \
             ORDER BY tags.name COLLATE NOCASE ASC",
        )
        .bind(workspace_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|row| row.try_get("tagName"))
            .collect::<Result<Vec<String>, _>>()
            .map_err(Into::into)
    }

    async fn descendant_ids(&self, workspace_id: &str) -> Result<BTreeSet<String>> {
        let mut seen = BTreeSet::<String>::new();
        let mut queue = VecDeque::<String>::from([workspace_id.to_string()]);
        while let Some(parent) = queue.pop_front() {
            let rows = sqlx::query(
                "SELECT childWorkspaceId FROM workspaceRelations WHERE parentWorkspaceId = ?",
            )
            .bind(parent)
            .fetch_all(&self.pool)
            .await?;
            for row in rows {
                let child: String = row.try_get("childWorkspaceId")?;
                if seen.insert(child.clone()) {
                    queue.push_back(child);
                }
            }
        }
        Ok(seen)
    }
}

fn project_from_row(row: sqlx::sqlite::SqliteRow) -> Result<Project> {
    Ok(Project {
        id: row.try_get("id")?,
        name: row.try_get("name")?,
        repo_path: row.try_get("repoPath")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        kind: ProjectKind::from_db(row.try_get::<String, _>("kind")?.as_str()),
    })
}

fn tab_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkspaceTabRecord> {
    let payload_json: String = row.try_get("payloadJson")?;
    Ok(WorkspaceTabRecord {
        id: row.try_get("id")?,
        workspace_id: row.try_get("workspaceId")?,
        kind: row.try_get("kind")?,
        title: row.try_get("title")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        payload: serde_json::from_str(&payload_json).unwrap_or_else(|_| serde_json::json!({})),
    })
}

fn layout_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkbenchLayoutRecord> {
    let data_json: String = row.try_get("dataJson")?;
    Ok(WorkbenchLayoutRecord {
        workspace_id: row.try_get("workspaceId")?,
        data: serde_json::from_str(&data_json).unwrap_or_else(|_| serde_json::json!({})),
    })
}

fn project_config_from_row(row: sqlx::sqlite::SqliteRow) -> Result<ProjectConfig> {
    let data_json: String = row.try_get("dataJson")?;
    Ok(serde_json::from_str(&data_json).unwrap_or_default())
}

fn tag_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkspaceTag> {
    Ok(WorkspaceTag {
        id: row.try_get("id")?,
        name: row.try_get("name")?,
        color: row.try_get("color")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
    })
}

fn relation_from_row(row: sqlx::sqlite::SqliteRow) -> Result<WorkspaceRelation> {
    Ok(WorkspaceRelation {
        id: row.try_get("id")?,
        parent_workspace_id: row.try_get("parentWorkspaceId")?,
        parent_instance_id: row.try_get("parentInstanceId")?,
        child_workspace_id: row.try_get("childWorkspaceId")?,
        child_instance_id: row.try_get("childInstanceId")?,
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
    })
}

fn ssh_target_from_row(row: sqlx::sqlite::SqliteRow) -> Result<SshTarget> {
    let last_bootstrap_at = row
        .try_get::<Option<String>, _>("lastBootstrapAt")?
        .map(|value| parse_timestamp(&value));
    let last_checked_at = row
        .try_get::<Option<String>, _>("lastCheckedAt")?
        .map(|value| parse_timestamp(&value));
    Ok(SshTarget {
        id: row.try_get("id")?,
        alias: row.try_get("alias")?,
        host: row.try_get("host")?,
        port: row.try_get("port")?,
        username: row.try_get("username")?,
        platform: row.try_get("platform")?,
        arch: row.try_get("arch")?,
        auth_kind: SshAuthKind::from_db(row.try_get::<String, _>("authKind")?.as_str()),
        created_at: parse_timestamp(row.try_get::<String, _>("createdAt")?.as_str()),
        updated_at: parse_timestamp(row.try_get::<String, _>("updatedAt")?.as_str()),
        last_status: row.try_get("lastStatus")?,
        install_dir: row.try_get("installDir")?,
        runtime_version: row.try_get("runtimeVersion")?,
        runtime_platform: row.try_get("runtimePlatform")?,
        runtime_arch: row.try_get("runtimeArch")?,
        bootstrap_status: SshBootstrapStatus::from_db(
            row.try_get::<String, _>("bootstrapStatus")?.as_str(),
        ),
        last_bootstrap_at,
        last_checked_at,
        last_error: row.try_get("lastError")?,
    })
}

async fn existing_relation_id(
    pool: &SqlitePool,
    parent_workspace_id: &str,
    child_workspace_id: &str,
) -> Result<Option<String>> {
    sqlx::query(
        "SELECT id FROM workspaceRelations WHERE parentWorkspaceId = ? AND childWorkspaceId = ?",
    )
    .bind(parent_workspace_id)
    .bind(child_workspace_id)
    .fetch_optional(pool)
    .await?
    .map(|row| row.try_get("id"))
    .transpose()
    .map_err(Into::into)
}

pub fn format_timestamp(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(SecondsFormat::Millis, true)
}

pub fn parse_timestamp(value: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(value)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc.timestamp_opt(0, 0).single().expect("epoch is valid"))
}

fn empty_to_none(value: Option<String>) -> Option<String> {
    value.and_then(|v| if v.trim().is_empty() { None } else { Some(v) })
}

const RUNTIME_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS runtimeMetadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        repoPath TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        kind TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS projectConfigs (
        projectId TEXT PRIMARY KEY,
        dataJson TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        instanceId TEXT NOT NULL,
        hostId TEXT NOT NULL,
        projectId TEXT NOT NULL,
        name TEXT NOT NULL,
        branch TEXT,
        path TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        sourceBranch TEXT,
        reusesExistingBranch INTEGER NOT NULL DEFAULT 0
    );",
    "CREATE INDEX IF NOT EXISTS workspacesProjectStatusIdx ON workspaces(projectId, status, kind, createdAt);",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspacesInstanceIdx ON workspaces(instanceId);",
    "CREATE TABLE IF NOT EXISTS workspaceTabs (
        id TEXT PRIMARY KEY,
        workspaceId TEXT NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        payloadJson TEXT NOT NULL DEFAULT '{}'
    );",
    "CREATE INDEX IF NOT EXISTS workspaceTabsWorkspaceIdx ON workspaceTabs(workspaceId, createdAt);",
    "CREATE TABLE IF NOT EXISTS workbenchLayouts (
        workspaceId TEXT PRIMARY KEY,
        dataJson TEXT NOT NULL
    );",
    "CREATE TABLE IF NOT EXISTS workspaceTags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspaceTagsNameIdx ON workspaceTags(name COLLATE NOCASE);",
    "CREATE TABLE IF NOT EXISTS workspaceTagAssignments (
        workspaceId TEXT NOT NULL,
        tagId TEXT NOT NULL,
        PRIMARY KEY(workspaceId, tagId)
    );",
    "CREATE INDEX IF NOT EXISTS workspaceTagAssignmentsTagIdx ON workspaceTagAssignments(tagId, workspaceId);",
    "CREATE TABLE IF NOT EXISTS workspaceRelations (
        id TEXT PRIMARY KEY,
        parentWorkspaceId TEXT NOT NULL,
        parentInstanceId TEXT NOT NULL,
        childWorkspaceId TEXT NOT NULL,
        childInstanceId TEXT NOT NULL,
        createdAt TEXT NOT NULL
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspaceRelationsPairIdx ON workspaceRelations(parentWorkspaceId, childWorkspaceId);",
    "CREATE UNIQUE INDEX IF NOT EXISTS workspaceRelationsChildIdx ON workspaceRelations(childWorkspaceId);",
    "CREATE INDEX IF NOT EXISTS workspaceRelationsParentIdx ON workspaceRelations(parentWorkspaceId);",
    "CREATE TABLE IF NOT EXISTS sshTargets (
        id TEXT PRIMARY KEY,
        alias TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        platform TEXT,
        arch TEXT,
        authKind TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        lastStatus TEXT,
        installDir TEXT,
        runtimeVersion TEXT,
        runtimePlatform TEXT,
        runtimeArch TEXT,
        bootstrapStatus TEXT NOT NULL DEFAULT 'notInstalled',
        lastBootstrapAt TEXT,
        lastCheckedAt TEXT,
        lastError TEXT
    );",
    "CREATE UNIQUE INDEX IF NOT EXISTS sshTargetsAliasIdx ON sshTargets(alias COLLATE NOCASE);",
];

#[cfg(test)]
mod tests {
    use super::*;

    async fn store() -> (tempfile::TempDir, RuntimeStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        (dir, store)
    }

    fn project(id: &str) -> Project {
        let now = Utc::now();
        Project {
            id: id.to_string(),
            name: id.to_string(),
            repo_path: format!("/tmp/{id}"),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        }
    }

    fn workspace(id: &str, project_id: &str) -> Workspace {
        let now = Utc::now();
        Workspace {
            id: id.to_string(),
            instance_id: format!("inst-{id}"),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: project_id.to_string(),
            name: id.to_string(),
            branch: Some("main".to_string()),
            path: format!("/tmp/{project_id}/{id}"),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            child_count: 0,
        }
    }

    fn ssh_target(id: &str) -> SshTarget {
        let now = Utc::now();
        SshTarget {
            id: id.to_string(),
            alias: id.to_string(),
            host: format!("{id}.example.test"),
            port: 22,
            username: "alera".to_string(),
            platform: None,
            arch: None,
            auth_kind: SshAuthKind::Agent,
            created_at: now,
            updated_at: now,
            last_status: None,
            install_dir: None,
            runtime_version: None,
            runtime_platform: None,
            runtime_arch: None,
            bootstrap_status: SshBootstrapStatus::NotInstalled,
            last_bootstrap_at: None,
            last_checked_at: None,
            last_error: None,
        }
    }

    #[tokio::test]
    async fn workspace_relations_prevent_cycles() {
        let (_dir, store) = store().await;
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("a", "p")).await.unwrap();
        store.upsert_workspace(workspace("b", "p")).await.unwrap();
        store.link_workspaces("a", "b").await.unwrap();
        let error = store.link_workspaces("b", "a").await.unwrap_err();
        assert!(error.to_string().contains("cycle"));
    }

    #[tokio::test]
    async fn cascade_preview_combines_descendants_and_tags() {
        let (_dir, store) = store().await;
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("a", "p")).await.unwrap();
        store.upsert_workspace(workspace("b", "p")).await.unwrap();
        store.upsert_workspace(workspace("c", "p")).await.unwrap();
        store.link_workspaces("a", "b").await.unwrap();
        let now = Utc::now();
        store
            .upsert_tag(WorkspaceTag {
                id: "tag".to_string(),
                name: "Review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        store.assign_tag("c", "tag").await.unwrap();
        let preview = store
            .cascade_preview(&["a".to_string()], &["tag".to_string()], true, true)
            .await
            .unwrap();
        assert_eq!(preview.workspace_ids, vec!["a", "b", "c"]);
    }

    #[tokio::test]
    async fn upsert_tag_reuses_existing_row_for_duplicate_name() {
        let (_dir, store) = store().await;
        let now = Utc::now();
        let original = store
            .upsert_tag(WorkspaceTag {
                id: "tag-1".to_string(),
                name: "Review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        let duplicate = store
            .upsert_tag(WorkspaceTag {
                id: "tag-2".to_string(),
                name: "review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();

        assert_eq!(duplicate.id, original.id);
        assert_eq!(duplicate.name, "Review");
        let tags = store.list_tags().await.unwrap();
        assert_eq!(tags.len(), 1);
    }

    #[tokio::test]
    async fn workspaces_include_tag_ids_and_names() {
        let (_dir, store) = store().await;
        store.upsert_project(project("p")).await.unwrap();
        store.upsert_workspace(workspace("w", "p")).await.unwrap();
        let now = Utc::now();
        store
            .upsert_tag(WorkspaceTag {
                id: "tag-review".to_string(),
                name: "Review".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        store
            .upsert_tag(WorkspaceTag {
                id: "tag-mobile".to_string(),
                name: "Mobile".to_string(),
                color: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        store.assign_tag("w", "tag-review").await.unwrap();
        store.assign_tag("w", "tag-mobile").await.unwrap();

        let workspaces = store.list_workspaces("p").await.unwrap();

        assert_eq!(workspaces[0].tag_ids, vec!["tag-mobile", "tag-review"]);
        assert_eq!(workspaces[0].tag_names, vec!["Mobile", "Review"]);
    }

    #[tokio::test]
    async fn metadata_round_trips_values() {
        let (_dir, store) = store().await;
        assert_eq!(store.get_metadata("migration").await.unwrap(), None);

        store.set_metadata("migration", "done").await.unwrap();
        assert_eq!(
            store.get_metadata("migration").await.unwrap(),
            Some("done".to_string())
        );
    }

    #[tokio::test]
    async fn ssh_target_upsert_preserves_runtime_state_and_updates_install_dir() {
        let (_dir, store) = store().await;
        store.upsert_ssh_target(ssh_target("remote")).await.unwrap();
        let installed = store
            .update_ssh_target_bootstrap_state(
                "remote",
                SshTargetBootstrapStateUpdate {
                    status: SshBootstrapStatus::Installed,
                    install_dir: Some("/home/alera/.alera/runtime"),
                    runtime_version: Some("1.2.3"),
                    runtime_platform: Some("linux"),
                    runtime_arch: Some("x64"),
                    last_error: None,
                },
            )
            .await
            .unwrap();
        assert_eq!(installed.bootstrap_status, SshBootstrapStatus::Installed);

        let mut updated = ssh_target("remote");
        updated.host = "renamed.example.test".to_string();
        let cleared = store.upsert_ssh_target(updated).await.unwrap();

        assert_eq!(cleared.host, "renamed.example.test");
        assert_eq!(cleared.bootstrap_status, SshBootstrapStatus::Installed);
        assert_eq!(cleared.runtime_version.as_deref(), Some("1.2.3"));
        assert_eq!(cleared.install_dir, None);

        let mut updated = cleared;
        updated.install_dir = Some("/custom/alera/runtime".to_string());
        let updated = store.upsert_ssh_target(updated).await.unwrap();

        assert_eq!(updated.host, "renamed.example.test");
        assert_eq!(updated.bootstrap_status, SshBootstrapStatus::Installed);
        assert_eq!(updated.runtime_version.as_deref(), Some("1.2.3"));
        assert_eq!(
            updated.install_dir.as_deref(),
            Some("/custom/alera/runtime")
        );
    }
}
