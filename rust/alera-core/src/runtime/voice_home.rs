use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use chrono::Utc;
use uuid::Uuid;

use super::{
    prepare_private_runtime_directory, Project, ProjectKind, RuntimeStore, Workspace,
    WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};

/// Stable task identity for the global voice home agent.
pub const VOICE_HOME_PROJECT_ID: &str = "alera-home";
pub const VOICE_HOME_WORKSPACE_ID: &str = "alera-home";
pub const VOICE_HOME_PROJECT_NAME: &str = "Alera";
pub const VOICE_HOME_WORKSPACE_NAME: &str = "Voice";
pub const VOICE_HOME_CONTRACT_VERSION: u32 = 1;
pub const VOICE_HOME_AGENTS_FILE_NAME: &str = "AGENTS.md";
pub const VOICE_HOME_CLAUDE_FILE_NAME: &str = "CLAUDE.md";
pub const VOICE_HOME_GEMINI_FILE_NAME: &str = "GEMINI.md";

const HOME_DIR_NAME: &str = "home";

pub fn is_voice_home_project_id(project_id: &str) -> bool {
    project_id == VOICE_HOME_PROJECT_ID
}

pub fn is_voice_home_workspace_id(workspace_id: &str) -> bool {
    workspace_id == VOICE_HOME_WORKSPACE_ID
}

pub fn voice_home_dir(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join(HOME_DIR_NAME)
}

pub fn voice_home_agents_path(runtime_dir: &Path) -> PathBuf {
    voice_home_dir(runtime_dir).join(VOICE_HOME_AGENTS_FILE_NAME)
}

pub fn voice_home_contract_marker() -> String {
    format!("<!-- voice-home-contract: {VOICE_HOME_CONTRACT_VERSION} -->")
}

pub fn voice_home_agents_markdown() -> String {
    format!(
        "{}\n\n# Alera voice home\n\nYou are Alera's global voice home agent. This folder is not a product repository.\n\n- Speak to the human only with `alera voice speak --text \"...\"`. Keep those sentences short.\n- Do not patch product code from this folder. Delegate with `alera orchestration delegate --workspace <id> --profile <name>`.\n- Inspect work with `alera workspace list --json`, `alera orchestration status`, and `alera terminal read`.\n- If a turn says the human interrupted you, they did not hear the previous spoken message. Drop that oral plan.\n- Never invent agent profiles. Use only the catalog from `alera orchestration agent-profiles --json`.\n",
        voice_home_contract_marker()
    )
}

