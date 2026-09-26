//! The last `alera.toml` the hub read from a remote-only project's host.
//!
//! Agent launches and prompt composition run inside the actor and cannot wait
//! on a host link, so for a project whose folder is on another host they use
//! the config the hub read most recently (the desktop reads it whenever it
//! shows the project, and a launch that finds nothing cached starts a read for
//! the next one). A local project keeps reading its folder directly.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use alera_core::runtime::{Project, ProjectConfig};
use serde_json::Value;

use super::remote_project_config::{remote_effective_project_config, LinkedProjectFileReader};
use super::{ServerActor, ServerCommand};
use crate::project_management::EffectiveProjectConfigPayload;
use crate::terminal_host::host_error::{HostError, HostResult};

/// Long enough that a burst of launches reads the file once, short enough
/// that an edit on the host shows up without restarting anything.
const FRESH_FOR: Duration = Duration::from_secs(5 * 60);

/// Interior mutability because prompt composition holds the actor by `&self`.
#[derive(Default)]
pub(super) struct RemoteProjectConfigCache {
    state: Mutex<CacheState>,
}

#[derive(Default)]
struct CacheState {
    entries: HashMap<String, (ProjectConfig, Instant)>,
    refreshing: HashSet<String>,
}

impl RemoteProjectConfigCache {
    fn state(&self) -> std::sync::MutexGuard<'_, CacheState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub(super) fn remember(&self, project_id: &str, payload: &Value) {
        let mut state = self.state();
        state.refreshing.remove(project_id);
        // A file that did not parse is not a config; the last good one stays.
        if payload.get("error").is_some_and(|error| !error.is_null()) {
            return;
        }
        if let Ok(config) = serde_json::from_value::<ProjectConfig>(payload["config"].clone()) {
            state
                .entries
                .insert(project_id.to_string(), (config, Instant::now()));
        }
    }

    fn forget_refresh(&self, project_id: &str) {
        self.state().refreshing.remove(project_id);
    }

    /// `(config, fresh)`: the last good config, and whether it is recent
    /// enough to use without starting another read.
    fn lookup(&self, project_id: &str) -> Option<(ProjectConfig, bool)> {
        self.state()
            .entries
            .get(project_id)
            .map(|(config, read_at)| (config.clone(), read_at.elapsed() < FRESH_FOR))
    }

    /// Claims the refresh; false when one is already running.
    fn begin_refresh(&self, project_id: &str) -> bool {
        self.state().refreshing.insert(project_id.to_string())
    }
}

impl ServerActor {
    /// The config a launch or a prompt should use for a project. Local
    /// projects read their folder as always; a remote-only project answers
    /// from the cache and refreshes it in the background when it is stale.
    pub(super) async fn effective_project_config_for_launch(
        &self,
        project_id: &str,
    ) -> HostResult<EffectiveProjectConfigPayload> {
        let project = self
            .runtime_store
            .find_project(project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Project not found: {project_id}")))?;
        if crate::project_hosts::project_folder_is_local(&self.runtime_store, &project).await {
            return crate::project_management::effective_project_config(
                &self.runtime_store,
                project_id,
            )
            .await
            .map_err(|error| HostError::state(error.to_string()));
        }
        let cached = self.remote_project_configs.lookup(project_id);
        if let Some((config, true)) = cached {
            return Ok(EffectiveProjectConfigPayload {
                config,
                origin: "repoFile",
                error: None,
            });
        }
        self.refresh_remote_project_config(project);
        Ok(EffectiveProjectConfigPayload {
            config: cached.map(|(config, _)| config).unwrap_or_default(),
            origin: "none",
            error: None,
        })
    }

    fn refresh_remote_project_config(&self, project: Project) {
        if !self.remote_project_configs.begin_refresh(&project.id) {
            return;
        }
        let store = self.runtime_store.clone();
        let links = self.host_links.clone();
        let inbox = self.inbox.clone();
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
            let _ = inbox.send(ServerCommand::RemoteProjectConfigRead {
                project_id: project.id,
                result,
            });
        });
    }

    pub(super) fn finish_remote_project_config_read(
        &mut self,
        project_id: &str,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(payload) => self.remote_project_configs.remember(project_id, &payload),
            Err(error) => {
                self.remote_project_configs.forget_refresh(project_id);
                tracing::warn!(
                    target: "host_link",
                    project_id,
                    "could not read the project configuration from the remote host: {}",
                    error.wire_message()
                );
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_parsed_config_is_remembered_and_a_broken_file_keeps_the_last_good_one() {
        let cache = RemoteProjectConfigCache::default();
        cache.remember(
            "p",
            &json!({"config": {"newWorkspace": {"promptAppend": "Read AGENTS.md first"}}, "origin": "repoFile", "error": null}),
        );
        assert_eq!(
            cache.lookup("p").unwrap().0.new_workspace.prompt_append,
            "Read AGENTS.md first"
        );
        cache.remember(
            "p",
            &json!({"config": {}, "origin": "repoFile", "error": "line 3: expected a table"}),
        );
        assert_eq!(
            cache.lookup("p").unwrap().0.new_workspace.prompt_append,
            "Read AGENTS.md first"
        );
        assert!(cache.lookup("other").is_none());
        assert!(cache.begin_refresh("p"));
        assert!(!cache.begin_refresh("p"), "one read at a time per project");
        cache.forget_refresh("p");
        assert!(cache.begin_refresh("p"));
    }
}

#[cfg(test)]
mod actor_tests {
    use super::super::checkout_buffer_guards_tests::fixture;
    use serde_json::json;

    #[tokio::test]
    async fn a_launch_uses_the_cached_remote_config_and_reads_it_once_when_stale() {
        let (_root, mut actor) = fixture().await;
        let now = chrono::Utc::now();
        let project: alera_core::runtime::Project = serde_json::from_value(json!({
            "id": "remote-only", "name": "Server Only", "repoPath": "/srv/remote/repo",
            "kind": "gitRepository", "createdAt": now, "updatedAt": now,
        }))
        .unwrap();
        actor.runtime_store.upsert_project(project).await.unwrap();
        actor
            .runtime_store
            .register_project_checkout("remote-only", "ssh", "/srv/remote/repo")
            .await
            .unwrap();
        let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
        actor.inbox = inbox;

        // Nothing cached yet: defaults, and one read starts in the background.
        let first = actor
            .effective_project_config_for_launch("remote-only")
            .await
            .unwrap();
        assert_eq!(first.origin, "none");
        assert!(first.config.new_workspace.prompt_append.is_empty());
        let second = actor
            .effective_project_config_for_launch("remote-only")
            .await
            .unwrap();
        assert_eq!(second.origin, "none");
        let read = commands.recv().await.expect("the read reports back");
        assert!(matches!(
            read,
            super::super::ServerCommand::RemoteProjectConfigRead { .. }
        ));
        assert!(
            commands.try_recv().is_err(),
            "the second launch must not start a second read"
        );

        // The desktop read the file: launches use it without touching the link.
        actor.finish_remote_project_config_read(
            "remote-only",
            Ok(json!({"config": {"newWorkspace": {"promptAppend": "Use pnpm"}}, "origin": "repoFile", "error": null})),
        );
        let cached = actor
            .effective_project_config_for_launch("remote-only")
            .await
            .unwrap();
        assert_eq!(cached.origin, "repoFile");
        assert_eq!(cached.config.new_workspace.prompt_append, "Use pnpm");
        assert!(commands.try_recv().is_err());

        // A local project keeps reading its own folder.
        let local = actor
            .effective_project_config_for_launch("project")
            .await
            .unwrap();
        assert_eq!(local.origin, "none");
    }
}
