//! The repository `alera.toml` of a project that lives only on a host.
//!
//! The hub cannot read it from disk: `Project.repo_path` is a path on the
//! satellite, and whatever sits at the same path here is unrelated. Instead
//! the hub picks one of the project's workspaces on that host and reads the
//! file through the same `workspace.files.*` verbs the explorer uses, so the
//! read is mirrored, routed and bounded exactly like any other remote file
//! read. The precedence is the one `project_management::effective_project_config`
//! applies to a local project: a UI override wins, a missing file is defaults,
//! and a file that does not parse is reported on the payload rather than
//! failing the request.

use alera_core::runtime::{Project, ProjectConfig, RuntimeStore, Workspace};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

use crate::project_management::EffectiveProjectConfigPayload;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};

pub(crate) const PROJECT_CONFIG_FILE_NAME: &str = "alera.toml";
/// A project config is a handful of commands and copy rules; anything larger
/// is not one, and the hub refuses it rather than paging through it.
pub(crate) const MAX_PROJECT_CONFIG_BYTES: u64 = 64 * 1024;

const EFFECTIVE_CONFIG_VERB: &str = "projectConfig.effective";

impl ServerActor {
    /// `projectConfig.effective` for a project whose folder is on another
    /// host. `Ok(false)` leaves every other project on the local arm, so a
    /// local project keeps the code path it always had.
    pub(super) async fn try_start_remote_project_config_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if request_type != EFFECTIVE_CONFIG_VERB {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        let project_id = require_string_key(payload, "projectId")?;
        let Some(project) = self
            .runtime_store
            .find_project(&project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(false);
        };
        if crate::project_hosts::project_folder_is_local(&self.runtime_store, &project).await {
            return Ok(false);
        }
        let store = self.runtime_store.clone();
        let links = self.host_links.clone();
        let inbox = self.inbox.clone();
        // Opening the link awaits an ssh handshake, so the read runs off the
        // actor and answers through the completion every spawned
        // workspace-scoped read already uses.
        tokio::spawn(async move {
            let reader = LinkedProjectFileReader {
                store: &store,
                links: &links,
            };
            let result = remote_effective_project_config(&store, &reader, &project)
                .await
                .and_then(|payload| {
                    serde_json::to_value(payload)
                        .map_err(|error| HostError::state(error.to_string()))
                });
            // The desktop's read is the freshest copy the launch cache can get.
            let _ = inbox.send(ServerCommand::RemoteProjectConfigRead {
                project_id: project.id.clone(),
                result: result.clone(),
            });
            let _ = inbox.send(ServerCommand::MobileWorkspaceFileFinished {
                client_id,
                request_id,
                request_type: EFFECTIVE_CONFIG_VERB.to_string(),
                result,
            });
        });
        Ok(true)
    }
}

/// Reads one file at the root of a workspace on the host that owns it.
pub(crate) trait RemoteProjectFileReader {
    /// `Ok(None)` when the workspace root has no file by that name.
    async fn read_root_text_file(
        &self,
        workspace: &Workspace,
        file_name: &str,
        max_bytes: u64,
    ) -> HostResult<Option<String>>;
}

/// The effective config of a project whose primary host is remote.
pub(crate) async fn remote_effective_project_config<R: RemoteProjectFileReader>(
    store: &RuntimeStore,
    reader: &R,
    project: &Project,
) -> HostResult<EffectiveProjectConfigPayload> {
    let state = |error: anyhow::Error| HostError::state(error.to_string());
    if let Some(config) = store
        .find_project_config(&project.id)
        .await
        .map_err(state)?
    {
        return Ok(payload(config, "uiOverride", None));
    }
    let checkouts = crate::project_hosts::project_checkouts(store, &project.id)
        .await
        .map_err(state)?;
    let host_id = crate::project_hosts::primary_host_id(&project.repo_path, &checkouts);
    let checkout_path = checkouts
        .iter()
        .find(|checkout| checkout.host_id == host_id)
        .map_or(project.repo_path.as_str(), |checkout| {
            checkout.path.as_str()
        });
    let workspaces: Vec<Workspace> = store
        .list_workspaces(&project.id)
        .await
        .map_err(state)?
        .into_iter()
        .filter(|workspace| workspace.host_id == host_id)
        .collect();
    let Some(workspace) = config_workspace(checkout_path, &workspaces) else {
        return Ok(payload(ProjectConfig::default(), "none", None));
    };
    let Some(contents) = reader
        .read_root_text_file(
            workspace,
            PROJECT_CONFIG_FILE_NAME,
            MAX_PROJECT_CONFIG_BYTES,
        )
        .await?
    else {
        return Ok(payload(ProjectConfig::default(), "none", None));
    };
    Ok(
        match crate::project_config_toml::parse_project_config_toml(&contents) {
            Ok(config) => payload(config, "repoFile", None),
            Err(error) => payload(
                ProjectConfig::default(),
                "repoFile",
                Some(error.to_string()),
            ),
        },
    )
}

