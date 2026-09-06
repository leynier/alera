//! Complete native history is read off the actor; only validated results mutate runtime state.

use super::codex_app_server::CodexAppServer;
use super::codex_history_actions::read_turns;
use super::codex_state::{active_turn_id, snapshot, tab_thread_id};
use super::codex_thread_identity::ensure_expected_thread;
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};
use serde_json::{json, Value};
use std::sync::Arc;

#[derive(Clone)]
pub(crate) struct CodexHistoryScan {
    pub(super) metadata: Value,
    pub(super) turns: Arc<Vec<Value>>,
}

pub(crate) struct CodexHistoryScanJob {
    client: Option<(u64, i64)>,
    request_type: String,
    payload: Value,
    tab_id: String,
    thread_id: String,
    queue_revision: u64,
    history_revision: u64,
    source_snapshot: Option<Value>,
    server_instance: Arc<()>,
}

async fn scan_history(
    server: &CodexAppServer,
    thread_id: &str,
    metadata: bool,
) -> HostResult<CodexHistoryScan> {
    let metadata = if metadata {
        server
            .request("thread/read", json!({"threadId":thread_id}))
            .await?
    } else {
        Value::Null
    };
    let turns = if metadata
        .pointer("/thread/historyMode")
        .and_then(Value::as_str)
        == Some("paginated")
    {
        Vec::new()
    } else {
        read_turns(server, thread_id).await?
    };
    Ok(CodexHistoryScan {
        metadata,
        turns: Arc::new(turns),
    })
}

pub(super) async fn scanned_history(
    server: &CodexAppServer,
    thread_id: &str,
    scan: Option<&CodexHistoryScan>,
    metadata: bool,
) -> HostResult<CodexHistoryScan> {
    if let Some(scan) = scan {
        return Ok(scan.clone());
    }
    #[cfg(test)]
    {
        scan_history(server, thread_id, metadata).await
    }
    #[cfg(not(test))]
    {
        let _ = (server, thread_id, metadata);
        Err(HostError::state(
            "A deferred native history scan is required.",
        ))
    }
}

