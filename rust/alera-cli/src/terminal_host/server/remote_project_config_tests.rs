use std::sync::Mutex;

use alera_core::runtime::{Project, ProjectKind, WorkspaceKind, WorkspaceStatus};
use chrono::Utc;

use super::*;

const REMOTE_REPO: &str = "/home/dev/alera-projects/server-only";

struct FakeReader {
    outcome: HostResult<Option<String>>,
    reads: Mutex<Vec<(String, String, u64)>>,
}

impl FakeReader {
    fn answering(outcome: HostResult<Option<String>>) -> Self {
        Self {
            outcome,
            reads: Mutex::new(Vec::new()),
        }
    }

    fn read_workspace_ids(&self) -> Vec<String> {
        self.reads
            .lock()
            .unwrap()
            .iter()
            .map(|(workspace_id, _, _)| workspace_id.clone())
            .collect()
    }
}

impl RemoteProjectFileReader for FakeReader {
    async fn read_root_text_file(
        &self,
        workspace: &Workspace,
        file_name: &str,
        max_bytes: u64,
    ) -> HostResult<Option<String>> {
        self.reads
            .lock()
            .unwrap()
            .push((workspace.id.clone(), file_name.to_string(), max_bytes));
        match &self.outcome {
            Ok(contents) => Ok(contents.clone()),
            Err(error) => Err(HostError::state(error.wire_message())),
        }
    }
}

fn workspace(id: &str, host_id: &str, path: &str, kind: WorkspaceKind) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.into(),
        instance_id: format!("{id}-instance"),
        host_id: host_id.into(),
        project_id: "project-1".into(),
        name: id.into(),
        branch: None,
        path: path.into(),
        created_at: now,
        updated_at: now,
        kind,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

