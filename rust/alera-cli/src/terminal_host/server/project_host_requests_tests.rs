use super::*;
use crate::project_hosts::decorate_projects;
use alera_core::runtime::CheckoutKind;

async fn store_with_project(kind: &str, repo_path: &str) -> (tempfile::TempDir, RuntimeStore) {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = chrono::Utc::now();
    let project: Project = serde_json::from_value(json!({
        "id": "project-1", "name": "My Project", "repoPath": repo_path, "kind": kind,
        "createdAt": now, "updatedAt": now,
    }))
    .unwrap();
    store.upsert_project(project).await.unwrap();
    (directory, store)
}

fn checkout_at(host_id: &str, path: &str) -> RepositoryCheckout {
    RepositoryCheckout {
        path: path.into(),
        ..checkout(host_id)
    }
}

fn checkout(host_id: &str) -> RepositoryCheckout {
    RepositoryCheckout {
        id: host_id.into(),
        project_id: "project-1".into(),
        host_id: host_id.into(),
        path: format!("/srv/{host_id}"),
        kind: CheckoutKind::Project,
        repository_path: None,
    }
}

#[test]
fn the_primary_host_is_local_unless_the_project_lives_only_elsewhere() {
    let repo = "/home/me/repo";
    assert_eq!(
        primary_host_id(repo, &[]),
        "local",
        "a legacy project has no rows"
    );
    assert_eq!(
        primary_host_id(repo, &[checkout("ssh-a"), checkout("local")]),
        "local"
    );
    assert_eq!(
        primary_host_id(repo, &[checkout("ssh-a")]),
        "local",
        "a missing local row is not evidence that the project lives elsewhere"
    );
    let remote_only = [checkout("ssh-a"), checkout_at("ssh-b", repo)];
    assert_eq!(primary_host_id(repo, &remote_only), "ssh-b");
    assert_eq!(
        host_rows(repo, &remote_only).len(),
        2,
        "no local row is invented"
    );
    assert_eq!(
        host_rows(repo, &[checkout("ssh-a")])[0],
        ("local".to_string(), repo.to_string())
    );
}

#[test]
fn the_clone_directory_is_named_after_the_project_folder() {
    let project = |repo_path: &str, name: &str| -> Project {
        let now = chrono::Utc::now();
        serde_json::from_value(json!({
            "id": "p", "name": name, "repoPath": repo_path, "kind": "gitRepository",
            "createdAt": now, "updatedAt": now,
        }))
        .unwrap()
    };
    assert_eq!(
        clone_directory_name(&project("/home/me/code/alera/", "Alera")),
        "alera"
    );
    assert_eq!(
        clone_directory_name(&project(r"C:\code\my repo", "X")),
        "my-repo"
    );
    assert_eq!(
        clone_directory_name(&project("", "Side Project!")),
        "Side-Project"
    );
    assert_eq!(clone_directory_name(&project("/", "..")), "project");
}

#[tokio::test]
async fn hosts_list_the_checkouts_with_their_workspace_counts() {
    let (_directory, store) = store_with_project("gitRepository", "/home/me/repo").await;
    store
        .register_project_checkout("project-1", "ssh-a", "/srv/repo")
        .await
        .unwrap();
    let hosts = project_hosts(&store, "project-1").await.unwrap();
    assert_eq!(hosts["primaryHostId"], "local");
    let rows = hosts["hosts"].as_array().unwrap();
    assert_eq!(rows.len(), 2, "{hosts}");
    let remote = rows.iter().find(|row| row["hostId"] == "ssh-a").unwrap();
    assert_eq!(remote["path"], "/srv/repo");
    assert_eq!(remote["primary"], false);
    assert_eq!(remote["workspaceCount"], 0);

    let mut listed = json!([{"id": "project-1"}, {"id": "missing"}]);
    decorate_projects(&store, &mut listed).await;
    assert_eq!(listed[0]["primaryHostId"], "local");
    assert_eq!(listed[0]["checkouts"].as_array().unwrap().len(), 2);
    assert_eq!(listed[1]["primaryHostId"], "local");
}

#[tokio::test]
async fn add_registers_a_path_or_asks_the_host_to_clone_by_name() {
    let (_directory, store) = store_with_project("gitRepository", "/home/me/code/alera").await;
    let existing = add_request(
        &store,
        "project-1",
        &json!({"hostId": "ssh-a", "path": " /srv/alera "}),
    )
    .await
    .unwrap();
    assert_eq!(existing.path, "/srv/alera");
    assert!(existing.clone_url.is_none() && existing.clone_name.is_none());

    let cloned = add_request(
        &store,
        "project-1",
        &json!({"hostId": "ssh-a", "cloneUrl": "git@github.com:o/alera.git"}),
    )
    .await
    .unwrap();
    assert!(
        cloned.path.is_empty(),
        "the host resolves its own projects folder"
    );
    assert_eq!(
        cloned.clone_url.as_deref(),
        Some("git@github.com:o/alera.git")
    );
    assert_eq!(cloned.clone_name.as_deref(), Some("alera"));

    // No URL given and the local folder is not a repository with a remote.
    let error = add_request(&store, "project-1", &json!({"hostId": "ssh-a"}))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("no Git remote"), "{error}");
}

#[tokio::test]
async fn add_refuses_duplicates_this_device_and_folder_projects() {
    let (_directory, store) = store_with_project("gitRepository", "/home/me/repo").await;
    store
        .register_project_checkout("project-1", "ssh-a", "/srv/repo")
        .await
        .unwrap();
    for (payload, expected) in [
        (
            json!({"hostId": "ssh-a", "path": "/other"}),
            "already on this host",
        ),
        (
            json!({"hostId": "local", "path": "/other"}),
            "not supported yet",
        ),
    ] {
        let error = add_request(&store, "project-1", &payload)
            .await
            .unwrap_err();
        assert!(error.to_string().contains(expected), "{error}");
    }
    let (_folder_directory, folder) = store_with_project("folder", "/home/me/notes").await;
    let error = add_request(
        &folder,
        "project-1",
        &json!({"hostId": "ssh-a", "path": "/srv/n"}),
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("folder project"), "{error}");
}

#[tokio::test]
async fn remove_forgets_a_secondary_host_and_protects_the_rest() {
    let (_directory, store) = store_with_project("gitRepository", "/home/me/repo").await;
    store
        .register_project_checkout("project-1", "ssh-a", "/srv/repo")
        .await
        .unwrap();
    let primary = remove_project_host(&store, "project-1", "local")
        .await
        .unwrap_err();
    assert!(primary.to_string().contains("own folder"), "{primary}");
    let unknown = remove_project_host(&store, "project-1", "ssh-z")
        .await
        .unwrap_err();
    assert!(
        unknown.to_string().contains("not on this host"),
        "{unknown}"
    );

    remove_project_host(&store, "project-1", "ssh-a")
        .await
        .unwrap();
    let hosts = project_hosts(&store, "project-1").await.unwrap();
    assert_eq!(hosts["hosts"].as_array().unwrap().len(), 1);
    let only = remove_project_host(&store, "project-1", "local")
        .await
        .unwrap_err();
    assert!(only.to_string().contains("only host"), "{only}");
}
