use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::PullRequestWatch;
use serde_json::{json, Value};
use tokio::task::JoinHandle;
use uuid::Uuid;

use super::pull_request_watch_evaluation::{evaluate, Evaluation};
use super::requests::terminal_session_id_from_tab;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) struct WatchRuntime {
    pub active: bool,
    jobs: HashMap<String, (Uuid, JoinHandle<()>)>,
    polls: Arc<tokio::sync::Semaphore>,
}

impl Default for WatchRuntime {
    fn default() -> Self {
        Self {
            active: false,
            jobs: HashMap::new(),
            polls: Arc::new(tokio::sync::Semaphore::new(4)),
        }
    }
}

impl WatchRuntime {
    pub fn cancel(&mut self, workspace_id: &str) {
        if let Some((_, job)) = self.jobs.remove(workspace_id) {
            job.abort();
        }
    }
}

impl Drop for WatchRuntime {
    fn drop(&mut self) {
        for (_, (_, job)) in self.jobs.drain() {
            job.abort();
        }
    }
}

pub(super) fn spawn(inbox: tokio::sync::mpsc::UnboundedSender<ServerCommand>) -> JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            if inbox.send(ServerCommand::PullRequestWatchTick).is_err() {
                break;
            }
            tokio::time::sleep(Duration::from_secs(30)).await;
        }
    })
}

impl ServerActor {
    pub(super) async fn poll_pull_request_watches(&mut self) {
        let watches = match self.runtime_store.list_pull_request_watches().await {
            Ok(watches) => watches,
            Err(error) => {
                tracing::warn!("could not load pull request watches: {error}");
                return;
            }
        };
        self.pull_request_watches.active = !watches.is_empty();
        for id in self
            .pull_request_watches
            .jobs
            .keys()
            .cloned()
            .collect::<Vec<_>>()
        {
            if !watches.iter().any(|w| w.workspace_id == id) {
                self.pull_request_watches.cancel(&id);
            }
        }
        self.schedule_shutdown_if_idle();
        for watch in watches {
            if self
                .pull_request_watches
                .jobs
                .contains_key(&watch.workspace_id)
            {
                continue;
            }
            let store = self.runtime_store.clone();
            let links = self.host_links.clone();
            let inbox = self.inbox.clone();
            let id = watch.workspace_id.clone();
            let generation = Uuid::new_v4();
            let polls = self.pull_request_watches.polls.clone();
            let job = tokio::spawn(async move {
                let Ok(_permit) = polls.acquire_owned().await else {
                    return;
                };
                // A remote checkout is read on its own host: `gh` and the
                // repository are there, not here.
                let result = super::remote_pull_request_routing::snapshot_for_workspace(
                    &store,
                    &links,
                    &watch.workspace_id,
                )
                .await;
                let _ = inbox.send(ServerCommand::PullRequestWatchSnapshot {
                    watch: Box::new(watch),
                    generation,
                    result,
                });
            });
            self.pull_request_watches.jobs.insert(id, (generation, job));
        }
    }

    pub(super) async fn finish_pull_request_watch_snapshot(
        &mut self,
        mut watch: PullRequestWatch,
        generation: Uuid,
        result: HostResult<Value>,
    ) {
        if !self.watch_job_current(&watch.workspace_id, generation) {
            return;
        }
        self.pull_request_watches.jobs.remove(&watch.workspace_id);
        // A start/stop or another client update invalidates the entire in-flight evaluation.
        if !self
            .runtime_store
            .find_pull_request_watch(&watch.workspace_id)
            .await
            .is_ok_and(|current| current.as_ref() == Some(&watch))
        {
            return;
        }
        let snapshot = match result {
            Ok(snapshot) => snapshot,
            Err(error) => {
                tracing::warn!(workspace_id = %watch.workspace_id, "pull request watch poll failed: {}", error.wire_message());
                return;
            }
        };
        match evaluate(&watch, &snapshot) {
            Evaluation::Wait => {}
            Evaluation::Stop => {
                if self
                    .runtime_store
                    .remove_pull_request_watch(&watch.workspace_id)
                    .await
                    .is_ok()
                {
                    self.broadcast_pull_request_watch_changed(Some(&watch.workspace_id));
                }
            }
            Evaluation::Dispatch { mark, prompt } => {
                match self.dispatch_pull_request_watch(&mut watch, &prompt).await {
                    Ok(true) => {
                        watch.last_dispatch = Some(mark);
                        self.save_runtime_watch(watch).await;
                    }
                    Ok(false) => {}
                    Err(error) => {
                        tracing::warn!(workspace_id = %watch.workspace_id, "pull request watch dispatch failed: {}", error.wire_message())
                    }
                }
            }
            Evaluation::Merge { head, method } => {
                let store = self.runtime_store.clone();
                let links = self.host_links.clone();
                let inbox = self.inbox.clone();
                let id = watch.workspace_id.clone();
                let job = tokio::spawn(async move {
                    let result = merge(&store, &links, &watch, &snapshot, &head, &method).await;
                    let _ = inbox.send(ServerCommand::PullRequestWatchMerged {
                        watch: Box::new(watch),
                        generation,
                        result,
                    });
                });
                self.pull_request_watches.jobs.insert(id, (generation, job));
            }
        }
    }

