use anyhow::{bail, Result};
use sqlx::{Row, Sqlite, Transaction};
use uuid::Uuid;

use super::{CheckoutKind, RepositoryCheckout, RuntimeStore, Workspace, WorkspaceKind};

const CHECKOUT_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS repositoryCheckouts (
        id TEXT PRIMARY KEY, projectId TEXT NOT NULL, hostId TEXT NOT NULL,
        path TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('project', 'linked')),
        repositoryPath TEXT,
        UNIQUE(projectId, hostId, path)
    )",
    "CREATE UNIQUE INDEX IF NOT EXISTS repositoryProjectCheckoutIdx
        ON repositoryCheckouts(projectId, hostId) WHERE kind = 'project'",
    "CREATE TABLE IF NOT EXISTS workspaceCheckoutBindings (
        workspaceId TEXT PRIMARY KEY, checkoutId TEXT NOT NULL
    )",
    "CREATE INDEX IF NOT EXISTS workspaceCheckoutBindingsCheckoutIdx
        ON workspaceCheckoutBindings(checkoutId)",
    "CREATE TRIGGER IF NOT EXISTS workspaceCheckoutBindingDelete
        AFTER DELETE ON workspaces BEGIN
        DELETE FROM workspaceCheckoutBindings WHERE workspaceId = OLD.id;
    END",
    "CREATE TRIGGER IF NOT EXISTS projectCheckoutDelete
        AFTER DELETE ON projects BEGIN
        DELETE FROM workspaceCheckoutBindings WHERE checkoutId IN
            (SELECT id FROM repositoryCheckouts WHERE projectId = OLD.id);
        DELETE FROM repositoryCheckouts WHERE projectId = OLD.id;
    END",
];

const PROJECT_CHECKOUT_BACKFILL: &str = "checkout.projectBackfillV1";

