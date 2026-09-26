//! `project.hosts.*`: one project registered on several hosts.
//!
//! A project is registered once and then added to hosts; "work on project X on
//! host Y" is a project checkout row per host, which is what New Workspace,
//! the branch catalog and the mirror already read. `add` with a `path`
//! registers an existing checkout; without one the host clones the project's
//! remote into its default projects folder, which only that host can resolve
//! because only it knows its home directory. `remove` forgets the checkout and
//! never touches files. A folder project has no remote to clone and no way to
//! keep two copies in step, so it stays on the one host it was registered on.

use alera_core::runtime::{Project, ProjectKind, RepositoryCheckout, RuntimeStore, LOCAL_HOST_ID};
use serde_json::{json, Value};

use super::requests::{optional_string_key, require_string_key};
use super::ServerActor;
use crate::project_hosts::{host_rows, primary_host_id};
use crate::remote_project_checkout::RegisterProjectCheckoutRequest;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::ok_response;

impl ServerActor {
    /// `Ok(false)` means the request is not a `project.hosts.*` verb, nor the
    /// effective config of a project whose folder is on another host.
    pub(super) async fn try_start_project_hosts_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if self
            .try_start_remote_project_config_request(client_id, request_id, request_type, payload)
            .await?
        {
            return Ok(true);
        }
        if request_type == "project.registerRemote" {
            self.require_auth(client_id)?;
            self.require_request_allowed(client_id, request_type)?;
            let request = serde_json::from_value(payload.clone()).map_err(|error| {
                HostError::format(format!("Invalid remote project payload: {error}"))
            })?;
            self.start_remote_project_registration(client_id, request_id, request);
            return Ok(true);
        }
        if !matches!(
            request_type,
            "project.hosts.list" | "project.hosts.add" | "project.hosts.remove"
        ) {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        let project_id = require_string_key(payload, "projectId")?;
        match request_type {
            "project.hosts.list" => {
                let hosts = project_hosts(&self.runtime_store, &project_id).await?;
                self.client_write(client_id, ok_response(request_id, hosts));
            }
            "project.hosts.remove" => {
                let host_id = require_string_key(payload, "hostId")?;
                remove_project_host(&self.runtime_store, &project_id, &host_id).await?;
                let hosts = project_hosts(&self.runtime_store, &project_id).await?;
                self.broadcast_project_state_changed();
                self.client_write(client_id, ok_response(request_id, hosts));
            }
            _ => {
                let request = add_request(&self.runtime_store, &project_id, payload).await?;
                // The registration job answers the client with the checkout
                // and announces the change when it finishes.
                self.start_project_checkout_registration(client_id, request_id, request);
            }
        }
        Ok(true)
    }
}

async fn find_project(store: &RuntimeStore, project_id: &str) -> HostResult<Project> {
    store
        .find_project(project_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok_or_else(|| HostError::state(format!("Project not found: {project_id}")))
}

async fn project_checkouts(
    store: &RuntimeStore,
    project_id: &str,
) -> HostResult<Vec<RepositoryCheckout>> {
    crate::project_hosts::project_checkouts(store, project_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))
}

