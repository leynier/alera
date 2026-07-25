use std::time::Duration;

use alera_core::runtime::{
    NewOrchestrationMessage, NewOrchestrationTask, OrchestrationCoordinatorStatus,
    OrchestrationDispatchContext, OrchestrationDispatchStatus, OrchestrationGateStatus,
    OrchestrationMessage, OrchestrationMessagePriority, OrchestrationMessageType,
    OrchestrationTaskStatus,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::dispatch_preamble::{
    build_dispatch_bootstrap, build_dispatch_preamble, build_worker_contract,
    parse_allow_stale_base_from_spec, GateResolution, PreambleParams, WorkerKind,
};
use crate::terminal_host::orchestration::group_resolution::{
    is_group_address, resolve_group_address, GroupResolutionTerminal,
};
use crate::terminal_host::orchestration::lifecycle_reconciliation::reconcile_lifecycle_message;
use crate::terminal_host::orchestration::message_formatter::format_messages_for_injection;
use crate::terminal_host::orchestration::message_waiters::{MessageWaiter, WaitKind};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::orchestration_validation::{
    optional_string, parse_message_type, parse_priority, parse_type_filter, prefixed_subject,
    require_string, state_error, wait_timeout_ms,
};
use super::{ServerActor, ServerCommand};

fn context_token_hash(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

fn validate_result_schema(
    result: &serde_json::Map<String, Value>,
    schema_raw: Option<&str>,
) -> HostResult<()> {
    let Some(schema_raw) = schema_raw else {
        return Ok(());
    };
    let schema: Value = serde_json::from_str(schema_raw)
        .map_err(|error| HostError::state(format!("stored result schema is invalid: {error}")))?;
    let validator = jsonschema::validator_for(&schema)
        .map_err(|error| HostError::state(format!("stored result schema is invalid: {error}")))?;
    validator
        .validate(&Value::Object(result.clone()))
        .map_err(|error| HostError::format(format!("result does not match schema: {error}")))
}

fn validate_result_schema_definition(schema_raw: &str) -> HostResult<()> {
    let schema: Value = serde_json::from_str(schema_raw)
        .map_err(|error| HostError::format(format!("result schema is invalid JSON: {error}")))?;
    jsonschema::validator_for(&schema)
        .map(|_| ())
        .map_err(|error| HostError::format(format!("result schema is invalid: {error}")))
}

impl ServerActor {
    fn dispatch_context_path(&self, handle: &str) -> std::path::PathBuf {
        let safe_handle: String = handle
            .chars()
            .map(|value| {
                if value.is_ascii_alphanumeric() || value == '-' || value == '_' {
                    value
                } else {
                    '_'
                }
            })
            .collect();
        self.runtime_dir
            .join("orchestration-contexts")
            .join(format!("{safe_handle}.json"))
    }

    pub(super) fn install_dispatch_context(
        &self,
        handle: &str,
        dispatch_id: &str,
        token: &str,
    ) -> HostResult<()> {
        let path = self.dispatch_context_path(handle);
        let parent = path
            .parent()
            .ok_or_else(|| HostError::state("invalid dispatch context path"))?;
        std::fs::create_dir_all(parent).map_err(|error| HostError::state(error.to_string()))?;
        let bytes = serde_json::to_vec(&json!({ "dispatchId": dispatch_id, "token": token }))
            .map_err(|error| HostError::state(error.to_string()))?;
        #[cfg(unix)]
        {
            use std::io::Write;
            use std::os::unix::fs::OpenOptionsExt;
            let mut file = std::fs::OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .mode(0o600)
                .open(path)
                .map_err(|error| HostError::state(error.to_string()))?;
            file.write_all(&bytes)
                .map_err(|error| HostError::state(error.to_string()))?;
        }
        #[cfg(not(unix))]
        std::fs::write(path, bytes).map_err(|error| HostError::state(error.to_string()))?;
        Ok(())
    }

    pub(super) fn remove_dispatch_context(&self, handle: &str) {
        let _ = std::fs::remove_file(self.dispatch_context_path(handle));
    }

    /// Handles requests; wait-capable verbs return `Ok(None)` until a wake or timeout writes the response.
    pub(super) async fn handle_orchestration_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        self.require_auth(client_id)?;
        match request_type {
            "orchestration.agentSpawn" => self.orchestration_agent_spawn(payload).await.map(Some),
            "orchestration.agentSpawnTimeout" => self
                .orchestration_agent_spawn_timeout(payload)
                .await
                .map(Some),
            "orchestration.runPolicyPropose" => self
                .orchestration_run_policy_propose(payload)
                .await
                .map(Some),
            "orchestration.runPolicyShow" => {
                self.orchestration_run_policy_show(payload).await.map(Some)
            }
            "orchestration.runPolicyApprove" => self
                .orchestration_run_policy_resolve(payload, true)
                .await
                .map(Some),
            "orchestration.runPolicyReject" => self
                .orchestration_run_policy_resolve(payload, false)
                .await
                .map(Some),
            "orchestration.send" => self.orchestration_send(payload).await.map(Some),
            "orchestration.check" => {
                self.orchestration_check(client_id, request_id, payload)
                    .await
            }
            "orchestration.reply" => self.orchestration_reply(payload).await.map(Some),
            "orchestration.inbox" => self.orchestration_inbox(payload).await.map(Some),
            "orchestration.ask" => self.orchestration_ask(client_id, request_id, payload).await,
            "orchestration.agentStatus" => self.orchestration_agent_status(payload).await.map(Some),
            "orchestration.terminals" => Ok(Some(self.orchestration_terminals(payload))),
            "orchestration.terminalShow" => {
                self.orchestration_terminal_show(payload).await.map(Some)
            }
            "orchestration.terminalPrune" => {
                self.orchestration_terminal_prune(payload).await.map(Some)
            }
            "orchestration.terminalWait" => {
                self.orchestration_terminal_wait(client_id, request_id, payload)
                    .await
            }
            "orchestration.taskWait" => {
                self.orchestration_task_wait(client_id, request_id, payload)
                    .await
            }
            "orchestration.taskCreate" => self.orchestration_task_create(payload).await.map(Some),
            "orchestration.taskList" => self.orchestration_task_list(payload).await.map(Some),
            "orchestration.taskShow" => self.orchestration_task_show(payload).await.map(Some),
            "orchestration.taskCancel" => self.orchestration_task_cancel(payload).await.map(Some),
            "orchestration.taskRecover" => self.orchestration_task_recover(payload).await.map(Some),
            "orchestration.transferCoordinator" => self
                .orchestration_transfer_coordinator(payload)
                .await
                .map(Some),
            "orchestration.dispatch" => self.orchestration_dispatch(payload).await.map(Some),
            "orchestration.dispatchShow" => {
                self.orchestration_dispatch_show(payload).await.map(Some)
            }
            "orchestration.dispatchAccept" => {
                self.orchestration_dispatch_accept(payload).await.map(Some)
            }
            "orchestration.dispatchInterrupt" => self
                .orchestration_dispatch_interrupt(payload)
                .await
                .map(Some),
            "orchestration.context" => self.orchestration_context(payload).await.map(Some),
            "orchestration.heartbeat" => self.orchestration_heartbeat(payload).await.map(Some),
            "orchestration.escalate" => self.orchestration_escalate(payload).await.map(Some),
            "orchestration.complete" => self.orchestration_complete(payload).await.map(Some),
            "orchestration.workerDone" => self.orchestration_worker_done(payload).await.map(Some),
            "orchestration.workerHelp" => Ok(Some(self.orchestration_worker_help())),
            "orchestration.gateCreate" => self.orchestration_gate_create(payload).await.map(Some),
            "orchestration.gateResolve" => self.orchestration_gate_resolve(payload).await.map(Some),
            "orchestration.gateList" => self.orchestration_gate_list(payload).await.map(Some),
            "orchestration.run" => self.orchestration_run(payload).await.map(Some),
            "orchestration.runList" => self.orchestration_run_list(payload).await.map(Some),
            "orchestration.runShow" => self.orchestration_run_show(payload).await.map(Some),
            "orchestration.status" => self.orchestration_status(payload).await.map(Some),
            "orchestration.runStop" => self.orchestration_run_stop(payload).await.map(Some),
            "orchestration.reset" => self.orchestration_reset(payload).await.map(Some),
            other => Err(HostError::state(format!(
                "Unknown orchestration request: {other}"
            ))),
        }
    }

    // --- send -------------------------------------------------------------

    async fn orchestration_send(&mut self, payload: &Value) -> HostResult<Value> {
        let from_handle = require_string(payload, "from")?;
        let to = require_string(payload, "to")?;
        let subject = require_string(payload, "subject")?;
        let body = optional_string(payload, "body").unwrap_or_default();
        let message_type = parse_message_type(payload)?;
        let priority = parse_priority(payload)?;
        let message_payload = optional_string(payload, "payload");
        let explicit_thread_id = optional_string(payload, "threadId");

        if message_type.is_lifecycle() {
            return Err(HostError::state(format!(
                "{} is a lifecycle operation; use heartbeat or complete instead",
                message_type.as_str()
            )));
        }

        if message_type.is_lifecycle() && is_group_address(&to) {
            return Err(HostError::state(format!(
                "{} messages cannot be sent to a group address",
                message_type.as_str()
            )));
        }

        let recipients = resolve_group_address(
            &to,
            &from_handle,
            &self.group_resolution_terminals(),
            &self.agent_presence,
        );
        if recipients.is_empty() {
            return Err(HostError::state(format!("No recipients resolved for {to}")));
        }

        // Group fan-out shares a thread id so replies converge.
        let thread_id = if recipients.len() > 1 {
            explicit_thread_id.or_else(|| Some(generated_group_thread_id()))
        } else {
            explicit_thread_id
        };

        let mut inserted = Vec::new();
        for recipient in &recipients {
            let message = self
                .runtime_store
                .insert_orchestration_message(NewOrchestrationMessage {
                    from_handle: from_handle.clone(),
                    to_handle: recipient.clone(),
                    subject: subject.clone(),
                    body: body.clone(),
                    message_type,
                    priority,
                    thread_id: thread_id.clone(),
                    payload: message_payload.clone(),
                    run_id: optional_string(payload, "runId"),
                    workspace_id: optional_string(payload, "workspaceId"),
                    task_id: optional_string(payload, "taskId"),
                    dispatch_id: optional_string(payload, "dispatchId"),
                    expires_at: optional_string(payload, "expiresAt"),
                })
                .await
                .map_err(state_error)?;
            inserted.push(message);
        }

        // Lifecycle messages reconcile BEFORE waking waiters so the dispatch
        // lock is released by the time the coordinator reads the result.
        if message_type.is_lifecycle() {
            for message in &inserted {
                let mut log = |line: String| eprintln!("[orchestration] {line}");
                let _ = reconcile_lifecycle_message(&self.runtime_store, message, &mut log).await;
            }
        }

        for recipient in &recipients {
            self.deliver_pending_messages_if_idle(recipient).await;
            self.notify_message_arrived(recipient, message_type).await;
        }
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "orchestrationMessagesChanged",
            json!({}),
        ));

        Ok(json!({
            "messages": inserted,
            "recipients": recipients,
        }))
    }

    // --- check ------------------------------------------------------------

    async fn orchestration_check(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let handle = require_string(payload, "terminal")?;
        let all = payload.get("all").and_then(Value::as_bool).unwrap_or(false);
        let wait = payload
            .get("wait")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let inject = payload
            .get("inject")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let type_filter = parse_type_filter(payload)?;

        if all {
            // `--all` is a read-only view: never marks read, never waits.
            let limit = payload.get("limit").and_then(Value::as_i64).unwrap_or(100);
            let filter = if type_filter.is_empty() {
                None
            } else {
                Some(type_filter.as_slice())
            };
            let messages = self
                .runtime_store
                .all_orchestration_messages_for_handle(&handle, filter, limit)
                .await
                .map_err(state_error)?;
            return Ok(Some(check_response(&messages, inject)));
        }

        let messages = self.consume_unread_messages(&handle, &type_filter).await?;
        if !messages.is_empty() || !wait {
            return Ok(Some(check_response(&messages, inject)));
        }

        // Nothing unread and the caller asked to wait: park the request.
        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            handle,
            WaitKind::Check {
                type_filter,
                inject,
            },
        );
        self.spawn_wait_timeout(waiter_id, wait_timeout_ms(payload));
        Ok(None)
    }

    /// Reads unread messages (optionally filtered), reconciles lifecycle
    /// messages inline, and marks them read.
    async fn consume_unread_messages(
        &mut self,
        handle: &str,
        type_filter: &[OrchestrationMessageType],
    ) -> HostResult<Vec<OrchestrationMessage>> {
        let filter = if type_filter.is_empty() {
            None
        } else {
            Some(type_filter)
        };
        let messages = self
            .runtime_store
            .unread_orchestration_messages(handle, filter)
            .await
            .map_err(state_error)?;
        if messages.is_empty() {
            return Ok(messages);
        }
        for message in &messages {
            if message.message_type.is_lifecycle() {
                let mut log = |line: String| eprintln!("[orchestration] {line}");
                let _ = reconcile_lifecycle_message(&self.runtime_store, message, &mut log).await;
            }
        }
        let ids: Vec<String> = messages.iter().map(|message| message.id.clone()).collect();
        self.runtime_store
            .mark_orchestration_messages_read(&ids)
            .await
            .map_err(state_error)?;
        Ok(messages)
    }

    // --- reply ------------------------------------------------------------

    async fn orchestration_reply(&mut self, payload: &Value) -> HostResult<Value> {
        let message_id = require_string(payload, "id")?;
        let body = require_string(payload, "body")?;
        let original = self
            .runtime_store
            .orchestration_message_by_id(&message_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("message not found: {message_id}")))?;
        self.runtime_store
            .mark_orchestration_messages_read(std::slice::from_ref(&original.id))
            .await
            .map_err(state_error)?;
        let reply = self
            .runtime_store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: original.to_handle.clone(),
                to_handle: original.from_handle.clone(),
                subject: prefixed_subject("Re: ", &original.subject),
                body,
                message_type: OrchestrationMessageType::Status,
                priority: OrchestrationMessagePriority::Normal,
                thread_id: original
                    .thread_id
                    .clone()
                    .or_else(|| Some(original.id.clone())),
                payload: None,
                run_id: original.run_id.clone(),
                workspace_id: original.workspace_id.clone(),
                task_id: original.task_id.clone(),
                dispatch_id: original.dispatch_id.clone(),
                expires_at: None,
            })
            .await
            .map_err(state_error)?;
        let recipient = reply.to_handle.clone();
        self.deliver_pending_messages_if_idle(&recipient).await;
        self.notify_message_arrived(&recipient, OrchestrationMessageType::Status)
            .await;
        Ok(json!(reply))
    }

    // --- inbox ------------------------------------------------------------

    async fn orchestration_inbox(&mut self, payload: &Value) -> HostResult<Value> {
        let limit = payload.get("limit").and_then(Value::as_i64).unwrap_or(50);
        let direction =
            optional_string(payload, "direction").unwrap_or_else(|| "inbox".to_string());
        let terminal_filter = optional_string(payload, "terminal");
        let messages = match (terminal_filter.clone(), direction.as_str()) {
            (Some(handle), "outbox") => self
                .runtime_store
                .all_orchestration_messages_from_handle(&handle, limit)
                .await
                .map_err(state_error)?,
            (Some(handle), _) => self
                .runtime_store
                .all_orchestration_messages_for_handle(&handle, None, limit)
                .await
                .map_err(state_error)?,
            (None, "outbox") => {
                return Err(HostError::format("--terminal is required for outbox."))
            }
            (None, _) => self
                .runtime_store
                .orchestration_inbox(limit)
                .await
                .map_err(state_error)?,
        };
        Ok(
            json!({ "kind": "messages", "items": messages, "messages": messages, "filters": { "terminal": terminal_filter, "direction": direction } }),
        )
    }

    // --- ask --------------------------------------------------------------

    async fn orchestration_ask(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let from_handle = require_string(payload, "from")?;
        let requested_to = require_string(payload, "to")?;
        let active_dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(&from_handle)
            .await
            .map_err(state_error)?;
        let to = active_dispatch
            .as_ref()
            .map(|dispatch| dispatch.coordinator_handle.clone())
            .unwrap_or(requested_to);
        if is_group_address(&to) {
            return Err(HostError::state(
                "ask requires a single terminal handle, not a group address",
            ));
        }
        let question = require_string(payload, "question")?;
        let options = optional_string(payload, "options");
        let body = match &options {
            Some(options) => format!("{question}\nOptions: {options}"),
            None => question.clone(),
        };
        let message = self
            .runtime_store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: from_handle.clone(),
                to_handle: to.clone(),
                subject: format!("Question: {question}"),
                body,
                message_type: OrchestrationMessageType::DecisionGate,
                priority: OrchestrationMessagePriority::High,
                thread_id: None,
                payload: None,
                run_id: active_dispatch
                    .as_ref()
                    .and_then(|dispatch| dispatch.run_id.clone())
                    .or_else(|| optional_string(payload, "runId")),
                workspace_id: active_dispatch
                    .as_ref()
                    .map(|dispatch| dispatch.workspace_id.clone())
                    .or_else(|| optional_string(payload, "workspaceId")),
                task_id: active_dispatch
                    .as_ref()
                    .map(|dispatch| dispatch.task_id.clone())
                    .or_else(|| optional_string(payload, "taskId")),
                dispatch_id: active_dispatch
                    .as_ref()
                    .map(|dispatch| dispatch.id.clone())
                    .or_else(|| optional_string(payload, "dispatchId")),
                expires_at: optional_string(payload, "expiresAt"),
            })
            .await
            .map_err(state_error)?;
        // The question is its own thread root: replies inherit thread_id =
        // message id via `reply`.
        self.deliver_pending_messages_if_idle(&to).await;
        self.notify_message_arrived(&to, OrchestrationMessageType::DecisionGate)
            .await;

        let waiter_id = self.orchestration_waiters.register(
            client_id,
            request_id,
            from_handle,
            WaitKind::Ask {
                thread_id: message.id.clone(),
                after_sequence: message.sequence,
            },
        );
        self.spawn_wait_timeout(waiter_id, wait_timeout_ms(payload));
        Ok(None)
    }

    // --- agent status forwarding -------------------------------------------

    pub(super) async fn orchestration_agent_status(
        &mut self,
        payload: &Value,
    ) -> HostResult<Value> {
        let Some(entries) = payload.get("entries").and_then(Value::as_array) else {
            return Err(HostError::format("entries must be an array."));
        };
        let mut became_ready = Vec::new();
        for entry in entries {
            let Some(handle) = entry
                .get("terminalSessionId")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
            else {
                continue;
            };
            let removed = entry
                .get("removed")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if removed {
                self.cleanup_orchestration_for_closed_session(handle, "agent status was removed")
                    .await;
                continue;
            }
            let Some(state) = entry
                .get("state")
                .and_then(Value::as_str)
                .and_then(AgentPresenceState::parse)
            else {
                continue;
            };
            let agent_type = entry
                .get("agentType")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_string();
            let state_started_at = self.agent_presence_timestamp(entry);
            let previous = self.agent_presence.get(handle);
            let updated_at = entry
                .get("updatedAt")
                .and_then(Value::as_str)
                .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
                .map(|value| value.with_timezone(&chrono::Utc))
                .unwrap_or_else(chrono::Utc::now);
            let presence = AgentPresence {
                agent_type,
                state,
                state_started_at,
                updated_at,
                prompt: entry
                    .get("prompt")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                    .or_else(|| previous.map(|value| value.prompt.clone()))
                    .unwrap_or_default(),
                tool_name: optional_status_string(entry, "toolName")
                    .or_else(|| previous.and_then(|value| value.tool_name.clone())),
                tool_input: optional_status_string(entry, "toolInput")
                    .or_else(|| previous.and_then(|value| value.tool_input.clone())),
                last_assistant_message: optional_status_string(entry, "lastAssistantMessage")
                    .or_else(|| previous.and_then(|value| value.last_assistant_message.clone())),
                interrupted: entry
                    .get("interrupted")
                    .and_then(Value::as_bool)
                    .or_else(|| previous.and_then(|value| value.interrupted)),
            };
            self.agent_presence.update_full(handle, presence);
            if let Ok(Some(dispatch)) = self
                .runtime_store
                .active_orchestration_dispatch_for_handle(handle)
                .await
            {
                let _ = self
                    .runtime_store
                    .record_orchestration_activity(&dispatch.id)
                    .await;
            }
            if state.accepts_injection() {
                became_ready.push(handle.to_string());
            }
        }
        for handle in became_ready {
            self.dispatch_pending_agent_spawn(&handle).await;
            self.deliver_pending_messages(&handle).await;
        }
        self.broadcast_agent_presence_changed();
        Ok(json!({}))
    }

    async fn dispatch_pending_agent_spawn(&mut self, handle: &str) {
        let Some(session) = self.sessions.get(handle) else {
            return;
        };
        let tab_id = session.tab_id.clone();
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&tab_id).await else {
            return;
        };
        let Some(pending) = tab.payload.get("pendingOrchestration").cloned() else {
            return;
        };
        if pending.is_null() {
            return;
        }
        let Some(task) = pending.get("task").and_then(Value::as_str) else {
            return;
        };
        let Some(from) = pending.get("from").and_then(Value::as_str) else {
            return;
        };
        let dispatch_payload = json!({
            "task": task,
            "to": handle,
            "from": from,
            "inject": true,
            "forceSubmit": pending
                .get("agent")
                .and_then(Value::as_str)
                .and_then(adapter_for)
                .is_some_and(|adapter| adapter.force_submit),
            "agentProfile": pending.get("profile").cloned(),
            "agentQuotaGroup": pending.get("quotaGroup").cloned(),
            "completionPolicy": "return-immediately",
            "terminalPolicy": "keep-open",
        });
        if self.orchestration_dispatch(&dispatch_payload).await.is_ok() {
            tab.payload["pendingOrchestration"] = Value::Null;
            tab.updated_at = chrono::Utc::now();
            let workspace_id = tab.workspace_id.clone();
            let _ = self.runtime_store.upsert_workspace_tab(tab).await;
            self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        }
    }

    // --- terminals ---------------------------------------------------------

    pub(super) fn group_resolution_terminals(&self) -> Vec<GroupResolutionTerminal> {
        self.sessions
            .iter()
            .filter(|(_, session)| session.running())
            .map(|(session_id, session)| GroupResolutionTerminal {
                handle: session_id.clone(),
                workspace_id: Some(session.workspace_id.clone()),
            })
            .collect()
    }

    // --- tasks --------------------------------------------------------------

    async fn orchestration_task_create(&mut self, payload: &Value) -> HostResult<Value> {
        let spec = require_string(payload, "spec")?;
        let result_schema = optional_string(payload, "resultSchema");
        if let Some(schema) = result_schema.as_deref() {
            validate_result_schema_definition(schema)?;
        }
        let created_by = optional_string(payload, "createdBy");
        let requested_coordinator = optional_string(payload, "coordinator");
        let workspace_id =
            optional_string(payload, "workspace").unwrap_or_else(|| "global".to_string());
        let run_id = optional_string(payload, "run");
        let coordinator_handle = if let Some(run_id) = run_id.as_deref() {
            let run = self
                .runtime_store
                .orchestration_coordinator_run_by_id(run_id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::state(format!("coordinator run not found: {run_id}")))?;
            if run.status != OrchestrationCoordinatorStatus::Running {
                return Err(HostError::state(format!(
                    "coordinator run is not accepting tasks: {run_id}"
                )));
            }
            if workspace_id != run.workspace_id {
                return Err(HostError::state(format!(
                    "task workspace {workspace_id} does not match run workspace {}",
                    run.workspace_id
                )));
            }
            let run_coordinator = run.coordinator_handle.ok_or_else(|| {
                HostError::state(format!("coordinator run has no owner: {run_id}"))
            })?;
            if requested_coordinator
                .as_deref()
                .is_some_and(|coordinator| coordinator != run_coordinator.as_str())
            {
                return Err(HostError::state(format!(
                    "task coordinator does not match run coordinator {run_coordinator}"
                )));
            }
            run_coordinator
        } else {
            requested_coordinator
                .or_else(|| created_by.clone())
                .unwrap_or_else(|| "coord".to_string())
        };
        let deps: Vec<String> = payload
            .get("deps")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default();
        let task = self
            .runtime_store
            .create_orchestration_task(NewOrchestrationTask {
                spec,
                task_title: optional_string(payload, "taskTitle"),
                display_name: None,
                deps,
                parent_id: optional_string(payload, "parent"),
                created_by_terminal_handle: created_by,
                run_id,
                workspace_id,
                coordinator_handle,
                result_schema,
            })
            .await
            .map_err(state_error)?;
        // Binding the stage after creation keeps `create_orchestration_task`
        // free of policy concerns; the stage is validated against the run's
        // approved plan rather than trusted from the payload.
        if let Some(stage) = optional_string(payload, "stage") {
            self.bind_task_to_policy_stage(&task.id, task.run_id.as_deref(), &stage)
                .await?;
            // Re-read rather than returning task_show: taskCreate always answers
            // with a bare task, and the stage must not change that shape.
            let stored = self
                .runtime_store
                .orchestration_task_by_id(&task.id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| {
                    HostError::state(format!("orchestration task not found: {}", task.id))
                })?;
            return Ok(json!(stored));
        }
        Ok(json!(task))
    }

    async fn orchestration_task_list(&mut self, payload: &Value) -> HostResult<Value> {
        let status = match optional_string(payload, "status") {
            None => None,
            Some(raw) => Some(
                OrchestrationTaskStatus::parse(&raw)
                    .ok_or_else(|| HostError::format(format!("unknown task status: {raw}")))?,
            ),
        };
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(
                status,
                optional_string(payload, "run").as_deref(),
                optional_string(payload, "workspace").as_deref(),
            )
            .await
            .map_err(state_error)?;
        Ok(json!({
            "kind": "tasks",
            "items": tasks,
            "tasks": tasks,
            "filters": {
                "status": optional_string(payload, "status"),
                "run": optional_string(payload, "run"),
                "workspace": optional_string(payload, "workspace"),
            }
        }))
    }

    async fn orchestration_task_show(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let task = self
            .runtime_store
            .orchestration_task_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {id}")))?;
        let dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_task(&id)
            .await
            .map_err(state_error)?;
        Ok(json!({ "task": task, "activeDispatch": dispatch }))
    }

    pub(super) async fn orchestration_task_cancel(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let reason = require_string(payload, "reason")?;
        let actor = optional_string(payload, "actor");
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let existing_task = self
            .runtime_store
            .orchestration_task_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {id}")))?;
        if !force && actor.as_deref() != Some(existing_task.coordinator_handle.as_str()) {
            return Err(HostError::state(format!(
                "only coordinator {} can cancel task {id}; use --force for audited recovery",
                existing_task.coordinator_handle
            )));
        }
        let active = self
            .runtime_store
            .active_orchestration_dispatch_for_task(&id)
            .await
            .map_err(state_error)?;
        let task = self
            .runtime_store
            .cancel_orchestration_task(&id, &reason)
            .await
            .map_err(state_error)?;
        self.runtime_store
            .insert_orchestration_audit_event(
                actor.as_deref(),
                if force {
                    "task.cancel.force"
                } else {
                    "task.cancel"
                },
                &id,
                &reason,
            )
            .await
            .map_err(state_error)?;
        if let Some(dispatch) = active {
            if let Some(assignee) = dispatch.assignee_handle {
                self.remove_dispatch_context(&assignee);
                let message = self
                    .runtime_store
                    .insert_orchestration_message(NewOrchestrationMessage {
                        from_handle: task.coordinator_handle.clone(),
                        to_handle: assignee.clone(),
                        subject: "Task Cancelled".to_string(),
                        body: reason.clone(),
                        message_type: OrchestrationMessageType::Status,
                        priority: OrchestrationMessagePriority::Urgent,
                        thread_id: None,
                        payload: None,
                        run_id: task.run_id.clone(),
                        workspace_id: Some(task.workspace_id.clone()),
                        task_id: Some(task.id.clone()),
                        dispatch_id: Some(dispatch.id),
                        expires_at: None,
                    })
                    .await
                    .map_err(state_error)?;
                if self.agent_presence.is_injection_ready(&assignee) {
                    self.deliver_pending_messages(&assignee).await;
                } else if let Some(agent_type) = self.agent_presence.agent_type(&assignee) {
                    if let Some(adapter) = adapter_for(agent_type) {
                        let _ =
                            self.queue_orchestration_control(&assignee, adapter.interrupt_bytes);
                    }
                }
                return Ok(json!({ "task": task, "cancellationMessage": message }));
            }
        }
        Ok(json!({ "task": task }))
    }

    async fn orchestration_task_recover(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let status_raw = require_string(payload, "status")?;
        let status = OrchestrationTaskStatus::parse(&status_raw)
            .ok_or_else(|| HostError::format(format!("unknown task status: {status_raw}")))?;
        let reason = require_string(payload, "reason")?;
        let actor = optional_string(payload, "actor");
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let existing_task = self
            .runtime_store
            .orchestration_task_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {id}")))?;
        if !force && actor.as_deref() != Some(existing_task.coordinator_handle.as_str()) {
            return Err(HostError::state(format!(
                "only coordinator {} can recover task {id}; use --force for audited recovery",
                existing_task.coordinator_handle
            )));
        }
        let task = self
            .runtime_store
            .recover_stalled_orchestration_task(&id, status, actor.as_deref(), &reason, force)
            .await
            .map_err(state_error)?;
        Ok(json!({ "task": task }))
    }

    async fn orchestration_transfer_coordinator(&mut self, payload: &Value) -> HostResult<Value> {
        let actor = optional_string(payload, "actor")
            .ok_or_else(|| HostError::format("actor is required."))?;
        let to = require_string(payload, "to")?;
        let reason = require_string(payload, "reason")?;
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        match (
            optional_string(payload, "task"),
            optional_string(payload, "run"),
        ) {
            (Some(task_id), None) => {
                let task = self
                    .runtime_store
                    .orchestration_task_by_id(&task_id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| {
                        HostError::state(format!("orchestration task not found: {task_id}"))
                    })?;
                if let Some(run_id) = task.run_id {
                    return Err(HostError::state(format!(
                        "task {task_id} belongs to run {run_id}; transfer the run instead"
                    )));
                }
                let task = self
                    .runtime_store
                    .transfer_orchestration_task_coordinator(&task_id, &actor, &to, &reason, force)
                    .await
                    .map_err(state_error)?;
                Ok(json!({ "task": task }))
            }
            (None, Some(run_id)) => {
                let run = self
                    .runtime_store
                    .transfer_orchestration_run_coordinator(&run_id, &actor, &to, &reason, force)
                    .await
                    .map_err(state_error)?;
                if let Some(handle) = self.coordinators.get_mut(&run_id) {
                    handle.config.coordinator_handle = Some(to);
                }
                Ok(json!({ "run": run }))
            }
            _ => Err(HostError::format("exactly one of task or run is required.")),
        }
    }

    // --- dispatch -------------------------------------------------------------

    pub(super) async fn orchestration_dispatch(&mut self, payload: &Value) -> HostResult<Value> {
        let task_id = require_string(payload, "task")?;
        let to = require_string(payload, "to")?;
        let from = require_string(payload, "from")?;
        let inject = payload
            .get("inject")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let dry_run = payload
            .get("dryRun")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let return_preamble = payload
            .get("returnPreamble")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let assume_agent = optional_string(payload, "assumeAgent");
        let assumed_adapter = assume_agent
            .as_deref()
            .map(|agent| {
                adapter_for(agent)
                    .ok_or_else(|| HostError::format(format!("unsupported agent type: {agent}")))
            })
            .transpose()?;
        let allow_self_dispatch = payload
            .get("allowSelfDispatch")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if from == to && !allow_self_dispatch {
            return Err(HostError::state(format!(
                "self_dispatch_requires_opt_in: from and to both resolve to {to}; pass --allow-self-dispatch for a deliberate protocol test"
            )));
        }

        let task = self
            .runtime_store
            .orchestration_task_by_id(&task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {task_id}")))?;
        let (_allow_stale, stripped_spec) = parse_allow_stale_base_from_spec(&task.spec);
        if from != task.coordinator_handle {
            return Err(HostError::state(format!(
                "coordinator ownership conflict: task is owned by {}, not {from}",
                task.coordinator_handle
            )));
        }
        let gate_resolution = self.latest_resolved_gate(&task_id).await?;

        if dry_run {
            // Builds the preamble without mutating any state; the dispatch id
            // is a placeholder that a real dispatch will replace.
            let preamble = build_dispatch_preamble(&PreambleParams {
                task_id: &task_id,
                dispatch_id: "ctx_dryrun",
                task_spec: &stripped_spec,
                coordinator_handle: &from,
                base_drift: None,
                gate_resolution: gate_resolution.as_ref(),
                worker_kind: WorkerKind::BareShell,
            });
            return Ok(json!({ "dryRun": true, "preamble": preamble }));
        }

        if inject {
            // Refuse to dump a preamble into a bare shell: injection requires
            // a recognized agent to be running in the target terminal.
            // Stable `stale_terminal_handle:` prefix is matched by recovery docs
            // and agents re-listing terminals after PTY death.
            let Some(session) = self.sessions.get(&to) else {
                return Err(HostError::state(format!(
                    "stale_terminal_handle: terminal {to} not found; remint the PTY \
                     (reopen the tab) or dispatch to a live handle from terminal-list"
                )));
            };
            if !session.running() {
                return Err(HostError::state(format!(
                    "stale_terminal_handle: terminal {to} is not running; remint the PTY \
                     (reopen the tab) or dispatch to a live handle from terminal-list"
                )));
            }
            if session.workspace_id != task.workspace_id {
                return Err(HostError::state(format!(
                    "terminal {to} belongs to workspace {}, not task workspace {}",
                    session.workspace_id, task.workspace_id
                )));
            }
            if self.agent_presence.get(&to).is_none() && assumed_adapter.is_none() {
                return Err(HostError::state(format!(
                    "no agent detected in terminal {to}; use --assume-agent <agent> for an audited injection override or dispatch without --inject and submit the returned bootstrap manually"
                )));
            }
            if !self.agent_presence.is_injection_ready(&to) && assumed_adapter.is_none() {
                return Err(HostError::state(format!(
                    "agent in terminal {to} is not idle; cannot inject"
                )));
            }
        }

        let completion_policy = optional_string(payload, "completionPolicy")
            .unwrap_or_else(|| "return-immediately".to_string());
        if completion_policy != "return-immediately" {
            return Err(HostError::format(format!(
                "unsupported completion policy: {completion_policy}; only return-immediately is implemented"
            )));
        }
        let context_token = uuid::Uuid::new_v4().simple().to_string();
        let context_hash = context_token_hash(&context_token);
        let dispatch = self
            .runtime_store
            .create_scoped_orchestration_dispatch(
                &task_id,
                &to,
                task.run_id.as_deref(),
                &task.workspace_id,
                &task.coordinator_handle,
                Some(&context_hash),
                &completion_policy,
                optional_string(payload, "terminalPolicy")
                    .as_deref()
                    .unwrap_or("keep-open"),
            )
            .await
            .map_err(state_error)?;
        // Recorded even when null so `task-show` always reports how the worker
        // was launched, and so fallback selection can read the attempt history.
        self.runtime_store
            .set_orchestration_dispatch_profile(
                &dispatch.id,
                optional_string(payload, "agentProfile").as_deref(),
                optional_string(payload, "agentQuotaGroup").as_deref(),
            )
            .await
            .map_err(state_error)?;
        if let Some(adapter) = assumed_adapter {
            self.runtime_store
                .insert_orchestration_audit_event(
                    Some(&from),
                    "dispatch.inject.assume_agent",
                    &dispatch.id,
                    &format!(
                        "agent readiness bypassed with explicit adapter {}",
                        adapter.agent_type
                    ),
                )
                .await
                .map_err(state_error)?;
        }
        self.orchestration_activity_last_recorded.remove(&to);
        if let Err(error) = self.install_dispatch_context(&to, &dispatch.id, &context_token) {
            let _ = self
                .runtime_store
                .fail_orchestration_startup(&dispatch.id, "could not install worker context")
                .await;
            return Err(error);
        }
        let preamble = build_dispatch_preamble(&PreambleParams {
            task_id: &task_id,
            dispatch_id: &dispatch.id,
            task_spec: &stripped_spec,
            coordinator_handle: &from,
            base_drift: None,
            gate_resolution: gate_resolution.as_ref(),
            worker_kind: WorkerKind::PromptReturningAgent,
        });

        if inject {
            if !self
                .sessions
                .get(&to)
                .is_some_and(|session| session.running())
            {
                self.remove_dispatch_context(&to);
                let _ = self
                    .runtime_store
                    .fail_orchestration_startup(&dispatch.id, "terminal session vanished")
                    .await;
                return Err(HostError::state(format!("terminal {to} vanished")));
            }
            let force_submit = payload
                .get("forceSubmit")
                .and_then(Value::as_bool)
                .unwrap_or_else(|| {
                    assumed_adapter
                        .map(|adapter| adapter.force_submit)
                        .unwrap_or(false)
                });
            if let Err(error) =
                self.queue_orchestration_paste(&to, &preamble, Vec::new(), force_submit)
            {
                self.remove_dispatch_context(&to);
                let _ = self
                    .runtime_store
                    .fail_orchestration_startup(&dispatch.id, "terminal input unavailable")
                    .await;
                return Err(error);
            }
        }

        let mut response = json!({
            "dispatch": dispatch,
            "taskId": task_id,
            "runId": task.run_id,
            "workspaceId": task.workspace_id,
            "coordinatorHandle": task.coordinator_handle,
            "assigneeHandle": to,
            "dispatchingTerminal": from,
            "startupState": if inject { "dispatch_submitted_unconfirmed" } else { "awaiting_manual_delivery" },
            "dispatchPreambleVersion": 2,
            "contextToken": context_token,
            "contextPath": self.dispatch_context_path(&to),
            "assumedAgent": assume_agent,
        });
        let bootstrap = build_dispatch_bootstrap();
        if return_preamble {
            response["preamble"] = Value::String(preamble);
        } else if !inject {
            response["preamble"] = Value::String(bootstrap.clone());
        }
        response["bootstrap"] = Value::String(bootstrap);
        Ok(response)
    }

    async fn orchestration_dispatch_show(&mut self, payload: &Value) -> HostResult<Value> {
        let task_id = require_string(payload, "task")?;
        let active = self
            .runtime_store
            .active_orchestration_dispatch_for_task(&task_id)
            .await
            .map_err(state_error)?;
        let history = self
            .runtime_store
            .list_orchestration_dispatches_for_task(&task_id)
            .await
            .map_err(state_error)?;
        Ok(json!({ "active": active, "history": history }))
    }

    async fn active_worker_dispatch(
        &self,
        payload: &Value,
    ) -> HostResult<OrchestrationDispatchContext> {
        let terminal = optional_string(payload, "terminal").ok_or_else(|| {
            HostError::format("terminal is required; run inside an Alera terminal.")
        })?;
        let dispatch = self
            .runtime_store
            .active_orchestration_dispatch_for_handle(&terminal)
            .await
            .map_err(state_error)?
            .ok_or_else(|| {
                HostError::state(format!("no active dispatch for terminal {terminal}"))
            })?;
        if let Some(expected_hash) = dispatch.context_token_hash.as_deref() {
            let token = optional_string(payload, "contextToken")
                .ok_or_else(|| HostError::state("dispatch context token is required"))?;
            if context_token_hash(&token) != expected_hash {
                return Err(HostError::state(
                    "dispatch context token is invalid or stale",
                ));
            }
        }
        Ok(dispatch)
    }

    async fn orchestration_dispatch_accept(&mut self, payload: &Value) -> HostResult<Value> {
        let terminal = optional_string(payload, "terminal")
            .ok_or_else(|| HostError::format("terminal is required."))?;
        let dispatch = self.active_worker_dispatch(payload).await?;
        let accepted = self
            .runtime_store
            .accept_orchestration_dispatch(
                &dispatch.id,
                &terminal,
                &optional_string(payload, "contextToken")
                    .map(|token| context_token_hash(&token))
                    .unwrap_or_default(),
            )
            .await
            .map_err(state_error)?;
        self.consume_owned_spawn_metadata(&terminal).await;
        Ok(json!({ "outcome": "accepted", "dispatch": accepted }))
    }

    async fn orchestration_dispatch_interrupt(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let reason = require_string(payload, "reason")?;
        let dispatch = self
            .runtime_store
            .orchestration_dispatch_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("dispatch not found: {id}")))?;
        if !matches!(
            dispatch.status,
            OrchestrationDispatchStatus::Dispatched | OrchestrationDispatchStatus::Stalled
        ) {
            return Err(HostError::state("dispatch is not interruptible"));
        }
        let actor = optional_string(payload, "actor");
        let force = payload
            .get("force")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !force && actor.as_deref() != Some(dispatch.coordinator_handle.as_str()) {
            return Err(HostError::state(format!(
                "only coordinator {} can interrupt dispatch {id}; use --force for audited recovery",
                dispatch.coordinator_handle
            )));
        }
        let handle = dispatch
            .assignee_handle
            .clone()
            .ok_or_else(|| HostError::state("dispatch has no assignee"))?;
        let agent_type = self.agent_presence.agent_type(&handle).unwrap_or("codex");
        let adapter = adapter_for(agent_type)
            .ok_or_else(|| HostError::state(format!("no interrupt adapter for {agent_type}")))?;
        self.queue_orchestration_control(&handle, adapter.interrupt_bytes)?;
        self.runtime_store
            .insert_orchestration_audit_event(
                actor.as_deref(),
                if force {
                    "dispatch.interrupt.force"
                } else {
                    "dispatch.interrupt"
                },
                &id,
                &reason,
            )
            .await
            .map_err(state_error)?;
        Ok(json!({ "dispatchId": id, "interrupted": true, "reason": reason }))
    }

    fn orchestration_worker_help(&self) -> Value {
        json!({
            "dispatchPreambleVersion": 2,
            "workerInstructions": build_worker_contract("<coordinator-handle>", WorkerKind::PromptReturningAgent),
            "commands": [
                "alera orchestration dispatch-accept",
                "alera orchestration --json context",
                "alera orchestration heartbeat --phase <phase>",
                "alera orchestration escalate --subject <subject> --body <details>",
                "alera orchestration complete --summary <summary> --completion-kind success --artifacts '[]' --validation '[]'"
            ]
        })
    }

    async fn orchestration_context(&mut self, payload: &Value) -> HostResult<Value> {
        let dispatch = self.active_worker_dispatch(payload).await?;
        let mut task = self
            .runtime_store
            .orchestration_task_by_id(&dispatch.task_id)
            .await
            .map_err(state_error)?;
        let mut base_drift = Value::Null;
        if let Some((task_spec, stored_drift)) =
            self.orchestration_preflight_context(&dispatch).await?
        {
            if let Some(task) = task.as_mut() {
                task.spec = task_spec;
            }
            base_drift = stored_drift;
        }
        let gate_resolution = self.latest_resolved_gate(&dispatch.task_id).await?;
        let worker_instructions = build_worker_contract(
            &dispatch.coordinator_handle,
            WorkerKind::PromptReturningAgent,
        );
        Ok(json!({
            "task": task,
            "dispatch": dispatch,
            "baseDrift": base_drift,
            "gateResolution": gate_resolution.map(|gate| json!({
                "question": gate.question,
                "resolution": gate.resolution,
            })),
            "workerInstructions": worker_instructions,
            "coordinatorHandle": dispatch.coordinator_handle,
            "assigneeHandle": dispatch.assignee_handle,
            "phase": dispatch.status.as_str(),
            "lastActivityAt": dispatch.last_activity_at,
            "completionState": dispatch.status.as_str(),
        }))
    }

    async fn orchestration_preflight_context(
        &self,
        dispatch: &OrchestrationDispatchContext,
    ) -> HostResult<Option<(String, Value)>> {
        let Some(handle) = dispatch.assignee_handle.as_deref() else {
            return Ok(None);
        };
        let Some(tab) = self
            .runtime_store
            .find_workspace_tab(handle)
            .await
            .map_err(state_error)?
        else {
            return Ok(None);
        };
        let Some(preflight) = tab.payload.get("orchestrationPreflight") else {
            return Ok(None);
        };
        if preflight.get("taskId").and_then(Value::as_str) != Some(dispatch.task_id.as_str())
            || preflight.get("dispatchId").and_then(Value::as_str) != Some(dispatch.id.as_str())
        {
            return Ok(None);
        }
        let Some(task_spec) = preflight.get("taskSpec").and_then(Value::as_str) else {
            return Ok(None);
        };
        Ok(Some((
            task_spec.to_string(),
            preflight.get("baseDrift").cloned().unwrap_or(Value::Null),
        )))
    }

    async fn orchestration_heartbeat(&mut self, payload: &Value) -> HostResult<Value> {
        let dispatch = self.active_worker_dispatch(payload).await?;
        let accepted = self
            .runtime_store
            .record_orchestration_activity(&dispatch.id)
            .await
            .map_err(state_error)?;
        if !accepted {
            return Err(HostError::state("heartbeat rejected for inactive dispatch"));
        }
        Ok(
            json!({ "lifecycleAccepted": true, "dispatchId": dispatch.id, "phase": optional_string(payload, "phase") }),
        )
    }

    async fn orchestration_escalate(&mut self, payload: &Value) -> HostResult<Value> {
        let dispatch = self.active_worker_dispatch(payload).await?;
        let assignee = dispatch.assignee_handle.clone().unwrap_or_default();
        let message = self
            .runtime_store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: assignee,
                to_handle: dispatch.coordinator_handle.clone(),
                subject: require_string(payload, "subject")?,
                body: optional_string(payload, "body").unwrap_or_default(),
                message_type: OrchestrationMessageType::Escalation,
                priority: OrchestrationMessagePriority::High,
                thread_id: None,
                payload: Some(
                    json!({
                        "taskId": dispatch.task_id,
                        "dispatchId": dispatch.id,
                    })
                    .to_string(),
                ),
                run_id: dispatch.run_id.clone(),
                workspace_id: Some(dispatch.workspace_id.clone()),
                task_id: Some(dispatch.task_id.clone()),
                dispatch_id: Some(dispatch.id.clone()),
                expires_at: None,
            })
            .await
            .map_err(state_error)?;
        self.runtime_store
            .record_orchestration_activity(&dispatch.id)
            .await
            .map_err(state_error)?;
        self.notify_message_arrived(
            &dispatch.coordinator_handle,
            OrchestrationMessageType::Escalation,
        )
        .await;
        Ok(json!({ "lifecycleAccepted": true, "message": message }))
    }

    async fn orchestration_complete(&mut self, payload: &Value) -> HostResult<Value> {
        let dispatch = self.active_worker_dispatch(payload).await?;
        let assignee = dispatch
            .assignee_handle
            .clone()
            .ok_or_else(|| HostError::state("active dispatch has no assignee"))?;
        let result = payload
            .get("result")
            .and_then(Value::as_object)
            .ok_or_else(|| HostError::format("result must be an object."))?;
        let summary = result
            .get("summary")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| HostError::format("result.summary is required."))?;
        let completion_kind = result
            .get("completionKind")
            .and_then(Value::as_str)
            .unwrap_or("success");
        for field in ["artifacts", "filesModified", "validation"] {
            if !result.get(field).is_some_and(Value::is_array) {
                return Err(HostError::format(format!(
                    "result.{field} must be an array."
                )));
            }
        }
        let task = self
            .runtime_store
            .orchestration_task_by_id(&dispatch.task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("dispatch task no longer exists"))?;
        validate_result_schema(result, task.result_schema.as_deref())?;
        let result_json =
            serde_json::to_string(result).map_err(|error| HostError::format(error.to_string()))?;
        if completion_kind == "failure" {
            self.remove_dispatch_context(&assignee);
            let failed = self
                .runtime_store
                .fail_orchestration_dispatch_with_result(&dispatch.id, summary, Some(&result_json))
                .await
                .map_err(state_error)?;
            return Ok(json!({
                "lifecycleAccepted": true,
                "taskId": dispatch.task_id,
                "dispatchId": failed.id,
                "dispatchStatus": failed.status.as_str(),
            }));
        }
        if completion_kind != "success" {
            return Err(HostError::format(
                "result.completionKind must be success or failure.",
            ));
        }
        let completed = self
            .runtime_store
            .complete_orchestration_dispatch(&dispatch.id, &assignee, &result_json)
            .await
            .map_err(state_error)?;
        self.apply_terminal_completion_policy(&assignee, &completed.terminal_policy)
            .await?;
        Ok(json!({
            "delivered": true,
            "lifecycleAccepted": true,
            "taskId": completed.task_id,
            "dispatchId": completed.id,
            "taskStatus": "completed",
            "dispatchStatus": completed.status.as_str(),
        }))
    }

    async fn orchestration_worker_done(&mut self, payload: &Value) -> HostResult<Value> {
        let terminal = optional_string(payload, "terminal")
            .ok_or_else(|| HostError::format("terminal is required."))?;
        let task_id = require_string(payload, "task")?;
        let dispatch_id = require_string(payload, "dispatch")?;
        let dispatch = self
            .runtime_store
            .orchestration_dispatch_by_id(&dispatch_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("dispatch not found: {dispatch_id}")))?;
        if dispatch.task_id != task_id || dispatch.assignee_handle.as_deref() != Some(&terminal) {
            return Err(HostError::state("worker-done authority rejected"));
        }
        let result = payload
            .get("result")
            .and_then(Value::as_object)
            .ok_or_else(|| HostError::format("result must be an object."))?;
        result
            .get("summary")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| HostError::format("result.summary is required."))?;
        let completion_kind = result
            .get("completionKind")
            .and_then(Value::as_str)
            .unwrap_or("success");
        if completion_kind != "success" {
            return Err(HostError::format(
                "worker-done result.completionKind must be success.",
            ));
        }
        for field in ["artifacts", "filesModified", "validation"] {
            if !result.get(field).is_some_and(Value::is_array) {
                return Err(HostError::format(format!(
                    "result.{field} must be an array."
                )));
            }
        }
        let task = self
            .runtime_store
            .orchestration_task_by_id(&task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state("dispatch task no longer exists"))?;
        validate_result_schema(result, task.result_schema.as_deref())?;
        let result_json =
            serde_json::to_string(result).map_err(|error| HostError::format(error.to_string()))?;
        let completed = self
            .runtime_store
            .complete_orchestration_dispatch(&dispatch_id, &terminal, &result_json)
            .await
            .map_err(state_error)?;
        self.apply_terminal_completion_policy(&terminal, &completed.terminal_policy)
            .await?;
        Ok(json!({
            "delivered": true,
            "lifecycleAccepted": true,
            "taskId": completed.task_id,
            "dispatchId": completed.id,
            "taskStatus": "completed",
            "dispatchStatus": completed.status.as_str(),
        }))
    }

    async fn apply_terminal_completion_policy(
        &mut self,
        handle: &str,
        policy: &str,
    ) -> HostResult<()> {
        match policy {
            "return-to-shell" => {
                let _ = self.queue_orchestration_control(handle, b"\x04");
            }
            "close-on-success" => {
                if let Some(tab_id) = self
                    .sessions
                    .get(handle)
                    .map(|session| session.tab_id.clone())
                {
                    self.runtime_store
                        .remove_workspace_tab(&tab_id)
                        .await
                        .map_err(state_error)?;
                    self.terminate_sessions_for_tab(&tab_id).await;
                    self.broadcast_authenticated(crate::terminal_host::protocol::event(
                        "workspaceTabsChanged",
                        json!({}),
                    ));
                } else {
                    self.agent_presence.remove(handle);
                    self.schedule_shutdown_if_idle();
                }
            }
            _ => {}
        }
        Ok(())
    }

    async fn orchestration_run_list(&mut self, payload: &Value) -> HostResult<Value> {
        let runs = self
            .runtime_store
            .list_orchestration_coordinator_runs(optional_string(payload, "workspace").as_deref())
            .await
            .map_err(state_error)?;
        Ok(
            json!({ "kind": "runs", "items": runs, "runs": runs, "filters": { "workspace": optional_string(payload, "workspace") } }),
        )
    }

    async fn orchestration_run_show(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("coordinator run not found: {id}")))?;
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(None, Some(&id), Some(&run.workspace_id))
            .await
            .map_err(state_error)?;
        Ok(json!({ "run": run, "tasks": tasks }))
    }

    async fn orchestration_status(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let run = self
            .runtime_store
            .orchestration_coordinator_run_by_id(&id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("coordinator run not found: {id}")))?;
        let tasks = self
            .runtime_store
            .list_scoped_orchestration_tasks(None, Some(&id), Some(&run.workspace_id))
            .await
            .map_err(state_error)?;
        let mut run_handles = tasks
            .iter()
            .filter_map(|task| task.assignee_handle.as_deref())
            .collect::<std::collections::HashSet<_>>();
        if let Some(coordinator_handle) = run.coordinator_handle.as_deref() {
            run_handles.insert(coordinator_handle);
        }
        let terminals = self.orchestration_terminals(&json!({}))["items"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|terminal| {
                terminal.get("workspaceId").and_then(Value::as_str)
                    == Some(run.workspace_id.as_str())
                    && terminal
                        .get("handle")
                        .and_then(Value::as_str)
                        .is_some_and(|handle| run_handles.contains(handle))
            })
            .cloned()
            .collect::<Vec<_>>();
        let active = tasks
            .iter()
            .filter(|task| {
                matches!(
                    task.status,
                    OrchestrationTaskStatus::Dispatched | OrchestrationTaskStatus::Stalled
                )
            })
            .count();
        Ok(json!({
            "run": run,
            "tasks": tasks,
            "terminals": terminals,
            "activeTaskCount": active,
            "lastActivityAt": run.last_activity_at,
        }))
    }

    async fn latest_resolved_gate(&self, task_id: &str) -> HostResult<Option<GateResolution>> {
        let gates = self
            .runtime_store
            .list_orchestration_gates(Some(task_id), Some(OrchestrationGateStatus::Resolved))
            .await
            .map_err(state_error)?;
        Ok(gates.into_iter().last().map(|gate| GateResolution {
            question: gate.question,
            resolution: gate.resolution.unwrap_or_default(),
        }))
    }

    // --- gates --------------------------------------------------------------

    async fn orchestration_gate_create(&mut self, payload: &Value) -> HostResult<Value> {
        let task_id = require_string(payload, "task")?;
        let question = require_string(payload, "question")?;
        let options: Vec<String> = payload
            .get("options")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default();
        let gate = self
            .runtime_store
            .create_orchestration_gate(&task_id, &question, &options)
            .await
            .map_err(state_error)?;
        Ok(json!(gate))
    }

    async fn orchestration_gate_resolve(&mut self, payload: &Value) -> HostResult<Value> {
        let gate_id = require_string(payload, "id")?;
        let resolution = require_string(payload, "resolution")?;
        let gate = self
            .runtime_store
            .resolve_orchestration_gate(&gate_id, &resolution)
            .await
            .map_err(state_error)?;
        Ok(json!(gate))
    }

    async fn orchestration_gate_list(&mut self, payload: &Value) -> HostResult<Value> {
        let task_id = optional_string(payload, "task");
        let status = match optional_string(payload, "status") {
            None => None,
            Some(raw) => Some(
                OrchestrationGateStatus::parse(&raw)
                    .ok_or_else(|| HostError::format(format!("unknown gate status: {raw}")))?,
            ),
        };
        let gates = self
            .runtime_store
            .list_orchestration_gates(task_id.as_deref(), status)
            .await
            .map_err(state_error)?;
        Ok(
            json!({ "kind": "gates", "items": gates, "gates": gates, "filters": { "task": task_id, "status": status.map(|value| value.as_str()) } }),
        )
    }

    // --- reset --------------------------------------------------------------

    async fn orchestration_reset(&mut self, payload: &Value) -> HostResult<Value> {
        let tasks = payload
            .get("tasks")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let messages = payload
            .get("messages")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        // No explicit scope means reset everything, mirroring Orca's --all
        // default.
        let all =
            (!tasks && !messages) || payload.get("all").and_then(Value::as_bool).unwrap_or(false);
        if all || tasks {
            for (_, handle) in self.coordinators.drain() {
                handle.stop();
            }
            self.runtime_store
                .reset_orchestration_tasks()
                .await
                .map_err(state_error)?;
        }
        if all || messages {
            self.runtime_store
                .reset_orchestration_messages()
                .await
                .map_err(state_error)?;
        }
        Ok(json!({
            "tasks": all || tasks,
            "messages": all || messages,
        }))
    }

    // --- waiter plumbing ----------------------------------------------------

    /// Wakes parked `check --wait`/`ask` requests that match a newly arrived
    /// message and writes their responses.
    pub(super) async fn notify_message_arrived(
        &mut self,
        to_handle: &str,
        message_type: OrchestrationMessageType,
    ) {
        let woken = self
            .orchestration_waiters
            .take_matching(to_handle, message_type);
        for waiter in woken {
            self.resolve_waiter(waiter).await;
        }
    }

    async fn resolve_waiter(&mut self, waiter: MessageWaiter) {
        match waiter.kind.clone() {
            WaitKind::Check {
                type_filter,
                inject,
            } => {
                let filter = type_filter.clone();
                match self.consume_unread_messages(&waiter.handle, &filter).await {
                    Ok(messages) if messages.is_empty() => {
                        // Raced with another consumer: re-park with the same
                        // waiter id so the original timeout still expires it.
                        self.orchestration_waiters.repark(waiter);
                    }
                    Ok(messages) => {
                        self.client_write(
                            waiter.client_id,
                            ok_response(waiter.request_id, check_response(&messages, inject)),
                        );
                    }
                    Err(error) => {
                        self.client_write(
                            waiter.client_id,
                            error_response(waiter.request_id, &error),
                        );
                    }
                }
            }
            WaitKind::Ask {
                thread_id,
                after_sequence,
            } => {
                match self
                    .runtime_store
                    .orchestration_thread_messages_for(&thread_id, &waiter.handle, after_sequence)
                    .await
                {
                    Ok(replies) if replies.is_empty() => {
                        // The wake was for an unrelated message; keep waiting
                        // under the original waiter id so its timeout remains
                        // authoritative.
                        self.orchestration_waiters.repark(waiter);
                    }
                    Ok(mut replies) => {
                        let ids: Vec<String> =
                            replies.iter().map(|reply| reply.id.clone()).collect();
                        let _ = self
                            .runtime_store
                            .mark_orchestration_messages_read(&ids)
                            .await;
                        let reply = replies.remove(0);
                        self.client_write(
                            waiter.client_id,
                            ok_response(
                                waiter.request_id,
                                json!({ "answered": true, "reply": reply }),
                            ),
                        );
                    }
                    Err(error) => {
                        self.client_write(
                            waiter.client_id,
                            error_response(waiter.request_id, &HostError::state(error.to_string())),
                        );
                    }
                }
            }
            WaitKind::TerminalState { .. } | WaitKind::TaskState { .. } => {
                self.orchestration_waiters.repark(waiter);
            }
        }
    }

    pub(super) async fn handle_orchestration_wait_timeout(
        &mut self,
        waiter_id: u64,
        waited_ms: u64,
    ) {
        let Some(waiter) = self.orchestration_waiters.take_by_id(waiter_id) else {
            return;
        };
        if matches!(
            &waiter.kind,
            WaitKind::TerminalState { .. } | WaitKind::TaskState { .. }
        ) {
            self.finish_orchestration_state_wait_timeout(waiter, waited_ms)
                .await;
            return;
        }
        let mut payload = match waiter.kind {
            WaitKind::Check { inject, .. } => check_response(&[], inject),
            WaitKind::Ask { .. } => json!({ "answered": false }),
            WaitKind::TerminalState { .. } | WaitKind::TaskState { .. } => unreachable!(),
        };
        payload["timedOut"] = Value::Bool(true);
        payload["outcome"] = Value::String("timeout".to_string());
        payload["waitedMs"] = json!(waited_ms);
        self.client_write(waiter.client_id, ok_response(waiter.request_id, payload));
    }

    pub(super) fn spawn_wait_timeout(&self, waiter_id: u64, timeout_ms: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(timeout_ms)).await;
            let _ = inbox.send(ServerCommand::OrchestrationWaitTimeout {
                waiter_id,
                waited_ms: timeout_ms,
            });
        });
    }
}

