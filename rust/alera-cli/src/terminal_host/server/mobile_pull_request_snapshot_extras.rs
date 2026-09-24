//! Additive snapshot fields a phone needs to offer pull request actions:
//! who is signed in (to allow editing only their own comments), which merge
//! methods apply, which base branches a new pull request can target, and
//! whether AI Assist can write its details. An older phone ignores all of
//! them; none of this bumps `aleraMobileProtocolVersion`.

use alera_core::runtime::{RuntimeStore, Workspace};
use git2::{BranchType, Repository};
use serde_json::{json, Value};

use super::mobile_pull_request_identity::parse_github_identity;
use super::mobile_pull_request_merge_methods::allowed_merge_methods;
use super::mobile_pull_request_requests::run_gh;

pub(super) async fn decorate_snapshot(
    store: &RuntimeStore,
    workspace: &Workspace,
    snapshot: &mut Value,
) {
    let ai_assist_enabled = store
        .effective_ai_assist_settings()
        .await
        .is_ok_and(|settings| settings.enabled);
    let preferred = snapshot["review"]["baseRefName"]
        .as_str()
        .map(ToOwned::to_owned);
    let path = workspace.path.clone();
    let (branches, suggested) = tokio::task::spawn_blocking(move || {
        let branches = base_branches(&path);
        let fallback = alera_core::git::default_branch(&path).ok();
        let suggested =
            pick_default_base_branch(&branches, preferred.as_deref().or(fallback.as_deref()));
        (branches, suggested)
    })
    .await
    .unwrap_or_default();
    snapshot["aiAssistEnabled"] = json!(ai_assist_enabled);
    snapshot["baseBranches"] = json!(branches);
    snapshot["suggestedBaseBranch"] = json!(suggested);

    let open = snapshot["review"]["state"].as_str() == Some("OPEN");
    snapshot["canComment"] = json!(open);
    if snapshot["authStatus"].as_str() != Some("authenticated") || !snapshot["review"].is_object() {
        return;
    }
    let Some(identity) = snapshot["remoteUrl"]
        .as_str()
        .and_then(parse_github_identity)
    else {
        return;
    };
    let viewer = viewer_login(&workspace.path, &identity.host).await;
    mark_editable_comments(snapshot, viewer.as_deref());
    snapshot["viewerLogin"] = json!(viewer);
    if !open {
        return;
    }
    let base = snapshot["review"]["baseRefName"]
        .as_str()
        .map(ToOwned::to_owned);
    match allowed_merge_methods(&workspace.path, &identity, base.as_deref()).await {
        Ok(methods) => snapshot["mergeMethods"] = json!(methods),
        Err(error) => {
            snapshot["mergeMethods"] = json!([]);
            snapshot["mergeMethodsError"] = json!(error);
        }
    }
}

async fn viewer_login(repo_path: &str, host: &str) -> Option<String> {
    let (code, stdout, _) = run_gh(
        repo_path,
        &["api", "--hostname", host, "user", "--jq", ".login"],
    )
    .await
    .ok()?;
    let login = stdout.trim();
    (code == 0 && !login.is_empty()).then(|| login.to_string())
}

/// Only the author may edit a comment from the phone.
fn mark_editable_comments(snapshot: &mut Value, viewer: Option<&str>) {
    let Some(comments) = snapshot["review"]["comments"].as_array_mut() else {
        return;
    };
    for comment in comments {
        let editable = viewer.is_some()
            && comment["author"].as_str() == viewer
            && comment["id"].as_i64().is_some_and(|id| id > 0);
        comment["canEdit"] = json!(editable);
    }
}

/// Local branches as they are and remote-tracking branches without their
/// remote prefix, de-duplicated and sorted.
fn base_branches(path: &str) -> Vec<String> {
    let Ok(repo) = Repository::discover(path) else {
        return Vec::new();
    };
    let Ok(branches) = repo.branches(None) else {
        return Vec::new();
    };
    let mut names = branches
        .filter_map(Result::ok)
        .filter_map(|(branch, kind)| {
            let name = branch.name().ok().flatten()?.to_string();
            match kind {
                BranchType::Local => Some(name),
                BranchType::Remote => name.split_once('/').map(|(_, short)| short.to_string()),
            }
        })
        .filter(|name| !name.is_empty() && name != "HEAD")
        .collect::<Vec<_>>();
    names.sort();
    names.dedup();
    names
}

/// The desktop's `pickDefaultBaseBranch`: the preferred branch, then `main`,
/// `master`, the first branch, or `main`.
fn pick_default_base_branch(branches: &[String], preferred: Option<&str>) -> String {
    let preferred = preferred.map(str::trim).filter(|value| !value.is_empty());
    if let Some(preferred) = preferred {
        if branches.iter().any(|branch| branch == preferred) {
            return preferred.to_string();
        }
    }
    for candidate in ["main", "master"] {
        if branches.iter().any(|branch| branch == candidate) {
            return candidate.to_string();
        }
    }
    branches
        .first()
        .cloned()
        .or_else(|| preferred.map(ToOwned::to_owned))
        .unwrap_or_else(|| "main".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_the_default_base_branch_like_desktop() {
        let branches = vec!["develop".to_string(), "main".to_string()];
        assert_eq!(
            pick_default_base_branch(&branches, Some("develop")),
            "develop"
        );
        assert_eq!(pick_default_base_branch(&branches, Some("gone")), "main");
        assert_eq!(pick_default_base_branch(&["dev".to_string()], None), "dev");
        assert_eq!(pick_default_base_branch(&[], Some("trunk")), "trunk");
        assert_eq!(pick_default_base_branch(&[], None), "main");
    }

    #[test]
    fn only_the_author_can_edit() {
        let mut snapshot = json!({"review": {"comments": [
            {"id": 1, "author": "me"},
            {"id": 2, "author": "you"},
            {"id": 0, "author": "me"},
        ]}});
        mark_editable_comments(&mut snapshot, Some("me"));
        let editable: Vec<bool> = snapshot["review"]["comments"]
            .as_array()
            .unwrap()
            .iter()
            .map(|comment| comment["canEdit"].as_bool().unwrap())
            .collect();
        assert_eq!(editable, [true, false, false]);
        mark_editable_comments(&mut snapshot, None);
        assert_eq!(snapshot["review"]["comments"][0]["canEdit"], false);
    }

    #[test]
    fn lists_local_and_remote_branches_without_the_remote_prefix() {
        let dir = tempfile::tempdir().unwrap();
        let repo = Repository::init(dir.path()).unwrap();
        let signature = git2::Signature::now("Alera", "alera@example.com").unwrap();
        let tree = repo
            .find_tree(repo.index().unwrap().write_tree().unwrap())
            .unwrap();
        let commit = repo
            .commit(Some("HEAD"), &signature, &signature, "init", &tree, &[])
            .unwrap();
        let commit = repo.find_commit(commit).unwrap();
        repo.branch("feat/x", &commit, false).unwrap();
        repo.reference("refs/remotes/origin/develop", commit.id(), false, "test")
            .unwrap();
        repo.reference("refs/remotes/origin/feat/x", commit.id(), false, "test")
            .unwrap();
        let head = repo.head().unwrap().shorthand().unwrap().to_string();
        let branches = base_branches(dir.path().to_str().unwrap());
        let mut expected = vec![head, "develop".to_string(), "feat/x".to_string()];
        expected.sort();
        expected.dedup();
        assert_eq!(branches, expected);
    }
}
