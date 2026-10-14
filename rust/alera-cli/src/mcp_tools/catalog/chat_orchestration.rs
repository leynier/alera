//! The MCP surface available to an agent chat's injected server.
//!
//! These tools intentionally use the chat_ prefix and never expose the
//! terminal orchestration catalog. The runtime host binds every invocation to
//! the credentialed caller chat and applies its mode ceiling.

use serde_json::{json, Value};

use super::{execute, read};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

const RUNTIME_MODES: &[&str] = &[
    "approval-required",
    "auto-accept-edits",
    "auto",
    "full-access",
];
const INTERACTION_MODES: &[&str] = &["default", "plan"];
const DELIVERY_MODES: &[&str] = &["auto", "queue"];
const NOTIFY_MODES: &[&str] = &["always", "settled_only", "never"];

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "chat_capabilities",
            "Chat Orchestration Capabilities",
            "Show the chat orchestration actions and supported target strategies.",
            || object(&[], &[]),
            |_| Ok(Invocation::new("chat", &["capabilities"])),
        ),
        read(
            "chat_list",
            "List Agent Chats",
            "List agent chats and delegated lineage visible to the credentialed caller.",
            || {
                object(
                    &[
                        ("workspaceId", string("Restrict chats to a workspace.")),
                        ("projectId", string("Restrict chats to a project.")),
                        ("hostId", string("Restrict chats to a host.")),
                        ("includeArchived", boolean("Include archived chats.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["list"])
                    .option_if("--workspace-id", arguments.string("workspaceId"))
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--host-id", arguments.string("hostId"))
                    .flag_if("--include-archived", arguments.flag("includeArchived")))
            },
        ),
        read(
            "chat_read",
            "Read Agent Chat",
            "Read bounded user and assistant text plus canonical plans from a child chat.",
            || {
                object(
                    &[
                        ("chatId", string("Chat id.")),
                        ("limit", integer("Maximum entries.", 1, 200)),
                    ],
                    &["chatId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["read"])
                    .option("--chat-id", arguments.required("chatId")?)
                    .option_if(
                        "--limit",
                        arguments.integer("limit").map(|value| value.to_string()),
                    ))
            },
        ),
        execute(
            "chat_delegate",
            "Delegate To Agent Chat",
            "Delegate a brief to an existing child chat, an existing workspace, or a new workspace. The child receives only this brief.",
            || {
                object(
                    &[
                        ("task", text("Brief sent to the child.", 65_536)),
                        ("target", target_schema()),
                        ("title", string("Optional task title.")),
                        ("role", string("Optional role label.")),
                        ("notify", one_of("Completion notification policy.", NOTIFY_MODES)),
                        ("mode", one_of("Wait mode.", &["async", "wait"])),
                        ("waitSeconds", integer("Bounded wait time.", 1, MAX_WAIT_SECONDS)),
                        ("agent", json!({"type": "object", "description": "Provider/model selection."})),
                        ("runtimeMode", one_of("Runtime policy ceiling.", RUNTIME_MODES)),
                        ("interactionMode", one_of("Interaction mode.", INTERACTION_MODES)),
                    ],
                    &["task", "target"],
                )
            },
            |arguments| {
                let invocation = Invocation::new("chat", &["delegate"])
                    .option("--target", object_json(arguments, "target")?)
                    .option_if("--title", arguments.string("title"))
                    .option_if("--role", arguments.string("role"))
                    .option_if("--notify", arguments.string("notify"))
                    .option(
                        "--mode",
                        arguments.string("mode").unwrap_or_else(|| "async".to_owned()),
                    )
                    .option_if(
                        "--wait-seconds",
                        arguments
                            .integer("waitSeconds")
                            .map(|value| value.min(MAX_WAIT_SECONDS).to_string()),
                    )
                    .option_if("--agent", object_json_optional(arguments, "agent")?)
                    .option_if("--runtime-mode", arguments.string("runtimeMode"))
                    .option_if("--interaction-mode", arguments.string("interactionMode"));
                Ok(invocation.flag("--task-stdin").stdin(arguments.required("task")?))
            },
        ),
        execute(
            "chat_send",
            "Send To Agent Chat",
            "Send a bounded message to a chat across known projects and hosts within the caller's runtime mode ceiling, optionally requesting a completion notification.",
            || {
                object(
                    &[
                        ("chatId", string("Chat id.")),
                        ("message", text("Message text.", 65_536)),
                        ("delivery", one_of("Delivery mode.", DELIVERY_MODES)),
                        ("expectReply", boolean("Request a completion notification.")),
                    ],
                    &["chatId", "message"],
                )
            },
            |arguments| {
                let invocation = Invocation::new("chat", &["send"])
                    .option("--chat-id", arguments.required("chatId")?)
                    .option_if(
                        "--delivery",
                        arguments
                            .string("delivery")
                            .or_else(|| Some("auto".to_owned())),
                    )
                    .flag_if("--expect-reply", arguments.flag("expectReply"));
                Ok(invocation.flag("--message-stdin").stdin(arguments.required("message")?))
            },
        ),
        ToolSpec {
            client_request_flag: Some("--request-id"),
            ..execute(
            "chat_task_status",
            "Read Chat Task",
            "Read one delegated task, its lineage, and its bounded result.",
            || {
                object(
                    &[
                        ("taskId", string("Task id.")),
                        ("acknowledge", boolean("Acknowledge delivered result.")),
                    ],
                    &["taskId"],
                )
            },
            |arguments| {
                if arguments.string(crate::mcp_tools::CLIENT_REQUEST_ID).is_some() && !arguments.flag("acknowledge") {
                    return Err(ToolInputError("clientRequestId requires acknowledge:true.".into()));
                }
                Ok(Invocation::new("chat", &["task"])
                    .option("--task-id", arguments.required("taskId")?)
                    .flag_if("--acknowledge", arguments.flag("acknowledge")))
            },
        )},
        read(
            "chat_task_wait",
            "Wait For Chat Task",
            "Wait for one or more tasks for at most 50 seconds, then call again with the same ids.",
            || {
                object(
                    &[
                        (
                            "taskIds",
                            json!({
                                "type": "array",
                                "items": {"type": "string", "minLength": 1},
                                "minItems": 1,
                                "description": "Task ids to wait for."
                            }),
                        ),
                        ("timeoutSeconds", integer("Wait time.", 1, MAX_WAIT_SECONDS)),
                        ("until", one_of("Return when any or all tasks settle.", &["any", "all"])),
                    ],
                    &["taskIds"],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["wait"])
                    .option(
                        "--task-id",
                        arguments
                            .list("taskIds")
                            .ok_or_else(|| ToolInputError("Missing array argument taskIds.".into()))?
                            .join(","),
                    )
                    .option_if(
                        "--timeout-seconds",
                        arguments
                            .integer("timeoutSeconds")
                            .map(|value| value.min(MAX_WAIT_SECONDS).to_string()),
                    )
                    .option_if("--until", arguments.string("until")))
            },
        ),
        read(
            "chat_task_list",
            "List Chat Tasks",
            "List delegated tasks with lineage, target, status, attention, and result delivery state.",
            || {
                object(
                    &[
                        ("parentChatId", string("Restrict tasks to one parent chat.")),
                        ("childChatId", string("Restrict tasks to one child chat.")),
                        ("rootTaskId", string("Restrict tasks to one lineage root task.")),
                        ("projectId", string("Restrict tasks to a project.")),
                        ("workspaceId", string("Restrict tasks to a workspace.")),
                        ("hostId", string("Restrict tasks to a host.")),
                        (
                            "statuses",
                            json!({"type":"array", "items":{"type":"string"}}),
                        ),
                        ("attention", boolean("Only tasks needing attention.")),
                        ("limit", integer("Maximum tasks.", 1, 200)),
                        (
                            "cursor",
                            json!({
                                "type": "integer",
                                "minimum": 0,
                                "description": "Continuation cursor returned as nextCursor."
                            }),
                        ),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["task-list"])
                    .option_if("--parent-chat-id", arguments.string("parentChatId"))
                    .option_if("--child-chat-id", arguments.string("childChatId"))
                    .option_if("--root-task-id", arguments.string("rootTaskId"))
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--workspace-id", arguments.string("workspaceId"))
                    .option_if("--host-id", arguments.string("hostId"))
                    .option_if(
                        "--status",
                        arguments.list("statuses").map(|values| values.join(",")),
                    )
                    .flag_if("--attention", arguments.flag("attention"))
                    .option_if(
                        "--limit",
                        arguments.integer("limit").map(|value| value.to_string()),
                    )
                    .option_if(
                        "--cursor",
                        arguments.integer("cursor").map(|value| value.to_string()),
                    ))
            },
        ),
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

fn target_schema() -> Value {
    json!({
        "type": "object",
        "description": "Exactly one target object: chat, workspace, or newWorkspace.",
        "minProperties": 1,
        "maxProperties": 1,
        "additionalProperties": false,
        "properties": {
            "chat": {"type": "object"},
            "workspace": {"type": "object"},
            "newWorkspace": {"type": "object"},
        },
    })
}

fn object_json(arguments: &ToolArguments, name: &str) -> Result<String, ToolInputError> {
    arguments
        .object(name)
        .map(|value| Value::Object(value.clone()).to_string())
        .ok_or_else(|| ToolInputError(format!("Missing object argument {name}.")))
}

fn object_json_optional(
    arguments: &ToolArguments,
    name: &str,
) -> Result<Option<String>, ToolInputError> {
    Ok(arguments
        .object(name)
        .map(|value| Value::Object(value.clone()).to_string()))
}
