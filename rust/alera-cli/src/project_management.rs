use std::path::{Path, PathBuf};

use alera_core::{
    git as core_git,
    runtime::{
        Project, ProjectConfig, ProjectKind, RuntimeStore, Workspace, WorkspaceKind,
        WorkspaceStatus, LOCAL_HOST_ID,
    },
};
use anyhow::{anyhow, bail, Context, Result};
use chrono::Utc;
use serde::Serialize;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectRegistration {
    pub project: Project,
    pub main_workspace: Workspace,
    pub created: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HostDirectoryRoot {
    pub name: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HostDirectoryEntry {
    pub name: String,
    pub path: String,
    pub is_symlink: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HostDirectoryListing {
    pub path: String,
    pub parent_path: Option<String>,
    pub entries: Vec<HostDirectoryEntry>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EffectiveProjectConfigPayload {
    pub config: ProjectConfig,
    pub origin: &'static str,
    pub error: Option<String>,
}

pub async fn register_project(
    store: &RuntimeStore,
    raw_path: &str,
    requested_name: Option<&str>,
) -> Result<ProjectRegistration> {
    let path = validate_existing_directory(raw_path)?;
    let canonical = canonical_string(&path)?;
    for project in store.list_projects().await? {
        if paths_equal(&project.repo_path, &canonical) {
            let main_workspace = ensure_main_workspace(store, &project).await?;
            return Ok(ProjectRegistration {
                project,
                main_workspace,
                created: false,
            });
        }
    }

    let branch = core_git::current_branch(&canonical).ok();
    let kind = if branch.is_some() || Path::new(&canonical).join(".git").exists() {
        ProjectKind::GitRepository
    } else {
        ProjectKind::Folder
    };
    let name = normalized_project_name(requested_name, &path)?;
    let now = Utc::now();
    let project = Project {
        id: Uuid::new_v4().to_string(),
        name: name.clone(),
        repo_path: canonical.clone(),
        created_at: now,
        updated_at: now,
        kind,
    };
    let main_workspace = Workspace {
        id: Uuid::new_v4().to_string(),
        instance_id: Uuid::new_v4().to_string(),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: project.id.clone(),
        name,
        branch,
        path: canonical,
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Main,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        child_count: 0,
    };
    store.upsert_project(project.clone()).await?;
    if let Err(error) = store.upsert_workspace(main_workspace.clone()).await {
        let _ = store.remove_project(&project.id).await;
        return Err(error);
    }
    Ok(ProjectRegistration {
        project,
        main_workspace,
        created: true,
    })
}

pub async fn rename_project(store: &RuntimeStore, id: &str, name: &str) -> Result<Project> {
    let name = name.trim();
    if name.is_empty() {
        bail!("Project name cannot be empty.");
    }
    let mut project = store
        .find_project(id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {id}"))?;
    project.name = name.to_string();
    project.updated_at = Utc::now();
    store.upsert_project(project).await
}

pub fn host_directory_roots() -> Vec<HostDirectoryRoot> {
    let mut roots = Vec::new();
    if let Some(home) = dirs::home_dir() {
        roots.push(HostDirectoryRoot {
            name: "Home".to_string(),
            path: home.to_string_lossy().to_string(),
        });
    }
    #[cfg(windows)]
    {
        for letter in b'A'..=b'Z' {
            let path = format!("{}:\\", letter as char);
            if Path::new(&path).is_dir() {
                roots.push(HostDirectoryRoot {
                    name: format!("{}:", letter as char),
                    path,
                });
            }
        }
    }
    #[cfg(not(windows))]
    roots.push(HostDirectoryRoot {
        name: "File System".to_string(),
        path: "/".to_string(),
    });
    roots.dedup_by(|left, right| paths_equal(&left.path, &right.path));
    roots
}

pub fn list_host_directory(raw_path: &str) -> Result<HostDirectoryListing> {
    let path = validate_existing_directory(raw_path)?;
    let canonical = std::fs::canonicalize(&path)
        .with_context(|| format!("Could not open directory: {}", path.display()))?;
    let mut entries = Vec::new();
    for item in std::fs::read_dir(&canonical)
        .with_context(|| format!("Could not read directory: {}", canonical.display()))?
    {
        let item = item?;
        let file_type = item.file_type()?;
        if !file_type.is_dir() && !file_type.is_symlink() {
            continue;
        }
        let item_path = item.path();
        if file_type.is_symlink() && !item_path.is_dir() {
            continue;
        }
        entries.push(HostDirectoryEntry {
            name: item.file_name().to_string_lossy().to_string(),
            path: item_path.to_string_lossy().to_string(),
            is_symlink: file_type.is_symlink(),
        });
    }
    entries.sort_by_key(|entry| entry.name.to_lowercase());
    Ok(HostDirectoryListing {
        path: canonical.to_string_lossy().to_string(),
        parent_path: canonical
            .parent()
            .filter(|parent| *parent != canonical)
            .map(|parent| parent.to_string_lossy().to_string()),
        entries,
    })
}

pub async fn effective_project_config(
    store: &RuntimeStore,
    project_id: &str,
) -> Result<EffectiveProjectConfigPayload> {
    let project = store
        .find_project(project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {project_id}"))?;
    if let Some(config) = store.find_project_config(project_id).await? {
        return Ok(EffectiveProjectConfigPayload {
            config,
            origin: "uiOverride",
            error: None,
        });
    }
    let config_path = Path::new(&project.repo_path).join("alera.toml");
    if !config_path.exists() {
        return Ok(EffectiveProjectConfigPayload {
            config: ProjectConfig::default(),
            origin: "none",
            error: None,
        });
    }
    let parsed = std::fs::read_to_string(&config_path)
        .with_context(|| format!("Could not load {}", config_path.display()))
        .and_then(|contents| crate::project_config_toml::parse_project_config_toml(&contents));
    match parsed {
        Ok(config) => Ok(EffectiveProjectConfigPayload {
            config,
            origin: "repoFile",
            error: None,
        }),
        Err(error) => Ok(EffectiveProjectConfigPayload {
            config: ProjectConfig::default(),
            origin: "repoFile",
            error: Some(error.to_string()),
        }),
    }
}

pub fn validate_clone_destination(parent_path: &str, directory_name: &str) -> Result<PathBuf> {
    let parent = validate_existing_directory(parent_path)?;
    let name = directory_name.trim();
    if name.is_empty() || name == "." || name == ".." || Path::new(name).components().count() != 1 {
        bail!("Clone directory name must be a single path segment.");
    }
    let parent = std::fs::canonicalize(parent)?;
    let destination = parent.join(name);
    if destination.exists() {
        bail!(
            "Clone destination already exists: {}",
            destination.display()
        );
    }
    Ok(destination)
}

fn validate_existing_directory(raw_path: &str) -> Result<PathBuf> {
    let trimmed = raw_path.trim();
    if trimmed.is_empty() {
        bail!("Project path cannot be empty.");
    }
    let path = PathBuf::from(trimmed);
    let metadata = std::fs::metadata(&path)
        .with_context(|| format!("Directory does not exist or is not accessible: {trimmed}"))?;
    if !metadata.is_dir() {
        bail!("Path is not a directory: {trimmed}");
    }
    Ok(path)
}

async fn ensure_main_workspace(store: &RuntimeStore, project: &Project) -> Result<Workspace> {
    if let Some(workspace) = store
        .list_workspaces(&project.id)
        .await?
        .into_iter()
        .find(|workspace| workspace.kind == WorkspaceKind::Main)
    {
        return Ok(workspace);
    }
    let now = Utc::now();
    store
        .upsert_workspace(Workspace {
            id: Uuid::new_v4().to_string(),
            instance_id: Uuid::new_v4().to_string(),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: project.id.clone(),
            name: project.name.clone(),
            branch: (project.kind == ProjectKind::GitRepository)
                .then(|| core_git::current_branch(&project.repo_path).ok())
                .flatten(),
            path: project.repo_path.clone(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            child_count: 0,
        })
        .await
}

fn normalized_project_name(requested_name: Option<&str>, path: &Path) -> Result<String> {
    let requested = requested_name.unwrap_or_default().trim();
    if !requested.is_empty() {
        return Ok(requested.to_string());
    }
    path.file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.trim().is_empty())
        .map(ToString::to_string)
        .ok_or_else(|| anyhow!("Project name cannot be derived from the selected path."))
}

fn canonical_string(path: &Path) -> Result<String> {
    Ok(std::fs::canonicalize(path)?.to_string_lossy().to_string())
}

fn paths_equal(left: &str, right: &str) -> bool {
    #[cfg(windows)]
    {
        left.eq_ignore_ascii_case(right)
    }
    #[cfg(not(windows))]
    {
        left == right
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clone_destination_rejects_nested_names() {
        let dir = tempfile::tempdir().unwrap();
        assert!(validate_clone_destination(dir.path().to_str().unwrap(), "nested/repo").is_err());
        assert!(validate_clone_destination(dir.path().to_str().unwrap(), "repo").is_ok());
    }

    #[test]
    fn clone_cleanup_never_removes_a_competing_destination() {
        let parent = tempfile::tempdir().unwrap();
        let destination = validate_clone_destination(parent.path().to_str().unwrap(), "repo").unwrap();
        let staging = crate::project_clone_staging::ProjectCloneStaging::create(
            parent.path().to_str().unwrap(), &uuid::Uuid::new_v4().to_string(),
        ).unwrap();
        std::fs::create_dir(staging.checkout_path()).unwrap();
        std::fs::create_dir(&destination).unwrap();
        let sentinel = destination.join("other-job.txt");
        std::fs::write(&sentinel, "keep the competing clone").unwrap();
        assert!(staging.publish(&destination).is_err());
        staging.cleanup().unwrap();
        assert!(sentinel.exists(), "failed clone cleanup must not delete a competing job's directory");
    }

    #[tokio::test]
    async fn registering_a_folder_creates_one_main_workspace_and_deduplicates() {
        let runtime = tempfile::tempdir().unwrap();
        let project_dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(runtime.path()).await.unwrap();

        let first = register_project(&store, project_dir.path().to_str().unwrap(), Some("Sample"))
            .await
            .unwrap();
        let second = register_project(
            &store,
            project_dir.path().to_str().unwrap(),
            Some("Ignored"),
        )
        .await
        .unwrap();

        assert!(first.created);
        assert!(!second.created);
        assert_eq!(first.project.id, second.project.id);
        assert_eq!(first.main_workspace.id, second.main_workspace.id);
        assert_eq!(first.project.kind, ProjectKind::Folder);
        assert_eq!(store.list_projects().await.unwrap().len(), 1);
        assert_eq!(
            store
                .list_workspaces(&first.project.id)
                .await
                .unwrap()
                .len(),
            1
        );
    }

    #[tokio::test]
    async fn effective_config_prefers_runtime_override() {
        let runtime = tempfile::tempdir().unwrap();
        let project_dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(runtime.path()).await.unwrap();
        let registered =
            register_project(&store, project_dir.path().to_str().unwrap(), Some("Sample"))
                .await
                .unwrap();
        let config = ProjectConfig {
            git_hosting_provider: Some("github".to_string()),
            ..ProjectConfig::default()
        };
        store
            .upsert_project_config(&registered.project.id, config.clone(), Utc::now())
            .await
            .unwrap();

        let effective = effective_project_config(&store, &registered.project.id)
            .await
            .unwrap();
        assert_eq!(effective.origin, "uiOverride");
        assert_eq!(effective.config, config);
        assert!(effective.error.is_none());
    }
}
