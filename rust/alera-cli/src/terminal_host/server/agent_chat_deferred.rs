//! Dispatches agent-chat requests away from the terminal-host actor.
//!
//! Provider startup and MCP callbacks can wait on the same client connection
//! that issued a request. Keeping this future outside the actor avoids a
//! request/hello deadlock while preserving the actor as the only writer of
//! client responses.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_runtime::commands::{
    decline_request_ids, optional_string, required_string, CallerCtx, ChatOp, ConfigureInput,
    ReceiptKey, SendInput,
};
use super::agent_chat_runtime::ids::payload_digest;
use super::agent_chat_runtime::{AgentChatRuntime, CreateChatInput};

pub(super) async fn dispatch(
    runtime: AgentChatRuntime,
    request_type: &str,
    payload: &Value,
    ctx: CallerCtx,
    validated_attachments: Option<Vec<Value>>,
) -> HostResult<Value> {
    match request_type {
        "agentChat.providers" => {
            let workspace_id = optional_string(payload, "workspaceId")?;
            runtime
                .providers(
                    workspace_id.as_deref(),
                    payload
                        .get("refreshModels")
                        .and_then(Value::as_bool)
                        .unwrap_or(false)
                        || payload
                            .get("refresh")
                            .and_then(Value::as_bool)
                            .unwrap_or(false),
                )
                .await
        }
        "agentChat.list" => {
            let workspace_id = optional_string(payload, "workspaceId")?;
            let chats = runtime
                .list(
                    workspace_id.as_deref(),
                    payload
                        .get("includeArchived")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                )
                .await?;
            Ok(json!({"chats": chats}))
        }
        "agentChat.create" => {
            let request_id = required_string(payload, "requestId")?;
            if optional_string(payload, "hostId")?.is_some_and(|host_id| host_id != "local") {
                return Err(HostError::conflict(
                    "unsupported",
                    "A local host cannot create a chat for a remote host.",
                    json!({}),
                ));
            }
            runtime
                .create(
                    CreateChatInput {
                        workspace_id: required_string(payload, "workspaceId")?,
                        provider: optional_string(payload, "provider")?,
                        provider_instance_id: optional_string(payload, "providerInstanceId")?,
                        model: optional_string(payload, "model")?,
                        reasoning_effort: optional_string(payload, "reasoningEffort")?,
                        runtime_mode: optional_string(payload, "runtimeMode")?,
                        interaction_mode: optional_string(payload, "interactionMode")?,
                        title: optional_string(payload, "title")?,
                        metadata: None,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.reopen" => {
            let request_id = required_string(payload, "requestId")?;
            let chat_id = required_string(payload, "chatId")?;
            runtime
                .reopen(
                    &chat_id,
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.snapshot" => runtime.snapshot(&required_string(payload, "chatId")?).await,
        "agentChat.payload" => runtime.payload(payload).await,
        "agentChat.history" => {
            let chat_id = required_string(payload, "chatId")?;
            let before = payload
                .get("before")
                .map(|value| match value {
                    Value::String(value) => value.clone(),
                    value => value.to_string(),
                })
                .ok_or_else(|| HostError::format("before is required"))?;
            let limit = payload
                .get("limit")
                .and_then(Value::as_u64)
                .unwrap_or(100)
                .clamp(1, 500) as usize;
            runtime
                .command(&chat_id, ChatOp::History { before, limit }, ctx, None)
                .await
        }
        "agentChat.send" => {
            let chat_id = required_string(payload, "chatId")?;
            let client_message_id = optional_string(payload, "clientMessageId")?
                .or(optional_string(payload, "requestId")?)
                .ok_or_else(|| HostError::format("clientMessageId is required"))?;
            let delivery = optional_string(payload, "delivery")?.unwrap_or_else(|| "auto".into());
            if !matches!(delivery.as_str(), "auto" | "steer" | "queue") {
                return Err(HostError::format("delivery must be auto, steer, or queue"));
            }
            let input = SendInput {
                client_message_id,
                text: optional_string(payload, "text")?.unwrap_or_default(),
                attachments: validated_attachments.unwrap_or_default(),
                delivery,
                model: optional_string(payload, "model")?,
                reasoning_effort: optional_string(payload, "reasoningEffort")?,
                interaction_mode: optional_string(payload, "interactionMode")?,
                runtime_mode_ceiling: None,
                origin: None,
            };
            let operation = match decline_request_ids(payload)? {
                Some(request_ids) => ChatOp::SendDecliningRequests { input, request_ids },
                None => ChatOp::Send(input),
            };
            runtime
                .command(
                    &chat_id,
                    operation,
                    ctx,
                    Some(receipt_from_send(payload, request_type)?),
                )
                .await
        }
        "agentChat.queueCancel" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::QueueCancel {
                        queue_id: required_string(payload, "queueId")?,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.queueSteer" | "agentChat.queueEdit" => {
            let request_id = required_string(payload, "requestId")?;
            let queue_id = required_string(payload, "queueId")?;
            let operation = if request_type == "agentChat.queueSteer" {
                ChatOp::QueuePromoteToSteer {
                    queue_id,
                    turn_id: required_string(payload, "turnId")?,
                }
            } else {
                ChatOp::QueueEdit {
                    queue_id,
                    text: optional_string(payload, "text")?.unwrap_or_default(),
                }
            };
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    operation,
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.queueReorder" => {
            let request_id = required_string(payload, "requestId")?;
            let index = payload
                .get("index")
                .and_then(Value::as_u64)
                .ok_or_else(|| HostError::format("index must be a non-negative integer"))?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::QueueReorder {
                        queue_id: required_string(payload, "queueId")?,
                        index: usize::try_from(index).unwrap_or(usize::MAX),
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.approvalHistory" => {
            let limit = payload
                .get("limit")
                .and_then(Value::as_u64)
                .unwrap_or(100)
                .clamp(1, 500) as usize;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::ApprovalHistory {
                        before: optional_string(payload, "before")?,
                        limit,
                    },
                    ctx,
                    None,
                )
                .await
        }
        "agentChat.turnDiff" => {
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::TurnDiff {
                        turn_id: required_string(payload, "turnId")?,
                    },
                    ctx,
                    None,
                )
                .await
        }
        "agentChat.fork" | "agentChat.rewind" | "agentChat.delete" => {
            let request_id = required_string(payload, "requestId")?;
            let chat_id = required_string(payload, "chatId")?;
            let key = Some(receipt(&request_id, request_type, payload));
            match request_type {
                "agentChat.fork" => {
                    runtime
                        .fork(
                            &chat_id,
                            &required_string(payload, "turnId")?,
                            optional_string(payload, "title")?,
                            ctx,
                            key,
                        )
                        .await
                }
                "agentChat.rewind" => {
                    let turn_id = required_string(payload, "turnId")?;
                    match optional_string(payload, "mode")?
                        .as_deref()
                        .unwrap_or("transcript")
                    {
                        "transcript" => runtime.rewind(&chat_id, &turn_id, ctx, key).await,
                        "native" => {
                            runtime
                                .command(&chat_id, ChatOp::NativeRewind { turn_id }, ctx, key)
                                .await
                        }
                        _ => Err(HostError::format("mode must be transcript or native")),
                    }
                }
                _ => runtime.delete(&chat_id, ctx, key).await,
            }
        }
        "agentChat.skills" => {
            runtime
                .skills(
                    &required_string(payload, "chatId")?,
                    payload
                        .get("refresh")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                    ctx,
                )
                .await
        }
        "agentChat.markRead" => {
            let request_id = required_string(payload, "requestId")?;
            let cursor = payload
                .get("cursor")
                .and_then(Value::as_i64)
                .ok_or_else(|| HostError::format("cursor must be an integer"))?;
            runtime
                .mark_read(
                    &required_string(payload, "chatId")?,
                    cursor,
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.rewindFiles"
        | "agentChat.fileCheckpoints.configure"
        | "agentChat.nativeHistory.reconcile" => {
            let request_id = required_string(payload, "requestId")?;
            let op = match request_type {
                "agentChat.rewindFiles" => ChatOp::NativeRewindFiles {
                    turn_id: required_string(payload, "turnId")?,
                },
                "agentChat.fileCheckpoints.configure" => ChatOp::NativeFileCheckpoints {
                    enabled: payload
                        .get("enabled")
                        .and_then(Value::as_bool)
                        .ok_or_else(|| HostError::format("enabled must be a boolean"))?,
                },
                _ => ChatOp::NativeHistoryReconcile {
                    operation_id: required_string(payload, "operationId")?,
                    expected_revision: payload
                        .get("expectedRevision")
                        .map(|value| {
                            value.as_i64().ok_or_else(|| {
                                HostError::format("expectedRevision must be an integer")
                            })
                        })
                        .transpose()?,
                    action: required_string(payload, "action")?,
                },
            };
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    op,
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.nativeHistory.operation" => {
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::NativeHistoryOperation {
                        operation_id: optional_string(payload, "operationId")?,
                    },
                    ctx,
                    None,
                )
                .await
        }
        "agentChat.interrupt" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::Interrupt {
                        turn_id: optional_string(payload, "turnId")?,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.respond" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::Respond {
                        runtime_request_id: required_string(payload, "runtimeRequestId")?,
                        response: payload
                            .get("response")
                            .cloned()
                            .ok_or_else(|| HostError::format("response is required"))?,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.configure" => {
            let request_id = required_string(payload, "requestId")?;
            let model = if payload.get("model").is_some() {
                Some(optional_string(payload, "model")?)
            } else {
                None
            };
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::Configure(ConfigureInput {
                        provider: optional_string(payload, "provider")?,
                        provider_instance_id: optional_string(payload, "providerInstanceId")?,
                        model,
                        reasoning_effort: payload
                            .get("reasoningEffort")
                            .map(|_| optional_string(payload, "reasoningEffort"))
                            .transpose()?,
                        runtime_mode: optional_string(payload, "runtimeMode")?,
                        interaction_mode: optional_string(payload, "interactionMode")?,
                    }),
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.rename" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::Rename {
                        title: required_string(payload, "title")?,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.recover" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::Recover {
                        mode: optional_string(payload, "mode")?,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.close" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::Close,
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        _ => Err(HostError::format(format!(
            "Unknown agent chat request: {request_type}"
        ))),
    }
}

fn receipt(request_id: &str, verb: &str, payload: &Value) -> ReceiptKey {
    ReceiptKey {
        verb: verb.to_string(),
        request_id: request_id.to_string(),
        digest: payload_digest(payload),
    }
}

fn receipt_from_send(payload: &Value, verb: &str) -> HostResult<ReceiptKey> {
    let request_id = optional_string(payload, "requestId")?
        .or_else(|| {
            payload
                .get("clientMessageId")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .ok_or_else(|| HostError::format("requestId is required"))?;
    Ok(receipt(&request_id, verb, payload))
}