    pub(super) async fn finish_pull_request_watch_merge(
        &mut self,
        mut watch: PullRequestWatch,
        generation: Uuid,
        result: HostResult<String>,
    ) {
        if !self.watch_job_current(&watch.workspace_id, generation) {
            return;
        }
        self.pull_request_watches.jobs.remove(&watch.workspace_id);
        match result {
            Ok(head) => {
                if self
                    .runtime_store
                    .find_pull_request_watch(&watch.workspace_id)
                    .await
                    .is_ok_and(|current| current.as_ref() == Some(&watch))
                {
                    // GitHub may only have queued the merge. Keep watching until a snapshot confirms it.
                    watch.last_merged_head_sha = Some(head);
                    self.broadcast_authenticated(crate::terminal_host::protocol::event(
                        "linkedReviewsChanged",
                        json!({"workspaceId": watch.workspace_id}),
                    ));
                    self.save_runtime_watch(watch).await;
                    let _ = self.inbox.send(ServerCommand::PullRequestWatchTick);
                }
            }
            Err(error) => {
                tracing::warn!(workspace_id = %watch.workspace_id, "pull request watch merge failed: {}", error.wire_message())
            }
        }
    }

    fn watch_job_current(&self, workspace_id: &str, generation: Uuid) -> bool {
        self.pull_request_watches
            .jobs
            .get(workspace_id)
            .is_some_and(|(current, _)| *current == generation)
    }

    async fn save_runtime_watch(&self, watch: PullRequestWatch) {
        match self.runtime_store.upsert_pull_request_watch(watch).await {
            Ok(watch) => self.broadcast_pull_request_watch_changed(Some(&watch.workspace_id)),
            Err(error) => tracing::warn!("could not persist pull request watch progress: {error}"),
        }
    }

    async fn dispatch_pull_request_watch(
        &mut self,
        watch: &mut PullRequestWatch,
        prompt: &str,
    ) -> HostResult<bool> {
        if let Some(tab_id) = &watch.tab_id {
            let tab = self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(|e| HostError::state(e.to_string()))?;
            if let Some(tab) = tab.filter(|tab| tab.workspace_id == watch.workspace_id) {
                if let Some(session_id) = terminal_session_id_from_tab(&tab)
                    .filter(|id| self.sessions.get(id).is_some_and(|s| s.running()))
                {
                    if !self.agent_presence.is_injection_ready(&session_id) {
                        return Ok(false);
                    }
                    self.queue_orchestration_paste(&session_id, prompt, Vec::new(), true)?;
                    return Ok(true);
                }
            }
        }
        let profile = watch.profile_id.as_ref().ok_or_else(|| {
            HostError::state("The watched agent is unavailable. Choose a running agent or profile.")
        })?;
        let result = self
            .launch_agent_profile(
                None,
                &json!({"workspaceId": watch.workspace_id, "profileId": profile, "prompt": prompt}),
            )
            .await?;
        watch.tab_id = result["tab"]["id"]
            .as_str()
            .or(result["tabId"].as_str())
            .map(str::to_string);
        Ok(true)
    }
}

async fn merge(
    store: &alera_core::runtime::RuntimeStore,
    links: &crate::terminal_host::host_link_registry::HostLinkRegistry,
    watch: &PullRequestWatch,
    snapshot: &Value,
    head: &str,
    method: &str,
) -> HostResult<String> {
    let _guard = super::mobile_pull_request_busy::BusyGuard::acquire(&watch.workspace_id)?;
    let workspace = store
        .find_workspace(&watch.workspace_id)
        .await
        .map_err(|e| HostError::state(e.to_string()))?
        .ok_or_else(|| HostError::state("Workspace disappeared."))?;
    let identity = snapshot["remoteUrl"]
        .as_str()
        .and_then(super::mobile_pull_request_identity::parse_github_identity)
        .ok_or_else(|| HostError::state("GitHub remote unavailable."))?;
    let flag = match method {
        "squash" => "--squash",
        "rebase" => "--rebase",
        _ => "--merge",
    };
    let (code, _, stderr) = super::remote_pull_request_routing::run_gh_for_workspace(
        store,
        links,
        &workspace,
        &[
            "pr",
            "merge",
            &watch.review_number.to_string(),
            "--repo",
            &identity.slug,
            flag,
            "--match-head-commit",
            head,
        ],
    )
    .await?;
    if code != 0 {
        return Err(HostError::state(stderr));
    }
    Ok(head.to_string())
}

