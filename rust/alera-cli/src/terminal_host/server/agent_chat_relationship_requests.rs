//! Thread relationship verbs: a provider-native sub-agent read and stopped on
//! its own (`agentChatSubagentThreadsV1`) and a fork merged back into the chat
//! it was forked from (`agentChatMergeBackV1`), and a workflow's script and
//! member answers read (`agentChatWorkflowsV1`).

use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_deferred::receipt;
use super::agent_chat_runtime::commands::{required_string, CallerCtx, ChatOp};
use super::agent_chat_runtime::AgentChatRuntime;

pub(super) async fn dispatch(
    runtime: AgentChatRuntime,
    request_type: &str,
    payload: &Value,
    ctx: CallerCtx,
) -> HostResult<Value> {
    match request_type {
        "agentChat.subagent" => {
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::SubagentTranscript {
                        item_id: required_string(payload, "itemId")?,
                    },
                    ctx,
                    None,
                )
                .await
        }
        "agentChat.stopSubagent" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::StopSubagent {
                        item_id: required_string(payload, "itemId")?,
                    },
                    ctx,
                    Some(receipt(&request_id, request_type, payload)),
                )
                .await
        }
        "agentChat.workflowScript" => {
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::WorkflowScript {
                        item_id: required_string(payload, "itemId")?,
                    },
                    ctx,
                    None,
                )
                .await
        }
        "agentChat.workflowAgent" => {
            let agent_index = payload
                .get("agentIndex")
                .and_then(Value::as_u64)
                .ok_or_else(|| HostError::format("agentIndex must be a non-negative integer"))?;
            runtime
                .command(
                    &required_string(payload, "chatId")?,
                    ChatOp::WorkflowAgent {
                        item_id: required_string(payload, "itemId")?,
                        agent_index,
                    },
                    ctx,
                    None,
                )
                .await
        }
        "agentChat.mergeBack" => {
            let request_id = required_string(payload, "requestId")?;
            runtime
                .merge_back(
                    &required_string(payload, "chatId")?,
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