fn optional_status_string(entry: &Value, key: &str) -> Option<String> {
    entry
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn generated_group_thread_id() -> String {
    format!("thread_{}", uuid::Uuid::new_v4().simple())
}

fn check_response(messages: &[OrchestrationMessage], inject: bool) -> Value {
    let mut response = json!({ "messages": messages });
    if inject {
        response["formatted"] = Value::String(format_messages_for_injection(messages));
    }
    response
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn generated_group_thread_ids_are_unique() {
        let ids = (0..512)
            .map(|_| generated_group_thread_id())
            .collect::<HashSet<_>>();

        assert_eq!(ids.len(), 512);
    }

    #[test]
    fn result_schema_distinguishes_integer_from_fractional_number() {
        let schema = r#"{"properties":{"count":{"type":"integer"}}}"#;
        for value in [json!(1), json!(1.0)] {
            let result = json!({"count": value}).as_object().unwrap().clone();
            assert!(validate_result_schema(&result, Some(schema)).is_ok());
        }
        let fractional = json!({"count": 1.5}).as_object().unwrap().clone();
        assert!(validate_result_schema(&fractional, Some(schema)).is_err());
    }

    #[test]
    fn result_schema_enforces_nested_enum_items_and_additional_properties() {
        let schema = r#"{
            "type":"object",
            "required":["status","details"],
            "additionalProperties":false,
            "properties":{
                "status":{"enum":["ok"]},
                "details":{
                    "type":"object",
                    "required":["checks"],
                    "properties":{"checks":{"type":"array","items":{"type":"boolean"}}}
                }
            }
        }"#;
        let valid = json!({"status":"ok","details":{"checks":[true, false]}})
            .as_object()
            .unwrap()
            .clone();
        assert!(validate_result_schema(&valid, Some(schema)).is_ok());
        for invalid in [
            json!({"status":"bad","details":{"checks":[true]}}),
            json!({"status":"ok","details":{"checks":["yes"]}}),
            json!({"status":"ok","details":{"checks":[]},"extra":true}),
        ] {
            assert!(validate_result_schema(invalid.as_object().unwrap(), Some(schema)).is_err());
        }
    }
}