#[cfg(test)]
mod tests {
    use super::super::actor_test_harness::test_actor;
    use super::*;
    use alera_core::runtime::{Project, ProjectKind};
    use chrono::Utc;

    async fn setup() -> (tempfile::TempDir, ServerActor, PullRequestWatch) {
        let dir = tempfile::tempdir().unwrap();
        let actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        let now = Utc::now();
        actor
            .runtime_store
            .upsert_project(Project {
                id: "p".into(),
                name: "Project".into(),
                repo_path: "/p".into(),
                kind: ProjectKind::GitRepository,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();
        actor.runtime_store.upsert_workspace(serde_json::from_value(json!({"id":"w","instanceId":"i","hostId":"local","projectId":"p","name":"Workspace","path":"/p","createdAt":now,"updatedAt":now,"kind":"linked","status":"active","reusesExistingBranch":false})).unwrap()).await.unwrap();
        let watch: PullRequestWatch = serde_json::from_value(json!({"workspaceId":"w","reviewNumber":42,"mode":"fix","checks":true,"comments":true,"conflicts":true,"tabId":"t"})).unwrap();
        actor
            .runtime_store
            .upsert_pull_request_watch(watch.clone())
            .await
            .unwrap();
        (dir, actor, watch)
    }

    fn job(actor: &mut ServerActor) -> Uuid {
        let id = Uuid::new_v4();
        actor
            .pull_request_watches
            .jobs
            .insert("w".into(), (id, tokio::spawn(async {})));
        id
    }

    #[tokio::test]
    async fn runtime_stops_closed_watch_without_any_connected_ui() {
        let (_dir, mut actor, watch) = setup().await;
        let generation = job(&mut actor);
        actor.finish_pull_request_watch_snapshot(watch, generation, Ok(json!({"provider":"github","authStatus":"authenticated","review":{"number":42,"state":"CLOSED"}}))).await;
        assert!(actor
            .runtime_store
            .find_pull_request_watch("w")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn stopped_or_replaced_watch_ignores_late_snapshot() {
        let (_dir, mut actor, watch) = setup().await;
        let stale = job(&mut actor);
        actor.pull_request_watches.cancel("w");
        let current = job(&mut actor);
        actor
            .finish_pull_request_watch_snapshot(
                watch.clone(),
                stale,
                Ok(json!({"provider":"github","authStatus":"authenticated","review":null})),
            )
            .await;
        assert_eq!(
            actor
                .runtime_store
                .find_pull_request_watch("w")
                .await
                .unwrap(),
            Some(watch.clone())
        );
        assert!(actor.watch_job_current("w", current));
        actor
            .runtime_store
            .remove_pull_request_watch("w")
            .await
            .unwrap();
        actor.finish_pull_request_watch_snapshot(watch, current, Ok(json!({"provider":"github","authStatus":"authenticated","review":{"number":42,"state":"OPEN","checks":[{"bucket":"fail"}]}}))).await;
        assert!(actor
            .runtime_store
            .find_pull_request_watch("w")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn failed_poll_keeps_durable_watch_for_retry() {
        let (_dir, mut actor, watch) = setup().await;
        let generation = job(&mut actor);
        actor
            .finish_pull_request_watch_snapshot(
                watch.clone(),
                generation,
                Err(HostError::state("offline")),
            )
            .await;
        assert_eq!(
            actor
                .runtime_store
                .find_pull_request_watch("w")
                .await
                .unwrap(),
            Some(watch)
        );
        assert!(actor.pull_request_watches.jobs.is_empty());
    }

    #[tokio::test]
    async fn queued_merge_keeps_watch_until_snapshot_confirms_merge() {
        let (_dir, mut actor, watch) = setup().await;
        let generation = job(&mut actor);
        actor
            .finish_pull_request_watch_merge(watch, generation, Ok("abc".into()))
            .await;
        let saved = actor
            .runtime_store
            .find_pull_request_watch("w")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(saved.last_merged_head_sha.as_deref(), Some("abc"));
        let generation = job(&mut actor);
        actor.finish_pull_request_watch_snapshot(saved, generation, Ok(json!({"provider":"github", "authStatus":"authenticated", "review":{"number":42,"state":"MERGED"}}))).await;
        assert!(actor
            .runtime_store
            .find_pull_request_watch("w")
            .await
            .unwrap()
            .is_none());
    }
}