/// A remote-only project: its folder is the checkout of `ssh-a` and nothing
/// is registered on this device.
async fn remote_only_project() -> (tempfile::TempDir, RuntimeStore, Project) {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = Utc::now();
    let project = store
        .upsert_project(Project {
            id: "project-1".into(),
            name: "Server Only".into(),
            repo_path: REMOTE_REPO.into(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .register_project_checkout("project-1", "ssh-a", REMOTE_REPO)
        .await
        .unwrap();
    (directory, store, project)
}

#[test]
fn the_workspace_on_the_project_folder_is_preferred_over_an_earlier_worktree() {
    let worktree = workspace(
        "feature",
        "ssh-a",
        "/home/dev/.alera/worktrees/feature",
        WorkspaceKind::Linked,
    );
    let main = workspace("main", "ssh-a", REMOTE_REPO, WorkspaceKind::Main);
    let workspaces = vec![worktree.clone(), main];
    assert_eq!(
        config_workspace(REMOTE_REPO, &workspaces).map(|w| w.id.as_str()),
        Some("main")
    );
    assert_eq!(
        config_workspace(REMOTE_REPO, &[worktree]).map(|w| w.id.as_str()),
        Some("feature"),
        "without a workspace on the folder the first one stands in"
    );
    assert!(config_workspace(REMOTE_REPO, &[]).is_none());
}

#[test]
fn a_windows_checkout_matches_its_verbatim_spelling() {
    let main = workspace(
        "main",
        "ssh-win",
        r"\\?\C:\Users\dev\alera-projects\repo",
        WorkspaceKind::Main,
    );
    let other = workspace(
        "other",
        "ssh-win",
        r"C:\Users\dev\worktrees\x",
        WorkspaceKind::Linked,
    );
    let workspaces = vec![other, main];
    assert_eq!(
        config_workspace(r"C:\Users\dev\alera-projects\repo", &workspaces).map(|w| w.id.as_str()),
        Some("main")
    );
}

#[tokio::test]
async fn the_file_is_read_from_the_folder_workspace_and_parsed() {
    let (_directory, store, project) = remote_only_project().await;
    store
        .insert_workspace(workspace(
            "feature",
            "ssh-a",
            "/home/dev/.alera/worktrees/feature",
            WorkspaceKind::Linked,
        ))
        .await
        .unwrap();
    store
        .insert_workspace(workspace("main", "ssh-a", REMOTE_REPO, WorkspaceKind::Main))
        .await
        .unwrap();
    let reader = FakeReader::answering(Ok(Some(
        "git_hosting_provider = \"gitlab\"\n[new_workspace]\nsource_branch = \"develop\"\n".into(),
    )));

    let effective = remote_effective_project_config(&store, &reader, &project)
        .await
        .unwrap();

    assert_eq!(effective.origin, "repoFile");
    assert!(effective.error.is_none());
    assert_eq!(effective.config.new_workspace.source_branch, "develop");
    assert_eq!(
        effective.config.git_hosting_provider.as_deref(),
        Some("gitlab")
    );
    assert_eq!(reader.read_workspace_ids(), ["main"]);
    let (_, file_name, max_bytes) = reader.reads.lock().unwrap()[0].clone();
    assert_eq!(file_name, PROJECT_CONFIG_FILE_NAME);
    assert_eq!(max_bytes, MAX_PROJECT_CONFIG_BYTES);
}

#[tokio::test]
async fn a_missing_file_or_workspace_is_defaults() {
    let (_directory, store, project) = remote_only_project().await;
    let reader = FakeReader::answering(Ok(Some("unused".into())));
    let effective = remote_effective_project_config(&store, &reader, &project)
        .await
        .unwrap();
    assert_eq!(effective.origin, "none");
    assert!(
        reader.read_workspace_ids().is_empty(),
        "no workspace, no read"
    );

    store
        .insert_workspace(workspace("main", "ssh-a", REMOTE_REPO, WorkspaceKind::Main))
        .await
        .unwrap();
    let reader = FakeReader::answering(Ok(None));
    let effective = remote_effective_project_config(&store, &reader, &project)
        .await
        .unwrap();
    assert_eq!(effective.origin, "none");
    assert_eq!(effective.config, ProjectConfig::default());
    assert!(effective.error.is_none());
}

#[tokio::test]
async fn a_file_that_does_not_parse_is_reported_on_the_payload() {
    let (_directory, store, project) = remote_only_project().await;
    store
        .insert_workspace(workspace("main", "ssh-a", REMOTE_REPO, WorkspaceKind::Main))
        .await
        .unwrap();
    let reader = FakeReader::answering(Ok(Some("git_hosting_provider = 7\n".into())));

    let effective = remote_effective_project_config(&store, &reader, &project)
        .await
        .unwrap();

    assert_eq!(effective.origin, "repoFile");
    assert_eq!(effective.config, ProjectConfig::default());
    assert!(
        effective
            .error
            .as_deref()
            .is_some_and(|error| error.contains("git_hosting_provider")),
        "{:?}",
        effective.error
    );
}

#[tokio::test]
async fn a_ui_override_wins_without_reaching_the_host() {
    let (_directory, store, project) = remote_only_project().await;
    store
        .insert_workspace(workspace("main", "ssh-a", REMOTE_REPO, WorkspaceKind::Main))
        .await
        .unwrap();
    let override_config = ProjectConfig {
        git_hosting_provider: Some("github".into()),
        ..ProjectConfig::default()
    };
    store
        .upsert_project_config("project-1", override_config.clone(), Utc::now())
        .await
        .unwrap();
    let reader = FakeReader::answering(Err(HostError::state("the host is down")));

    let effective = remote_effective_project_config(&store, &reader, &project)
        .await
        .unwrap();

    assert_eq!(effective.origin, "uiOverride");
    assert_eq!(effective.config, override_config);
    assert!(reader.read_workspace_ids().is_empty());
}

#[tokio::test]
async fn a_read_that_fails_fails_the_request() {
    let (_directory, store, project) = remote_only_project().await;
    store
        .insert_workspace(workspace("main", "ssh-a", REMOTE_REPO, WorkspaceKind::Main))
        .await
        .unwrap();
    let reader = FakeReader::answering(Err(HostError::state("The host ssh-a did not answer")));

    let error = remote_effective_project_config(&store, &reader, &project)
        .await
        .unwrap_err();

    assert!(error.wire_message().contains("did not answer"));
}

#[test]
fn the_listing_names_the_config_file_and_its_size() {
    let listing = json!({"entries": [
        {"name": "alera.toml", "kind": "directory", "size": 0},
        {"name": "src", "kind": "directory", "size": 0},
    ]});
    assert!(
        root_file_size(&listing, "alera.toml").is_none(),
        "a folder is not the file"
    );
    let listing = json!({"entries": [
        {"name": "readme.md", "kind": "file", "size": 9},
        {"name": "alera.toml", "kind": "file", "size": 120},
    ]});
    assert_eq!(root_file_size(&listing, "alera.toml"), Some(120));
    let listing = json!({"entries": [{"name": "alera.toml", "kind": "symlink", "size": 3}]});
    assert_eq!(root_file_size(&listing, "alera.toml"), Some(3));
    assert!(root_file_size(&json!({}), "alera.toml").is_none());
}

#[test]
fn the_read_answer_is_decoded_whole_or_refused() {
    let read = |bytes: &[u8], total: u64, next: u64, is_text: bool| {
        json!({
            "dataBase64": STANDARD.encode(bytes),
            "totalBytes": total,
            "nextOffset": next,
            "isText": is_text,
        })
    };
    assert_eq!(
        text_from_read_response(&read(b"a = 1\n", 6, 6, true), "alera.toml", "ssh-a", 64).unwrap(),
        "a = 1\n"
    );
    let chunked = text_from_read_response(&read(b"a = 1", 70, 5, true), "alera.toml", "ssh-a", 64)
        .unwrap_err();
    assert!(
        chunked.wire_message().contains("at most 64 bytes"),
        "{chunked:?}"
    );
    let over =
        text_from_read_response(&read(b"", 65, 65, true), "alera.toml", "ssh-a", 64).unwrap_err();
    assert!(over.wire_message().contains("65 bytes"), "{over:?}");
    let binary = text_from_read_response(&read(b"\0\0", 2, 2, false), "alera.toml", "ssh-a", 64)
        .unwrap_err();
    assert!(
        binary.wire_message().contains("not a text file"),
        "{binary:?}"
    );
    let invalid =
        text_from_read_response(&read(&[0xff, 0xfe], 2, 2, true), "alera.toml", "ssh-a", 64)
            .unwrap_err();
    assert!(invalid.wire_message().contains("not UTF-8"), "{invalid:?}");
}