/// The workspace whose root holds the project's own `alera.toml`: the one on
/// the project folder, which is what a local project reads too. Failing that,
/// the first workspace on the host stands in and its own copy is read; a
/// linked worktree carries the file of the branch it has checked out, which
/// is normally the same file, and the alternative is answering defaults for a
/// project that does have a config.
pub(crate) fn config_workspace<'a>(
    checkout_path: &str,
    workspaces: &'a [Workspace],
) -> Option<&'a Workspace> {
    workspaces
        .iter()
        .find(|workspace| crate::windows_path_form::same_path(&workspace.path, checkout_path))
        .or_else(|| workspaces.first())
}

/// Reads through the host link, mirroring the workspace first, with the same
/// one-shot ssh fallback the explorer keeps for a host whose link is down.
pub(crate) struct LinkedProjectFileReader<'a> {
    pub(crate) store: &'a RuntimeStore,
    pub(crate) links: &'a HostLinkRegistry,
}

impl RemoteProjectFileReader for LinkedProjectFileReader<'_> {
    async fn read_root_text_file(
        &self,
        workspace: &Workspace,
        file_name: &str,
        max_bytes: u64,
    ) -> HostResult<Option<String>> {
        let list_payload = json!({
            "workspaceId": workspace.id,
            "relativePath": "",
            "hideIgnored": false,
        });
        let listing = match self.forward("workspace.files.list", &list_payload).await? {
            Some(listing) => listing,
            None => crate::remote_workspace_files::list_workspace_files(
                self.store, workspace, "", false,
            )
            .await
            .map(|entries| crate::remote_workspace_files::entries_to_json(&entries))
            .map_err(|error| HostError::state(error.to_string()))?,
        };
        let Some(size) = root_file_size(&listing, file_name) else {
            return Ok(None);
        };
        if size > max_bytes {
            return Err(oversized(file_name, &workspace.host_id, size, max_bytes));
        }
        let read_payload = json!({
            "workspaceId": workspace.id,
            "relativePath": file_name,
            "offset": 0,
            "length": max_bytes,
        });
        let read = match self.forward("workspace.files.read", &read_payload).await? {
            Some(read) => read,
            None => crate::remote_workspace_files::try_read_remote_from_payload(
                self.store,
                workspace,
                &read_payload,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!(
                    "Workspace {} is not on a remote host.",
                    workspace.id
                ))
            })?,
        };
        text_from_read_response(&read, file_name, &workspace.host_id, max_bytes).map(Some)
    }
}

impl LinkedProjectFileReader<'_> {
    async fn forward(&self, verb: &str, payload: &Value) -> HostResult<Option<Value>> {
        super::host_link_routing::forward_workspace_scoped_request(
            self.store, self.links, verb, payload,
        )
        .await
    }
}

/// The size of a regular file (or a symlink to one) named `file_name` in a
/// `workspace.files.list` answer, `None` when the root has no such entry.
pub(crate) fn root_file_size(listing: &Value, file_name: &str) -> Option<u64> {
    listing["entries"]
        .as_array()?
        .iter()
        .find(|entry| {
            entry["name"].as_str() == Some(file_name)
                && matches!(entry["kind"].as_str(), Some("file") | Some("symlink"))
        })
        .map(|entry| entry["size"].as_u64().unwrap_or(0))
}

/// The whole file out of a `workspace.files.read` answer. The verb pages
/// through large files; a config that needs a second page is over the cap.
pub(crate) fn text_from_read_response(
    read: &Value,
    file_name: &str,
    host_id: &str,
    max_bytes: u64,
) -> HostResult<String> {
    let total = read["totalBytes"].as_u64().unwrap_or(0);
    let next_offset = read["nextOffset"].as_u64().unwrap_or(total);
    if total > max_bytes || next_offset < total {
        return Err(oversized(file_name, host_id, total, max_bytes));
    }
    if read["isText"].as_bool() != Some(true) {
        return Err(HostError::state(format!(
            "{file_name} on host {host_id} is not a text file."
        )));
    }
    let bytes = STANDARD
        .decode(read["dataBase64"].as_str().unwrap_or_default())
        .map_err(|error| {
            HostError::state(format!(
                "Could not decode {file_name} from host {host_id}: {error}"
            ))
        })?;
    String::from_utf8(bytes)
        .map_err(|_| HostError::state(format!("{file_name} on host {host_id} is not UTF-8.")))
}

fn oversized(file_name: &str, host_id: &str, size: u64, max_bytes: u64) -> HostError {
    HostError::state(format!(
        "{file_name} on host {host_id} is {size} bytes; the hub reads a project config of at most {max_bytes} bytes."
    ))
}

fn payload(
    config: ProjectConfig,
    origin: &'static str,
    error: Option<String>,
) -> EffectiveProjectConfigPayload {
    EffectiveProjectConfigPayload {
        config,
        origin,
        error,
    }
}

#[cfg(test)]
#[path = "remote_project_config_tests.rs"]
mod tests;