impl ServerActor {
    pub(super) async fn try_start_codex_history_scan(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !matches!(
            request_type,
            "codex.thread.fork" | "codex.thread.edit" | "codex.queue.reconcile"
        ) {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        self.require_codex_client(client_id)?;
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        ensure_expected_thread(payload, tab_thread_id(&tab).as_deref())?;
        let state = self.codex_delivery_state(&tab).await?;
        if request_type == "codex.queue.reconcile" {
            if state.thread_id.is_empty() {
                return Ok(false);
            }
            if state.history_locked() {
                return Err(HostError::state("The conversation is being edited."));
            }
            super::codex_queue::ensure_queue_revision(&state, payload)?;
        } else {
            let id = require_string_key(payload, "operationId")?;
            if let Some(op) = state.operations.iter().find(|op| op.id == id) {
                let needs_scan = if request_type == "codex.thread.fork" {
                    op.kind == "fork" && op.phase == "failed"
                } else {
                    op.kind == "edit" && op.phase == "uncertain"
                };
                if request_type == "codex.thread.fork"
                    && op.kind == "fork"
                    && op.phase == "forkCreated"
                {
                    if let Some(value) = self
                        .defer_codex_fork(Some((client_id, request_id)), payload, None)
                        .await?
                    {
                        self.client_write(client_id, ok_response(request_id, value));
                    }
                    return Ok(true);
                }
                if !needs_scan {
                    return Ok(false);
                }
            } else if state.history_locked() {
                return Err(HostError::state(
                    "Another history operation is in progress.",
                ));
            }
        }
        self.start_codex_history_scan(Some((client_id, request_id)), request_type, payload.clone())
            .await?;
        Ok(true)
    }

    pub(super) async fn start_codex_history_scan(
        &mut self,
        client: Option<(u64, i64)>,
        request_type: &str,
        payload: Value,
    ) -> HostResult<()> {
        let tab_id = require_string_key(&payload, "tabId")?;
        if self.codex_history_scans.contains(&tab_id) {
            return Err(HostError::state(
                "A history scan is already in progress for this conversation.",
            ));
        }
        self.handle_codex_force_flush(&tab_id).await;
        let tab = self.codex_tab(&tab_id).await?;
        let state = self.codex_delivery_state(&tab).await?;
        let server = self
            .ensure_codex_server(super::codex_tab_lifecycle::active_cwd(&tab).as_deref())
            .await?;
        let metadata = request_type == "codex.thread.edit"
            && !state
                .operations
                .iter()
                .any(|op| Some(op.id.as_str()) == payload["operationId"].as_str());
        let job = CodexHistoryScanJob {
            client,
            request_type: request_type.into(),
            payload,
            tab_id: tab_id.clone(),
            thread_id: state.thread_id,
            queue_revision: state.revision,
            history_revision: state.history_revision,
            // Snapshots are bounded to 512 KiB. Compare live state only for replacements;
            // forks and initial edit validation may safely outlive streaming progress.
            source_snapshot: (request_type != "codex.thread.fork" && !metadata)
                .then(|| snapshot(&tab)),
            server_instance: server.instance_token(),
        };
        self.codex_history_scans.insert(tab_id.clone());
        self.codex_delivery_active.insert(tab_id);
        self.schedule_shutdown_if_idle();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = tokio::time::timeout(
                std::time::Duration::from_secs(90),
                scan_history(&server, &job.thread_id, metadata),
            )
            .await
            .unwrap_or_else(|_| {
                Err(HostError::state(
                    "Native history scan timed out. No history action was applied.",
                ))
            });
            let _ = inbox.send(ServerCommand::CodexHistoryScanFinished {
                job: Box::new(job),
                result,
            });
        });
        Ok(())
    }

    pub(super) async fn finish_codex_history_scan(
        &mut self,
        job: CodexHistoryScanJob,
        result: HostResult<CodexHistoryScan>,
    ) {
        self.codex_history_scans.remove(&job.tab_id);
        let result = self.apply_codex_history_scan(&job, result).await;
        if let Some((client_id, request_id)) = job.client {
            if let Some(response) = match result {
                Ok(Some(value)) => Some(ok_response(request_id, value)),
                Ok(None) => None,
                Err(error) => Some(error_response(request_id, &error)),
            } {
                self.client_write(client_id, response);
            }
        } else if let Err(error) = result {
            tracing::warn!(
                tab_id = job.tab_id,
                "Codex history recovery scan failed: {error}"
            );
        }
        if let Ok(tab) = self.codex_tab(&job.tab_id).await {
            if let Ok(state) = self.codex_delivery_state(&tab).await {
                self.refresh_codex_delivery_activity(
                    &state,
                    active_turn_id(&snapshot(&tab)).is_some(),
                );
            }
            self.schedule_codex_queue(&job.tab_id);
        } else {
            self.codex_delivery_active.remove(&job.tab_id);
        }
        self.schedule_shutdown_if_idle();
    }

    async fn apply_codex_history_scan(
        &mut self,
        job: &CodexHistoryScanJob,
        result: HostResult<CodexHistoryScan>,
    ) -> HostResult<Option<Value>> {
        // Recovery only reconciles persisted work, which already blocks removal
        // of its owner. Client actions can create work outside a cleanup plan.
        if job.client.is_some() && self.mutation_queue.has_runtime_mutations() {
            return Err(HostError::state(
                "A runtime mutation is in progress. Wait for it to finish and retry.",
            ));
        }
        let scan = result?;
        if job.source_snapshot.is_some() {
            self.handle_codex_force_flush(&job.tab_id).await;
        }
        let tab = self.codex_tab(&job.tab_id).await?;
        let state = self.codex_delivery_state(&tab).await?;
        if tab_thread_id(&tab).as_deref() != Some(&job.thread_id)
            || state.history_revision != job.history_revision
            || state.revision != job.queue_revision
            || job
                .source_snapshot
                .as_ref()
                .is_some_and(|source| *source != snapshot(&tab))
            || !self
                .codex
                .as_ref()
                .is_some_and(|server| server.matches_instance(&job.server_instance))
        {
            return Err(HostError::state(
                "The conversation changed while history was being read. Review it before retrying.",
            ));
        }
        if job.request_type == "codex.thread.fork" {
            return self
                .defer_codex_fork(job.client, &job.payload, Some(&scan))
                .await;
        }
        match job.request_type.as_str() {
            "codex.thread.edit" => {
                self.edit_codex_history_scanned(&job.payload, Some(&scan))
                    .await
            }
            "codex.queue.reconcile" => {
                self.handle_codex_queue_request_scanned(
                    &job.request_type,
                    &job.payload,
                    Some(&scan),
                )
                .await
            }
            "recovery" => {
                if let Some(op) = state
                    .operations
                    .iter()
                    .rev()
                    .find(|op| op.kind == "edit" && op.phase == "uncertain")
                {
                    self.reconcile_codex_history_edit_scanned(&job.tab_id, &op.id, Some(&scan))
                        .await?;
                }
                let current = self
                    .codex_delivery_state(&self.codex_tab(&job.tab_id).await?)
                    .await?;
                if current
                    .messages
                    .iter()
                    .any(|entry| matches!(entry.status.as_str(), "sending" | "uncertain"))
                {
                    self.reconcile_codex_queue_scanned(current, Some(&scan))
                        .await
                } else {
                    Ok(current.snapshot())
                }
            }
            _ => Err(HostError::state("Unknown deferred history action.")),
        }
        .map(Some)
    }
}
