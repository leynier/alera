//! The injected chat tools that steer delegated work after it starts: cancel
//! a task, interrupt a turn, mark background work, answer a child chat's open
//! requests, and configure a child chat. Like the rest of the `chat_*`
//! catalog, every call is bound to the credentialed caller chat.

use serde_json::json;

use super::chat_schema::{object_json, INTERACTION_MODES, RUNTIME_MODES};
use super::{execute, read};
use crate::mcp_tools::schema::{boolean, object, one_of, string};
use crate::mcp_tools::{Invocation, ToolInputError, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        execute(
            "chat_task_cancel",
            "Cancel Chat Task",
            "Cancel a delegated task, its queued input, and descendants.",
            || {
                object(
                    &[
                        ("taskId", string("Task id.")),
                        ("reason", string("Why the task is cancelled.")),
                    ],
                    &["taskId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["cancel"])
                    .option("--task-id", arguments.required("taskId")?)
                    .option_if("--reason", arguments.string("reason")))
            },
        ),
        execute(
            "chat_interrupt",
            "Interrupt Agent Chat",
            "Interrupt the active child turn without archiving its chat.",
            || {
                object(
                    &[
                        ("chatId", string("Chat id.")),
                        ("turnId", string("Optional active turn id.")),
                    ],
                    &["chatId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["interrupt"])
                    .option("--chat-id", arguments.required("chatId")?)
                    .option_if("--turn-id", arguments.string("turnId")))
            },
        ),
        ToolSpec {
            // Marking the same tasks twice leaves the same marks.
            idempotent: true,
            ..execute(
            "chat_background_wait",
            "Wait On Background Work",
            "Keep this chat working while you wait for a background command or Monitor you started. Call this before you end your turn if you will act on its result when it wakes you. In taskIds, give the IDs shown when the tasks started. The chat stays working until the task ends. Do not mark work you leave running, such as a dev server or watcher; unmarked commands never keep the chat working. Pass waiting=false to remove the mark; this does not stop the task. IDs that are not running return in unmatched and change nothing. Only Claude chats support this tool; other providers return an invalid request error.",
            || {
                object(
                    &[
                        (
                            "taskIds",
                            json!({
                                "type": "array",
                                "items": {"type": "string", "minLength": 1},
                                "minItems": 1,
                                "maxItems": 20,
                                "description": "Background task ids to mark."
                            }),
                        ),
                        ("waiting", boolean("Mark (default true) or remove the mark.")),
                    ],
                    &["taskIds"],
                )
            },
            |arguments| {
                let task_ids = arguments
                    .list("taskIds")
                    .ok_or_else(|| ToolInputError("Missing array argument taskIds.".into()))?;
                if task_ids.is_empty()
                    || task_ids.len() > 20
                    || task_ids.iter().any(|id| id.trim().is_empty())
                {
                    return Err(ToolInputError(
                        "taskIds must hold 1 to 20 nonempty task ids.".into(),
                    ));
                }
                Ok(Invocation::new("chat", &["background-wait"])
                    .option("--task-id", task_ids.join(","))
                    .flag_if("--stop-waiting", arguments.optional_flag("waiting") == Some(false)))
            },
        )},
        read(
            "chat_requests",
            "List Chat Requests",
            "List open approval, user-input, and elicitation requests for a child chat.",
            || {
                object(
                    &[
                        ("chatId", string("Restrict requests to a chat.")),
                        ("taskId", string("Restrict requests to a task.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["requests"])
                    .option_if("--chat-id", arguments.string("chatId"))
                    .option_if("--task-id", arguments.string("taskId")))
            },
        ),
        execute(
            "chat_respond",
            "Respond To Chat Request",
            "Answer one open child-chat request using the exact offered decision or native response.",
            || {
                object(
                    &[
                        ("chatId", string("Chat id.")),
                        ("runtimeRequestId", string("Runtime request id.")),
                        ("response", json!({"type": "object", "description": "Runtime response object."})),
                    ],
                    &["chatId", "runtimeRequestId", "response"],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["respond"])
                    .option("--chat-id", arguments.required("chatId")?)
                    .option(
                        "--runtime-request-id",
                        arguments.required("runtimeRequestId")?,
                    )
                    .option("--response", object_json(arguments, "response")?))
            },
        ),
        execute(
            "chat_configure",
            "Configure Agent Chat",
            "Change an idle child chat's provider, model, or runtime policy.",
            || {
                object(
                    &[
                        ("chatId", string("Chat id.")),
                        ("provider", string("Provider slug.")),
                        ("providerInstanceId", string("Provider instance id.")),
                        ("model", string("Model id.")),
                        ("resetModel", boolean("Reset to the provider-default model.")),
                        ("reasoningEffort", string("Provider-supported reasoning effort id.")),
                        ("resetReasoningEffort", boolean("Reset to provider-default reasoning effort.")),
                        ("runtimeMode", one_of("Runtime policy.", RUNTIME_MODES)),
                        ("interactionMode", one_of("Interaction mode.", INTERACTION_MODES)),
                    ],
                    &["chatId"],
                )
            },
            |arguments| {
                if (arguments.flag("resetModel") && arguments.string("model").is_some())
                    || (arguments.flag("resetReasoningEffort") && arguments.string("reasoningEffort").is_some()) {
                    return Err(ToolInputError("A selection and its reset cannot be combined.".into()));
                }
                let invocation = Invocation::new("chat", &["configure"])
                    .option("--chat-id", arguments.required("chatId")?)
                    .option_if("--provider", arguments.string("provider"))
                    .option_if(
                        "--provider-instance-id",
                        arguments.string("providerInstanceId"),
                    )
                    .option_if("--model", arguments.string("model"))
                    .flag_if("--reset-model", arguments.flag("resetModel"))
                    .option_if("--reasoning-effort", arguments.string("reasoningEffort"))
                    .flag_if("--reset-reasoning-effort", arguments.flag("resetReasoningEffort"))
                    .option_if("--runtime-mode", arguments.string("runtimeMode"))
                    .option_if("--interaction-mode", arguments.string("interactionMode"));
                if !invocation.args.iter().any(|arg| {
                    arg.starts_with("--provider=")
                        || arg.starts_with("--provider-instance-id=")
                        || arg.starts_with("--model=")
                        || arg == "--reset-model"
                        || arg.starts_with("--reasoning-effort=")
                        || arg == "--reset-reasoning-effort"
                        || arg.starts_with("--runtime-mode=")
                        || arg.starts_with("--interaction-mode=")
                }) {
                    return Err(ToolInputError(
                        "Pass at least one configuration field.".into(),
                    ));
                }
                Ok(invocation)
            },
        ),
    ]
}
