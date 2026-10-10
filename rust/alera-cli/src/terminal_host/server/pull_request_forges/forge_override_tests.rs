use alera_core::runtime::{Project, ProjectConfig, ProjectKind, RuntimeStore};
use chrono::Utc;

use super::project_forge_override;
use super::ForgeKind;

async fn project_with_repo_file(contents: &str) -> (tempfile::TempDir, RuntimeStore) {
    let directory = tempfile::tempdir().unwrap();
    let repo = directory.path().join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    std::fs::write(repo.join("alera.toml"), contents).unwrap();
    let store = RuntimeStore::open(&directory.path().join("runtime"))
        .await
        .unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "p".to_string(),
            name: "p".to_string(),
            repo_path: repo.display().to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    (directory, store)
}

#[tokio::test]
async fn a_repository_file_forces_the_forge_without_a_settings_override() {
    let (_directory, store) = project_with_repo_file("git_hosting_provider = \"gitlab\"").await;
    assert_eq!(
        project_forge_override(&store, "p").await,
        Some(ForgeKind::GitLab)
    );
}

#[tokio::test]
async fn a_settings_override_wins_over_the_repository_file() {
    let (_directory, store) = project_with_repo_file("git_hosting_provider = \"gitlab\"").await;
    let config = ProjectConfig {
        git_hosting_provider: Some("azureDevops".to_string()),
        ..ProjectConfig::default()
    };
    store
        .upsert_project_config("p", config, Utc::now())
        .await
        .unwrap();
    assert_eq!(
        project_forge_override(&store, "p").await,
        Some(ForgeKind::AzureDevOps)
    );
}
