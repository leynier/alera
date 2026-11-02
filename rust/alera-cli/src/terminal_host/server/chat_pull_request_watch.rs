//! Runs the pull request watches of agent chats on the 30 s watch tick
//! (`chatOrchestrationPullRequestsV1`). Each watched pull request is read in
//! its chat's workspace repository; a change is delivered into the chat as a
//! message with `origin.kind = pullRequestWatch`.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use alera_core::runtime::{AgentChatPullRequest, RuntimeStore};
use serde_json::{json, Value};

use super::agent_chat_runtime::commands::{CallerCtx, SendInput};
use super::agent_chat_runtime::AgentChatRuntime;
use super::chat_orchestration::pull_requests::parse_pull_request_url;
use super::chat_pull_request_notices::step;
use super::ServerActor;

impl ServerActor {
    /// Starts one pass over the watched chat pull requests unless one runs.
    pub(super) fn poll_chat_pull_request_watches(&mut self, running: &Arc<AtomicBool>) {
        let Some(runtime) = self.agent_chat_runtime.clone() else {
            return;
        };
        if running.swap(true, Ordering::AcqRel) {
            return;
        }
        let store = self.runtime_store.clone();
        let running = running.clone();
        tokio::spawn(async move {
            poll(&store, &runtime).await;
            running.store(false, Ordering::Release);
        });
    }
}

async fn poll(store: &RuntimeStore, runtime: &AgentChatRuntime) {
    let rows = match store.list_watched_agent_chat_pull_requests().await {
        Ok(rows) => rows,
        Err(error) => {
            tracing::warn!("could not load chat pull request watches: {error}");
            return;
        }
    };
    for row in rows {
        if let Err(error) = poll_one(store, runtime, &row).await {
            tracing::warn!(chat_id = %row.chat_id, "chat pull request watch failed: {error}");
        }
    }
}

/// The watched review, or `Err` when it could not be read as that pull
/// request (another repository's review of the same number reads as a
/// failure).
async fn read(
    store: &RuntimeStore,
    workspace_id: &str,
    row: &AgentChatPullRequest,
) -> Result<Value, ()> {
    let workspace = store
        .find_workspace(workspace_id)
        .await
        .ok()
        .flatten()
        .ok_or(())?;
    let snapshot = super::pull_request_forges::load_review_snapshot(store, &workspace, row.number)
        .await
        .map_err(|_| ())?;
    if let Some(url) = snapshot["review"]["url"].as_str() {
        if parse_pull_request_url(url)
            .ok()
            .map(|parsed| parsed.url)
            .as_ref()
            != Some(&row.url)
        {
            return Err(());
        }
    }
    Ok(snapshot)
}

async fn poll_one(
    store: &RuntimeStore,
    runtime: &AgentChatRuntime,
    row: &AgentChatPullRequest,
) -> anyhow::Result<()> {
    let chat = runtime
        .snapshot(&row.chat_id)
        .await
        .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
    if chat["archived"] == true {
        return Ok(());
    }
    let workspace_id = chat["workspaceId"].as_str().unwrap_or_default().to_owned();
    let snapshot = read(store, &workspace_id, row).await;
    let state = row.watch_state.clone().unwrap_or_else(|| json!({}));
    let next = step(
        row.number,
        &row.url,
        &state,
        snapshot.as_ref().map_err(|_| ()),
    );
    // An unwatch while the read ran wins over this step.
    let current = store
        .agent_chat_pull_request(&row.chat_id, &row.url)
        .await?;
    if !current.is_some_and(|current| current.watching) {
        return Ok(());
    }
    store
        .set_agent_chat_pull_request_watch(&row.chat_id, &row.url, !next.stop, Some(&next.state))
        .await?;
    if let Some(notice) = next.notice {
        runtime
            .send(
                &row.chat_id,
                SendInput {
                    client_message_id: format!("pull-request-watch:{}", uuid::Uuid::new_v4()),
                    text: notice,
                    attachments: Vec::new(),
                    delivery: "queue".into(),
                    model: None,
                    reasoning_effort: None,
                    interaction_mode: None,
                    runtime_mode_ceiling: None,
                    origin: Some(json!({
                        "kind": "pullRequestWatch",
                        "url": row.url,
                        "number": row.number,
                    })),
                },
                CallerCtx::runtime(),
            )
            .await
            .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
    }
    Ok(())
}