pub fn voice_home_pointer_markdown(file_name: &str) -> String {
    format!("Read @{file_name}\n")
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceHomeEnsureResult {
    pub project: Project,
    pub workspace: Workspace,
    pub home_dir: PathBuf,
    pub created: bool,
    pub agents_rewritten: bool,
}

impl RuntimeStore {
    pub async fn ensure_voice_home(&self, runtime_dir: &Path) -> Result<VoiceHomeEnsureResult> {
        let home_dir = voice_home_dir(runtime_dir);
        prepare_private_runtime_directory(&home_dir)
            .with_context(|| format!("Could not create {}", home_dir.display()))?;
        let home_path = canonical_or_display(&home_dir);
        let now = Utc::now();
        let mut created = false;
        let project = if let Some(existing) = self.find_project(VOICE_HOME_PROJECT_ID).await? {
            if existing.kind != ProjectKind::Folder || existing.repo_path != home_path {
                let mut updated = existing;
                updated.name = VOICE_HOME_PROJECT_NAME.to_string();
                updated.kind = ProjectKind::Folder;
                updated.repo_path = home_path.clone();
                updated.updated_at = now;
                self.upsert_project(updated).await?
            } else {
                existing
            }
        } else {
            created = true;
            self.upsert_project(Project {
                id: VOICE_HOME_PROJECT_ID.to_string(),
                name: VOICE_HOME_PROJECT_NAME.to_string(),
                repo_path: home_path.clone(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::Folder,
            })
            .await?
        };
        self.register_project_checkout(&project.id, LOCAL_HOST_ID, &home_path)
            .await?;
        let workspace = if let Some(existing) = self.find_workspace(VOICE_HOME_WORKSPACE_ID).await?
        {
            if existing.project_id != project.id
                || existing.path != home_path
                || existing.kind != WorkspaceKind::Main
                || existing.status != WorkspaceStatus::Active
            {
                let mut updated = existing;
                updated.project_id = project.id.clone();
                updated.host_id = LOCAL_HOST_ID.to_string();
                updated.name = VOICE_HOME_WORKSPACE_NAME.to_string();
                updated.path = home_path;
                updated.kind = WorkspaceKind::Main;
                updated.status = WorkspaceStatus::Active;
                updated.branch = None;
                updated.source_branch = None;
                updated.parent_workspace_id = None;
                updated.updated_at = now;
                if updated.instance_id.trim().is_empty() {
                    updated.instance_id = Uuid::new_v4().to_string();
                }
                self.upsert_workspace(updated).await?
            } else {
                existing
            }
        } else {
            created = true;
            self.insert_workspace(Workspace {
                id: VOICE_HOME_WORKSPACE_ID.to_string(),
                instance_id: Uuid::new_v4().to_string(),
                host_id: LOCAL_HOST_ID.to_string(),
                project_id: project.id.clone(),
                name: VOICE_HOME_WORKSPACE_NAME.to_string(),
                branch: None,
                path: home_path,
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Main,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: false,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                section_id: None,
                parent_workspace_id: None,
                child_count: 0,
            })
            .await?
        };
        let agents_rewritten = write_managed_home_files(&home_dir)?;
        Ok(VoiceHomeEnsureResult {
            project,
            workspace,
            home_dir,
            created,
            agents_rewritten,
        })
    }
}

fn write_managed_home_files(home_dir: &Path) -> Result<bool> {
    let agents_path = home_dir.join(VOICE_HOME_AGENTS_FILE_NAME);
    let desired = voice_home_agents_markdown();
    let rewritten = match std::fs::read_to_string(&agents_path) {
        Ok(existing) if existing == desired => false,
        _ => {
            std::fs::write(&agents_path, desired.as_bytes())
                .with_context(|| format!("Could not write {}", agents_path.display()))?;
            true
        }
    };
    write_if_changed(
        &home_dir.join(VOICE_HOME_CLAUDE_FILE_NAME),
        &voice_home_pointer_markdown(VOICE_HOME_AGENTS_FILE_NAME),
    )?;
    write_if_changed(
        &home_dir.join(VOICE_HOME_GEMINI_FILE_NAME),
        &voice_home_pointer_markdown(VOICE_HOME_AGENTS_FILE_NAME),
    )?;
    Ok(rewritten)
}

fn write_if_changed(path: &Path, contents: &str) -> Result<()> {
    match std::fs::read_to_string(path) {
        Ok(existing) if existing == contents => Ok(()),
        _ => {
            std::fs::write(path, contents.as_bytes())
                .with_context(|| format!("Could not write {}", path.display()))?;
            Ok(())
        }
    }
}

fn canonical_or_display(path: &Path) -> String {
    std::fs::canonicalize(path)
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn ensure_is_idempotent_and_rewrites_stale_agents() {
        let directory = TempDir::new().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        let first = store.ensure_voice_home(directory.path()).await.unwrap();
        assert!(first.created);
        assert!(first.agents_rewritten);
        assert_eq!(first.project.id, VOICE_HOME_PROJECT_ID);
        assert_eq!(first.workspace.id, VOICE_HOME_WORKSPACE_ID);
        assert_eq!(first.project.kind, ProjectKind::Folder);
        let agents = std::fs::read_to_string(voice_home_agents_path(directory.path())).unwrap();
        assert!(agents.contains(&voice_home_contract_marker()));
        std::fs::write(voice_home_agents_path(directory.path()), "stale").unwrap();
        let second = store.ensure_voice_home(directory.path()).await.unwrap();
        assert!(!second.created);
        assert!(second.agents_rewritten);
        assert_eq!(second.workspace.id, first.workspace.id);
        let restored = std::fs::read_to_string(voice_home_agents_path(directory.path())).unwrap();
        assert_eq!(restored, voice_home_agents_markdown());
        let claude =
            std::fs::read_to_string(directory.path().join("home").join("CLAUDE.md")).unwrap();
        assert_eq!(claude, "Read @AGENTS.md\n");
    }

    #[test]
    fn identity_helpers_match_stable_ids() {
        assert!(is_voice_home_project_id(VOICE_HOME_PROJECT_ID));
        assert!(is_voice_home_workspace_id(VOICE_HOME_WORKSPACE_ID));
        assert!(!is_voice_home_project_id("other"));
    }
}