pub(super) async fn project_hosts(store: &RuntimeStore, project_id: &str) -> HostResult<Value> {
    let project = find_project(store, project_id).await?;
    let checkouts = project_checkouts(store, project_id).await?;
    let workspaces = store
        .list_workspaces(project_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let primary = primary_host_id(&project.repo_path, &checkouts);
    let hosts: Vec<Value> = host_rows(&project.repo_path, &checkouts)
        .into_iter()
        .map(|(host_id, path)| {
            json!({
                "primary": host_id == primary,
                "workspaceCount": workspaces
                    .iter()
                    .filter(|workspace| workspace.host_id == host_id)
                    .count(),
                "hostId": host_id,
                "path": path,
            })
        })
        .collect();
    Ok(json!({
        "projectId": project.id,
        "kind": project.kind,
        "primaryHostId": primary,
        "hosts": hosts,
    }))
}

async fn remove_project_host(
    store: &RuntimeStore,
    project_id: &str,
    host_id: &str,
) -> HostResult<()> {
    let project = find_project(store, project_id).await?;
    let host_id = crate::ssh_remote::normalized_host_id(Some(host_id));
    let checkouts = project_checkouts(store, project_id).await?;
    let rows = host_rows(&project.repo_path, &checkouts);
    if !rows.iter().any(|(row_host, _)| *row_host == host_id) {
        return Err(HostError::state("The project is not on this host."));
    }
    if rows.len() == 1 {
        return Err(HostError::state(
            "This is the project's only host. Remove the project instead.",
        ));
    }
    if primary_host_id(&project.repo_path, &checkouts) == host_id {
        return Err(HostError::state(
            "The project's own folder lives on this host, so it cannot be removed from it.",
        ));
    }
    store
        .remove_project_checkout(project_id, &host_id)
        .await
        .map(|_| ())
        .map_err(|error| HostError::state(error.to_string()))
}

async fn add_request(
    store: &RuntimeStore,
    project_id: &str,
    payload: &Value,
) -> HostResult<RegisterProjectCheckoutRequest> {
    let project = find_project(store, project_id).await?;
    let host_id =
        crate::ssh_remote::normalized_host_id(Some(&require_string_key(payload, "hostId")?));
    if host_id == LOCAL_HOST_ID {
        return Err(HostError::state(
            "Adding this device to a project is not supported yet; register the local folder as its own project.",
        ));
    }
    let checkouts = project_checkouts(store, project_id).await?;
    if checkouts.iter().any(|checkout| checkout.host_id == host_id) {
        return Err(HostError::state("The project is already on this host."));
    }
    if project.kind == ProjectKind::Folder {
        return Err(HostError::state(
            "A folder project lives on one host. Only Git projects can be added to more hosts.",
        ));
    }
    let path = optional_string_key(payload, "path")
        .map(|path| path.trim().to_string())
        .filter(|path| !path.is_empty());
    if let Some(path) = path {
        return Ok(RegisterProjectCheckoutRequest {
            project_id: project.id,
            host_id,
            path,
            clone_url: None,
            clone_name: None,
        });
    }
    let clone_url = match optional_string_key(payload, "cloneUrl")
        .map(|url| url.trim().to_string())
        .filter(|url| !url.is_empty())
    {
        Some(url) => url,
        None => {
            let primary = primary_host_id(&project.repo_path, &checkouts);
            project_remote_url(&project, &primary).await?
        }
    };
    Ok(RegisterProjectCheckoutRequest {
        clone_name: Some(clone_directory_name(&project)),
        project_id: project.id,
        host_id,
        path: String::new(),
        clone_url: Some(clone_url),
    })
}

async fn project_remote_url(project: &Project, primary_host_id: &str) -> HostResult<String> {
    if primary_host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "This project has no folder on this device to read its remote from. Pass the repository URL or an existing path.",
        ));
    }
    let repo_path = project.repo_path.clone();
    tokio::task::spawn_blocking(move || alera_core::git::repository_remote_url(&repo_path))
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok()
        .flatten()
        .filter(|url| !url.trim().is_empty())
        .ok_or_else(|| {
            HostError::state(
                "This project has no Git remote to clone. Add a remote, or pass an existing path on the host.",
            )
        })
}

/// The project folder's own name, which is what the user already calls the
/// repository on disk; the project's display name is the fallback.
fn clone_directory_name(project: &Project) -> String {
    let from_path = project
        .repo_path
        .trim_end_matches(['/', '\\'])
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or_default();
    let raw = if from_path.trim().is_empty() {
        project.name.as_str()
    } else {
        from_path
    };
    let cleaned: String = raw
        .trim()
        .chars()
        .map(|character| {
            if character.is_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '-'
            }
        })
        .collect();
    let cleaned = cleaned.trim_matches(['-', '.']).to_string();
    if cleaned.is_empty() {
        "project".to_string()
    } else {
        cleaned
    }
}

#[cfg(test)]
#[path = "project_host_requests_tests.rs"]
mod tests;