impl RuntimeStore {
    pub(super) async fn migrate_workspace_checkouts(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in CHECKOUT_SCHEMA {
            sqlx::query(*statement).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        let bound: std::collections::HashSet<String> =
            sqlx::query_scalar("SELECT workspaceId FROM workspaceCheckoutBindings")
                .fetch_all(self.pool())
                .await?
                .into_iter()
                .collect();
        let registered: std::collections::HashSet<String> = sqlx::query_scalar(
            "SELECT projectId FROM repositoryCheckouts WHERE hostId = 'local' AND kind = 'project'",
        )
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .collect();
        let backfill_projects = self
            .get_metadata(PROJECT_CHECKOUT_BACKFILL)
            .await?
            .is_none();
        let projects = self
            .list_projects()
            .await?
            .into_iter()
            .filter(|project| backfill_projects && !registered.contains(&project.id))
            .collect::<Vec<_>>();
        let workspaces = self
            .list_all_workspaces()
            .await?
            .into_iter()
            .filter(|workspace| !bound.contains(&workspace.id))
            .collect::<Vec<_>>();
        if projects.is_empty() && workspaces.is_empty() {
            if backfill_projects {
                self.set_metadata(PROJECT_CHECKOUT_BACKFILL, "1").await?;
            }
            return Ok(());
        }
        // Only new bindings need filesystem inspection. Never rewrite task records.
        let (projects, workspaces) = tokio::task::spawn_blocking(move || {
            let mut paths = std::collections::HashMap::<String, String>::new();
            let mut canonical = |path: &str| {
                paths
                    .entry(path.to_string())
                    .or_insert_with(|| canonical_local_path_or_original(path))
                    .clone()
            };
            let projects = projects
                .into_iter()
                .map(|mut project| {
                    project.repo_path = canonical(&project.repo_path);
                    project
                })
                .collect::<Vec<_>>();
            let workspaces = workspaces
                .into_iter()
                .map(|mut workspace| {
                    if workspace.host_id == super::LOCAL_HOST_ID {
                        workspace.path = canonical(&workspace.path);
                    }
                    workspace
                })
                .collect::<Vec<_>>();
            (projects, workspaces)
        })
        .await?;
        let mut tx = self.pool().begin().await?;
        for project in projects {
            sqlx::query("INSERT OR IGNORE INTO repositoryCheckouts (id, projectId, hostId, path, kind, repositoryPath) VALUES (?, ?, 'local', ?, 'project', ?)")
                .bind(format!("project:{}:local", project.id)).bind(&project.id).bind(&project.repo_path).bind(&project.repo_path).execute(&mut *tx).await?;
        }
        for workspace in workspaces {
            bind_workspace_checkout(&mut tx, &workspace, &workspace.path).await?;
        }
        // New owner projects can intentionally contain only linked worktrees.
        // Only legacy projects inherit repoPath as a project checkout on upgrade.
        if backfill_projects {
            sqlx::query("INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, '1', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
            .bind(PROJECT_CHECKOUT_BACKFILL).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn list_project_checkouts(
        &self,
        project_id: &str,
    ) -> Result<Vec<RepositoryCheckout>> {
        sqlx::query("SELECT * FROM repositoryCheckouts WHERE projectId = ? ORDER BY hostId, path")
            .bind(project_id)
            .fetch_all(self.pool())
            .await?
            .into_iter()
            .map(checkout_from_row)
            .collect()
    }

    pub(super) async fn checkout_path_for_write(&self, workspace: &Workspace) -> Result<String> {
        if let Some(stored) = self.find_workspace(&workspace.id).await? {
            if stored.project_id == workspace.project_id
                && stored.host_id == workspace.host_id
                && stored.path == workspace.path
                && stored.kind == workspace.kind
            {
                if let Some(checkout) = self.find_workspace_checkout(&workspace.id).await? {
                    return Ok(checkout.path);
                }
            }
        }
        let path = workspace.path.clone();
        if workspace.host_id != super::LOCAL_HOST_ID {
            return Ok(path);
        }
        Ok(tokio::task::spawn_blocking(move || canonical_local_path_or_original(&path)).await?)
    }

    pub async fn find_project_checkout(
        &self,
        project_id: &str,
        host_id: &str,
    ) -> Result<Option<RepositoryCheckout>> {
        let row = sqlx::query(
            "SELECT * FROM repositoryCheckouts WHERE projectId = ? AND hostId = ? AND kind = 'project'",
        )
        .bind(project_id)
        .bind(host_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(checkout_from_row).transpose()
    }

    pub async fn find_workspace_checkout(
        &self,
        workspace_id: &str,
    ) -> Result<Option<RepositoryCheckout>> {
        let row = sqlx::query(
            "SELECT c.* FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b
             ON c.id = b.checkoutId WHERE b.workspaceId = ?",
        )
        .bind(workspace_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(checkout_from_row).transpose()
    }

    /// Persist native ownership evidence without replacing an existing origin or task identity.
    pub async fn record_verified_linked_origin(
        &self,
        workspace: &Workspace,
        checkout: &RepositoryCheckout,
        origin: &str,
    ) -> Result<()> {
        if origin.trim().is_empty()
            || workspace.kind != WorkspaceKind::Linked
            || workspace.status != super::WorkspaceStatus::Active
            || checkout.kind != CheckoutKind::Linked
            || checkout.project_id != workspace.project_id
            || checkout.host_id != workspace.host_id
            || checkout
                .repository_path
                .as_deref()
                .is_some_and(|stored| stored != origin)
        {
            bail!("Verified origin does not match the linked checkout scope");
        }
        let result = sqlx::query("UPDATE repositoryCheckouts SET repositoryPath = ? WHERE id = ? AND projectId = ? AND hostId = ? AND path = ? AND kind = 'linked' AND (repositoryPath IS NULL OR repositoryPath = ?) AND EXISTS (SELECT 1 FROM workspaceCheckoutBindings b JOIN workspaces w ON w.id = b.workspaceId WHERE b.checkoutId = repositoryCheckouts.id AND w.id = ? AND w.instanceId = ? AND w.projectId = ? AND w.hostId = ? AND w.path = ? AND w.kind = 'linked' AND w.status = 'active')")
            .bind(origin).bind(&checkout.id).bind(&checkout.project_id).bind(&checkout.host_id).bind(&checkout.path).bind(origin)
            .bind(&workspace.id).bind(&workspace.instance_id).bind(&workspace.project_id).bind(&workspace.host_id).bind(&workspace.path)
            .execute(self.pool()).await?;
        if result.rows_affected() != 1 {
            bail!("The linked task or checkout changed during origin inspection; no ownership was replaced");
        }
        Ok(())
    }

    /// Adopt the first principal of an owner previously enrolled with linked tasks only.
    pub async fn register_owner_project_checkout(&self, project: super::Project) -> Result<()> {
        if project.id.trim().is_empty() || project.repo_path.trim().is_empty() {
            bail!("Project identity and checkout path are required");
        }
        let path = project.repo_path.clone();
        let path =
            tokio::task::spawn_blocking(move || canonical_local_path_or_original(&path)).await?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING")
            .bind(&project.id).bind(&project.name).bind(&path)
            .bind(super::store::format_timestamp(project.created_at)).bind(super::store::format_timestamp(project.updated_at))
            .bind(project.kind.as_str()).execute(&mut *tx).await?;
        let kind: String = sqlx::query_scalar("SELECT kind FROM projects WHERE id = ?")
            .bind(&project.id)
            .fetch_one(&mut *tx)
            .await?;
        if kind != project.kind.as_str() {
            bail!("Project identity already belongs to another project type");
        }
        let existing: Option<String> = sqlx::query_scalar("SELECT path FROM repositoryCheckouts WHERE projectId = ? AND hostId = 'local' AND kind = 'project'")
            .bind(&project.id).fetch_optional(&mut *tx).await?;
        if existing.as_ref().is_some_and(|existing| existing != &path) {
            bail!("The project already has a different checkout on this host");
        }
        sqlx::query("INSERT OR IGNORE INTO repositoryCheckouts (id, projectId, hostId, path, kind, repositoryPath) VALUES (?, ?, 'local', ?, 'project', ?)")
            .bind(Uuid::new_v4().to_string()).bind(&project.id).bind(&path).bind(&path).execute(&mut *tx).await?;
        let registered: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM repositoryCheckouts WHERE projectId = ? AND hostId = 'local' AND path = ? AND kind = 'project')")
            .bind(&project.id).bind(&path).fetch_one(&mut *tx).await?;
        if !registered {
            bail!("The path is already registered as a linked checkout");
        }
        sqlx::query("UPDATE projects SET repoPath = ? WHERE id = ?")
            .bind(&path)
            .bind(&project.id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    /// The host validates and canonicalizes paths on the owning machine first.
    pub async fn register_project_checkout(
        &self,
        project_id: &str,
        host_id: &str,
        path: &str,
    ) -> Result<RepositoryCheckout> {
        if project_id.trim().is_empty() || host_id.trim().is_empty() || path.trim().is_empty() {
            bail!("Project, host and checkout path are required");
        }
        let canonical_path = if host_id == super::LOCAL_HOST_ID {
            let path = path.to_string();
            Some(
                tokio::task::spawn_blocking(move || canonical_local_path_or_original(&path))
                    .await?,
            )
        } else {
            None
        };
        let path = canonical_path.as_deref().unwrap_or(path);
        let mut tx = self.pool().begin().await?;
        let exists: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projects WHERE id = ?")
            .bind(project_id)
            .fetch_one(&mut *tx)
            .await?;
        if exists == 0 {
            bail!("Project not found: {project_id}");
        }
        sqlx::query(
            "INSERT OR IGNORE INTO repositoryCheckouts
             (id, projectId, hostId, path, kind, repositoryPath) VALUES (?, ?, ?, ?, 'project', ?)",
        )
        .bind(Uuid::new_v4().to_string())
        .bind(project_id)
        .bind(host_id)
        .bind(path)
        .bind(path)
        .execute(&mut *tx)
        .await?;
        let row = sqlx::query(
            "SELECT * FROM repositoryCheckouts WHERE projectId = ? AND hostId = ? AND kind = 'project'",
        )
        .bind(project_id)
        .bind(host_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(row) = row else {
            bail!("The path is already registered as a linked checkout");
        };
        let checkout = checkout_from_row(row)?;
        if checkout.path != path {
            bail!("The project already has a different checkout on this host");
        }
        tx.commit().await?;
        Ok(checkout)
    }
}

pub(super) async fn bind_workspace_checkout(
    tx: &mut Transaction<'_, Sqlite>,
    workspace: &Workspace,
    checkout_path: &str,
) -> Result<()> {
    let kind = if workspace.kind == WorkspaceKind::Main {
        CheckoutKind::Project
    } else {
        CheckoutKind::Linked
    };
    sqlx::query(
        "INSERT OR IGNORE INTO repositoryCheckouts
         (id, projectId, hostId, path, kind) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(Uuid::new_v4().to_string())
    .bind(&workspace.project_id)
    .bind(&workspace.host_id)
    .bind(checkout_path)
    .bind(kind.as_str())
    .execute(&mut **tx)
    .await?;
    let row = sqlx::query(
        "SELECT * FROM repositoryCheckouts WHERE projectId = ? AND hostId = ? AND path = ?",
    )
    .bind(&workspace.project_id)
    .bind(&workspace.host_id)
    .bind(checkout_path)
    .fetch_optional(&mut **tx)
    .await?;
    let Some(row) = row else {
        bail!("The project already has a different checkout on this host");
    };
    let checkout = checkout_from_row(row)?;
    if checkout.kind != kind {
        bail!("Workspace storage kind does not match its registered checkout");
    }
    if kind == CheckoutKind::Linked {
        let other_owners: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM workspaceCheckoutBindings b JOIN workspaces w ON w.id = b.workspaceId
             WHERE b.checkoutId = ? AND b.workspaceId != ? AND w.status = 'active'",
        )
        .bind(&checkout.id)
        .bind(&workspace.id)
        .fetch_one(&mut **tx)
        .await?;
        if other_owners != 0 {
            bail!("A linked checkout can belong to only one workspace");
        }
    }
    sqlx::query(
        "INSERT INTO workspaceCheckoutBindings(workspaceId, checkoutId) VALUES (?, ?)
         ON CONFLICT(workspaceId) DO UPDATE SET checkoutId = excluded.checkoutId",
    )
    .bind(&workspace.id)
    .bind(&checkout.id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn canonical_local_path_or_original(path: &str) -> String {
    // Offline and missing checkouts retain their last known location and task records.
    std::fs::canonicalize(path)
        .ok()
        .and_then(|path| path.to_str().map(str::to_owned))
        .unwrap_or_else(|| path.to_string())
}

fn checkout_from_row(row: sqlx::sqlite::SqliteRow) -> Result<RepositoryCheckout> {
    let kind = match row.try_get::<String, _>("kind")?.as_str() {
        "project" => CheckoutKind::Project,
        "linked" => CheckoutKind::Linked,
        other => bail!("Unknown checkout storage kind: {other}"),
    };
    Ok(RepositoryCheckout {
        id: row.try_get("id")?,
        project_id: row.try_get("projectId")?,
        host_id: row.try_get("hostId")?,
        path: row.try_get("path")?,
        kind,
        repository_path: row.try_get("repositoryPath")?,
    })
}

#[cfg(test)]
#[path = "checkout_origin_store_tests.rs"]
mod origin_tests;
