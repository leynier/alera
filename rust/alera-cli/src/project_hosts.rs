//! Which hosts a project is on, derived from its project checkouts. Shared by
//! the runtime verbs (`project.list`, `project.hosts.*`) and the CLI, which
//! reads the store directly for listings.

use alera_core::runtime::{CheckoutKind, RepositoryCheckout, RuntimeStore, LOCAL_HOST_ID};
use serde_json::{json, Value};

/// `checkouts` and `primaryHostId` for every project, merged into the
/// `project.list` items. Additive: an older client ignores both.
pub(crate) async fn decorate_projects(store: &RuntimeStore, projects: &mut Value) {
    let Some(items) = projects.as_array_mut() else {
        return;
    };
    for item in items {
        let Some(project_id) = item.get("id").and_then(Value::as_str) else {
            continue;
        };
        let repo_path = item
            .get("repoPath")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let checkouts = project_checkouts(store, project_id)
            .await
            .unwrap_or_default();
        item["primaryHostId"] = json!(primary_host_id(&repo_path, &checkouts));
        item["checkouts"] = host_rows(&repo_path, &checkouts)
            .into_iter()
            .map(|(host_id, path)| json!({"hostId": host_id, "path": path}))
            .collect();
    }
}

pub(crate) async fn project_checkouts(
    store: &RuntimeStore,
    project_id: &str,
) -> anyhow::Result<Vec<RepositoryCheckout>> {
    Ok(store
        .list_project_checkouts(project_id)
        .await?
        .into_iter()
        .filter(|checkout| checkout.kind == CheckoutKind::Project)
        .collect())
}

/// The host of the project's own `repoPath`. It is this machine unless that
/// path is the checkout of another host and nothing is registered here, which
/// is what a remote-only project looks like. A project stored without a local
/// checkout row (anything that came through `project.upsert`) is still local,
/// so the absence of a row is never read as "lives elsewhere".
pub(crate) fn primary_host_id(repo_path: &str, checkouts: &[RepositoryCheckout]) -> String {
    if checkouts
        .iter()
        .any(|checkout| checkout.host_id == LOCAL_HOST_ID)
    {
        return LOCAL_HOST_ID.to_string();
    }
    checkouts
        .iter()
        .find(|checkout| checkout.path == repo_path)
        .map_or_else(
            || LOCAL_HOST_ID.to_string(),
            |checkout| checkout.host_id.clone(),
        )
}

/// Every host the project is on, as `(hostId, path)`. A local primary without
/// a checkout row is listed from `repoPath`, so it shows up like any other.
pub(crate) fn host_rows(
    repo_path: &str,
    checkouts: &[RepositoryCheckout],
) -> Vec<(String, String)> {
    let mut rows: Vec<(String, String)> = checkouts
        .iter()
        .map(|checkout| (checkout.host_id.clone(), checkout.path.clone()))
        .collect();
    if primary_host_id(repo_path, checkouts) == LOCAL_HOST_ID
        && !rows.iter().any(|(host_id, _)| host_id == LOCAL_HOST_ID)
    {
        rows.insert(0, (LOCAL_HOST_ID.to_string(), repo_path.to_string()));
    }
    rows
}

/// The host a new workspace goes to when the caller names none: the host of
/// the project's own folder. For an ordinary project that is this device, as
/// it always was; for a project that lives only on a server it is that server,
/// where "this device" would point at a folder that does not exist.
pub(crate) async fn workspace_host_id(
    store: &RuntimeStore,
    project: &alera_core::runtime::Project,
    requested: Option<&str>,
) -> String {
    if requested.is_some_and(|host_id| !host_id.trim().is_empty()) {
        return crate::ssh_remote::normalized_host_id(requested);
    }
    let checkouts = project_checkouts(store, &project.id)
        .await
        .unwrap_or_default();
    primary_host_id(&project.repo_path, &checkouts)
}
