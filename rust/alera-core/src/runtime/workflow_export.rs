use std::io::Write;
use std::path::Path;
use std::sync::Mutex;

use anyhow::{bail, Context, Result};
use cap_fs_ext::DirExt;
use cap_std::{ambient_authority, fs::Dir, fs::OpenOptions};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::workflow_catalog::workflow_blocking;
use super::workflow_project_files::{optional_directory, read_document};
use super::{ProjectKind, RuntimeStore, WorkflowRecipeV1, WorkspaceStatus, LOCAL_HOST_ID};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowExportRequest {
    pub workspace_id: String,
    pub filename: String,
    pub document: String,
    pub expected_digest: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowExportPreview {
    pub workspace_id: String,
    pub path: String,
    pub before: Option<String>,
    pub after: String,
    pub expected_digest: String,
    pub retained_path: Option<String>,
}

impl RuntimeStore {
    pub async fn export_workflow_recipe(
        &self,
        request: WorkflowExportRequest,
        apply: bool,
    ) -> Result<WorkflowExportPreview> {
        let store = self.clone();
        // A caller timeout must not release workspace identity protection while
        // the blocking filesystem write is still running.
        tokio::spawn(async move { store.export_workflow_recipe_inner(request, apply).await })
            .await?
    }

    async fn export_workflow_recipe_inner(
        &self,
        request: WorkflowExportRequest,
        apply: bool,
    ) -> Result<WorkflowExportPreview> {
        let workspace = self
            .find_workspace(&request.workspace_id)
            .await?
            .context("workflow export workspace not found")?;
        let project = self
            .find_project(&workspace.project_id)
            .await?
            .context("workflow export project not found")?;
        if workspace.status != WorkspaceStatus::Active
            || workspace.host_id != LOCAL_HOST_ID
            || project.kind != ProjectKind::GitRepository
        {
            bail!("workflow export requires an active local Git workspace");
        }
        let mut transaction = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let current: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workspaces w JOIN projects p ON p.id = w.projectId
             WHERE w.id = ? AND w.instanceId = ? AND w.path = ? AND w.projectId = ?
             AND w.status = 'active' AND w.hostId = 'local' AND p.kind = 'gitRepository')",
        )
        .bind(&workspace.id)
        .bind(&workspace.instance_id)
        .bind(&workspace.path)
        .bind(&workspace.project_id)
        .fetch_one(&mut *transaction)
        .await?;
        if !current {
            bail!("workflow export workspace changed; refresh the catalog");
        }
        let result = workflow_blocking(move || {
            static WRITES: Mutex<()> = Mutex::new(());
            let _guard = WRITES
                .lock()
                .map_err(|_| anyhow::anyhow!("workflow export lock failed"))?;
            export_at(
                Path::new(&workspace.path),
                &workspace.instance_id,
                request,
                apply,
            )
        })
        .await;
        transaction.commit().await?;
        result
    }
}

pub(super) fn export_at(
    workspace: &Path,
    instance_id: &str,
    request: WorkflowExportRequest,
    apply: bool,
) -> Result<WorkflowExportPreview> {
    let name = &request.filename;
    super::orchestration_role_contract::artifact_path(name)?;
    // A deliberately narrow filename grammar works identically on all desktop hosts.
    if name.len() > 128
        || !name.ends_with(".yaml")
        || name.starts_with('.')
        || !name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
    {
        bail!("use a single .yaml filename with letters, numbers, hyphens or underscores");
    }
    let after = WorkflowRecipeV1::from_yaml(&request.document)?.portable_document()?;
    let root = Dir::open_ambient_dir(workspace, ambient_authority())?;
    let alera = optional_directory(&root, ".alera")?;
    let directory = alera
        .as_ref()
        .map(|dir| optional_directory(dir, "workflows"))
        .transpose()?
        .flatten();
    let before = directory
        .as_ref()
        .map(|dir| read_optional(dir, name))
        .transpose()?
        .flatten();
    let digest = format!(
        "{:x}",
        Sha256::digest(serde_json::to_vec(&(
            &request.workspace_id,
            instance_id,
            workspace,
            name,
            &before,
            &after,
        ))?)
    );
    let mut retained_path = None;
    if apply {
        if request.expected_digest.as_deref() != Some(&digest) {
            bail!("export destination or document changed; review a new preview");
        }
        if before.as_deref() != Some(after.as_str()) {
            let alera = ensure_directory(&root, ".alera")?;
            let directory = ensure_directory(&alera, "workflows")?;
            let existing =
                super::workflow_project_files::read_project_workflow_documents(workspace)?;
            if before.is_none()
                && existing.len() >= super::workflow_project_files::CATALOG_MAX_ENTRIES
            {
                bail!("project workflow catalog is full");
            }
            let other_bytes: usize = existing
                .iter()
                .filter(|entry| entry.path != format!(".alera/workflows/{name}"))
                .filter_map(|entry| entry.source.as_ref().ok())
                .map(String::len)
                .sum();
            if other_bytes + after.len() > super::workflow_project_files::CATALOG_MAX_BYTES {
                bail!("export would exceed the project workflow catalog byte limit");
            }
            retained_path = replace_document(&directory, name, before.as_deref(), &after)?
                .map(|name| format!(".alera/workflows/{name}"));
        }
    }
    Ok(WorkflowExportPreview {
        workspace_id: request.workspace_id,
        path: format!(".alera/workflows/{name}"),
        before,
        after,
        expected_digest: digest,
        retained_path,
    })
}

fn read_optional(directory: &Dir, name: &str) -> Result<Option<String>> {
    match directory.symlink_metadata(name) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
        Ok(_) => read_document(directory, name).map(Some),
    }
}

fn ensure_directory(parent: &Dir, name: &str) -> Result<Dir> {
    if let Some(directory) = optional_directory(parent, name)? {
        return Ok(directory);
    }
    match parent.create_dir(name) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(error) => return Err(error.into()),
    }
    Ok(parent.open_dir_nofollow(name)?)
}

fn replace_document(
    directory: &Dir,
    name: &str,
    before: Option<&str>,
    after: &str,
) -> Result<Option<String>> {
    let temporary = format!(".export-{}.tmp", uuid::Uuid::new_v4());
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    let mut file = directory.open_with(&temporary, &options)?;
    let result = (|| {
        file.write_all(after.as_bytes())?;
        file.sync_all()?;
        drop(file);
        if read_optional(directory, name)?.as_deref() != before {
            bail!("export destination changed; review a new preview");
        }
        if before.is_none() {
            // A hard link publishes a complete file without replacing a concurrent create.
            directory.hard_link(&temporary, directory, name)?;
            directory.remove_file(&temporary)?;
            Ok(None)
        } else {
            // Retain the displaced inode until its bytes have been checked. An
            // external writer that races review must never lose its document.
            let retained = format!(".export-retained-{}.bak", uuid::Uuid::new_v4());
            directory.rename(name, directory, &retained)?;
            if read_document(directory, &retained).ok().as_deref() != before {
                let _ = directory.hard_link(&retained, directory, name);
                bail!("export destination changed; original retained as {retained}; review again");
            }
            if let Err(error) = directory.hard_link(&temporary, directory, name) {
                let _ = directory.hard_link(&retained, directory, name);
                bail!("export destination changed; original retained as {retained}: {error}");
            }
            directory.remove_file(&temporary)?;
            // Keep the old file for external editors holding its inode and recovery.
            Ok(Some(retained))
        }
    })();
    if result.is_err() {
        let _ = directory.remove_file(&temporary);
    }
    result
}
