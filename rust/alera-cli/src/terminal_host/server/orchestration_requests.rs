use std::time::Duration;

use alera_core::runtime::{
    NewOrchestrationMessage, NewOrchestrationTask, OrchestrationGateStatus, OrchestrationMessage,
    OrchestrationMessagePriority, OrchestrationMessageType, OrchestrationTaskStatus,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::dispatch_preamble::{
    build_dispatch_preamble, parse_allow_stale_base_from_spec, GateResolution, PreambleParams,
};
use crate::terminal_host::orchestration::group_resolution::{
    is_group_address, resolve_group_address, GroupResolutionTerminal,
};
use crate::terminal_host::orchestration::lifecycle_reconciliation::reconcile_lifecycle_message;
use crate::terminal_host::orchestration::message_formatter::format_messages_for_injection;
use crate::terminal_host::orchestration::message_waiters::{MessageWaiter, WaitKind};
use crate::terminal_host::protocol::{error_response, ok_response};
use crate::terminal_host::session::Session;

use super::{ServerActor, ServerCommand};

/// Server-side ceiling for `check --wait`/`ask` so a parked request can never
/// outlive a misbehaving client that skipped its own timeout.
const MAX_WAIT_TIMEOUT_MS: u64 = 600_000;
const DEFAULT_WAIT_TIMEOUT_MS: u64 = 120_000;

fn optional_string(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn require_string(payload: &Value, key: &str) -> HostResult<String> {
    optional_string(payload, key).ok_or_else(|| HostError::format(format!("{key} is required.")))
}

fn parse_message_type(payload: &Value) -> HostResult<OrchestrationMessageType> {
    match payload.get("type").and_then(Value::as_str) {
        None => Ok(OrchestrationMessageType::Status),
        Some(raw) => OrchestrationMessageType::parse(raw)
            .ok_or_else(|| HostError::format(format!("unknown message type: {raw}"))),
    }
}

fn parse_priority(payload: &Value) -> HostResult<OrchestrationMessagePriority> {
    match payload.get("priority").and_then(Value::as_str) {
        None => Ok(OrchestrationMessagePriority::Normal),
        Some(raw) => OrchestrationMessagePriority::parse(raw)
            .ok_or_else(|| HostError::format(format!("unknown message priority: {raw}"))),
    }
}

fn parse_type_filter(payload: &Value) -> HostResult<Vec<OrchestrationMessageType>> {
    let Some(types) = payload.get("types") else {
        return Ok(Vec::new());
    };
    let Some(items) = types.as_array() else {
        return Err(HostError::format("types must be an array of strings."));
    };
    items
        .iter()
        .map(|item| {
            item.as_str()
                .and_then(OrchestrationMessageType::parse)
                .ok_or_else(|| HostError::format(format!("unknown message type: {item}")))
        })
        .collect()
}

fn wait_timeout_ms(payload: &Value) -> u64 {
    payload
        .get("timeoutMs")
        .and_then(Value::as_u64)
        .unwrap_or(DEFAULT_WAIT_TIMEOUT_MS)
        .min(MAX_WAIT_TIMEOUT_MS)
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

impl ServerActor {
    /// Handles `orchestration.*` requests. Wait-capable verbs return
    /// `Ok(None)` when the request parked a waiter; the response is written
    /// later by a wake or timeout.
    pub(super) async fn handle_orchestration_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        self.require_auth(client_id)?;
        match request_type {
            "orchestration.send" => self.orchestration_send(payload).await.map(Some),
            "orchestration.check" => {
                self.orchestration_check(client_id, request_id, payload)
                    .await
            }
            "orchestration.reply" => self.orchestration_reply(payload).await.map(Some),
            "orchestration.inbox" => self.orchestration_inbox(payload).await.map(Some),
            "orchestration.ask" => self.orchestration_ask(client_id, request_id, payload).await,
            "orchestration.agentStatus" => self.orchestration_agent_status(payload).await.map(Some),
            "orchestration.terminals" => Ok(Some(self.orchestration_terminals())),
            "orchestration.taskCreate" => self.orchestration_task_create(payload).await.map(Some),
            "orchestration.taskList" => self.orchestration_task_list(payload).await.map(Some),
            "orchestration.taskUpdate" => self.orchestration_task_update(payload).await.map(Some),
            "orchestration.dispatch" => self.orchestration_dispatch(payload).await.map(Some),
            "orchestration.dispatchShow" => {
                self.orchestration_dispatch_show(payload).await.map(Some)
            }
            "orchestration.gateCreate" => self.orchestration_gate_create(payload).await.map(Some),
            "orchestration.gateResolve" => self.orchestration_gate_resolve(payload).await.map(Some),
            "orchestration.gateList" => self.orchestration_gate_list(payload).await.map(Some),
            "orchestration.run" => self.orchestration_run(payload).await.map(Some),
            "orchestration.runStop" => self.orchestration_run_stop().await.map(Some),
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
                subject: format!("Re: {}", original.subject),
                body,
                message_type: OrchestrationMessageType::Status,
                priority: OrchestrationMessagePriority::Normal,
                thread_id: original
                    .thread_id
                    .clone()
                    .or_else(|| Some(original.id.clone())),
                payload: None,
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
        let messages = match optional_string(payload, "terminal") {
            Some(handle) => self
                .runtime_store
                .all_orchestration_messages_for_handle(&handle, None, limit)
                .await
                .map_err(state_error)?,
            None => self
                .runtime_store
                .orchestration_inbox(limit)
                .await
                .map_err(state_error)?,
        };
        Ok(json!({ "messages": messages }))
    }

    // --- ask --------------------------------------------------------------

    async fn orchestration_ask(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let from_handle = require_string(payload, "from")?;
        let to = require_string(payload, "to")?;
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

    async fn orchestration_agent_status(&mut self, payload: &Value) -> HostResult<Value> {
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
            if self.agent_presence.update(handle, agent_type, state) {
                became_ready.push(handle.to_string());
            }
        }
        // A transition into an injection-ready state flushes that handle's
        // undelivered queue (push-on-idle).
        for handle in became_ready {
            self.deliver_pending_messages(&handle).await;
        }
        Ok(json!({}))
    }

    // --- terminals ---------------------------------------------------------

    pub(super) fn orchestration_terminals(&self) -> Value {
        let terminals: Vec<Value> = self
            .sessions
            .iter()
            .map(|(session_id, session)| {
                let presence = self.agent_presence.get(session_id);
                json!({
                    "handle": session_id,
                    "workspaceId": session.workspace_id,
                    "tabId": session.tab_id,
                    "running": session.running(),
                    "agentType": presence.map(|entry| entry.agent_type.clone()),
                    "agentState": presence.map(|entry| entry.state.as_str()),
                })
            })
            .collect();
        json!({ "terminals": terminals })
    }

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
                created_by_terminal_handle: optional_string(payload, "createdBy"),
            })
            .await
            .map_err(state_error)?;
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
            .list_orchestration_tasks(status)
            .await
            .map_err(state_error)?;
        Ok(json!({ "tasks": tasks }))
    }

    async fn orchestration_task_update(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string(payload, "id")?;
        let status_raw = require_string(payload, "status")?;
        let status = OrchestrationTaskStatus::parse(&status_raw)
            .ok_or_else(|| HostError::format(format!("unknown task status: {status_raw}")))?;
        let result = optional_string(payload, "result");
        let task = self
            .runtime_store
            .update_orchestration_task_status(&id, status, result.as_deref())
            .await
            .map_err(state_error)?;
        Ok(json!(task))
    }

    // --- dispatch -------------------------------------------------------------

    async fn orchestration_dispatch(&mut self, payload: &Value) -> HostResult<Value> {
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

        let task = self
            .runtime_store
            .orchestration_task_by_id(&task_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("orchestration task not found: {task_id}")))?;
        let (_allow_stale, stripped_spec) = parse_allow_stale_base_from_spec(&task.spec);
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
            });
            return Ok(json!({ "dryRun": true, "preamble": preamble }));
        }

        if inject {
            // Refuse to dump a preamble into a bare shell: injection requires
            // a recognized agent to be running in the target terminal.
            let session_running = self.sessions.get(&to).is_some_and(Session::running);
            if !session_running {
                return Err(HostError::state(format!(
                    "terminal {to} is not running; cannot inject"
                )));
            }
            if self.agent_presence.get(&to).is_none() {
                return Err(HostError::state(format!(
                    "no agent detected in terminal {to}; use --dry-run and paste the preamble manually"
                )));
            }
            if !self.agent_presence.is_injection_ready(&to) {
                return Err(HostError::state(format!(
                    "agent in terminal {to} is not idle; cannot inject"
                )));
            }
        }

        let dispatch = self
            .runtime_store
            .create_orchestration_dispatch(&task_id, &to)
            .await
            .map_err(state_error)?;
        let preamble = build_dispatch_preamble(&PreambleParams {
            task_id: &task_id,
            dispatch_id: &dispatch.id,
            task_spec: &stripped_spec,
            coordinator_handle: &from,
            base_drift: None,
            gate_resolution: gate_resolution.as_ref(),
        });

        if inject {
            let Some(session) = self.sessions.get_mut(&to) else {
                let _ = self
                    .runtime_store
                    .fail_orchestration_dispatch(&dispatch.id, "terminal session vanished")
                    .await;
                return Err(HostError::state(format!("terminal {to} vanished")));
            };
            session.write(preamble.as_bytes());
            let session_instance_id = session.instance_id();
            let inbox = self.inbox.clone();
            let session_id = to.clone();
            tokio::spawn(async move {
                tokio::time::sleep(Duration::from_millis(
                    crate::terminal_host::orchestration::message_delivery::DEFERRED_ENTER_DELAY_MS,
                ))
                .await;
                let _ = inbox.send(ServerCommand::OrchestrationDeferredEnter {
                    session_id,
                    session_instance_id,
                    message_ids: Vec::new(),
                });
            });
        }

        let mut response = json!({ "dispatch": dispatch, "taskId": task_id });
        if return_preamble || !inject {
            response["preamble"] = Value::String(preamble);
        }
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
        Ok(json!({ "gates": gates }))
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
            if let Some(handle) = self.coordinator.take() {
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
        }
    }

    pub(super) async fn handle_orchestration_wait_timeout(&mut self, waiter_id: u64) {
        let Some(waiter) = self.orchestration_waiters.take_by_id(waiter_id) else {
            return;
        };
        let mut payload = match waiter.kind {
            WaitKind::Check { inject, .. } => check_response(&[], inject),
            WaitKind::Ask { .. } => json!({ "answered": false, "timedOut": true }),
        };
        payload["timedOut"] = Value::Bool(true);
        self.client_write(waiter.client_id, ok_response(waiter.request_id, payload));
    }

    fn spawn_wait_timeout(&self, waiter_id: u64, timeout_ms: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(timeout_ms)).await;
            let _ = inbox.send(ServerCommand::OrchestrationWaitTimeout { waiter_id });
        });
    }
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
}
