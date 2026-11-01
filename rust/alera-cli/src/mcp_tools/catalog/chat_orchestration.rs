//! The MCP surface available to an agent chat's injected server: discovery,
//! delegation, messages, and task reads. The tools that steer running work
//! live in `chat_orchestration_control`.
//!
//! These tools intentionally use the chat_ prefix and never expose the
//! terminal orchestration catalog. The runtime host binds every invocation to
//! the credentialed caller chat and applies its mode ceiling.

use serde_json::json;

use super::chat_schema::{
    object_json, object_json_optional, target_schema, INTERACTION_MODES, RUNTIME_MODES,
};
use super::{execute, read};
use crate::mcp_tools::schema::{boolean, clamped_integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

const DELIVERY_MODES: &[&str] = &["auto", "queue"];
const NOTIFY_MODES: &[&str] = &["always", "settled_only", "never"];

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "chat_capabilities",
            "Chat Orchestration Capabilities",
            "Show the chat orchestration actions, target strategies and providers. Each provider lists a few models, its pinned ones always included; omittedModels counts the rest. Pass search to find a model by id or label.",
            || {
                object(
                    &[
                        ("search", text("Words every listed model's id or label must contain.", 200)),
                        ("workspaceId", string("List the providers of this workspace's host.")),
                        ("hostId", string("List the providers of this host.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["capabilities"])
                    .option_if("--search", arguments.string("search"))
                    .option_if("--workspace-id", arguments.string("workspaceId"))
                    .option_if("--host-id", arguments.string("hostId")))
            },
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
                        ("limit", clamped_integer("Maximum entries.", 1, 200)),
                    ],
                    &["chatId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("chat", &["read"])
                    .option("--chat-id", arguments.required("chatId")?)
                    .option_if(
                        "--limit",
                        arguments
                            .integer_at_most("limit", 200)
                            .map(|value| value.to_string()),
                    ))
            },
        ),
        execute(
            "chat_delegate",
            "Delegate To Agent Chat",
            "Delegate a brief to an existing child chat, an existing workspace, or a new workspace. The child receives only this brief. With mode async the task's completion wakes this chat with its result: follow next and end your turn instead of waiting or polling.",
            || {
                object(
                    &[
                        ("task", text("Brief sent to the child.", 65_536)),
                        ("target", target_schema()),
                        ("title", string("Optional task title.")),
                        ("role", string("Optional role label.")),
                        ("notify", one_of("Completion notification policy: always and settled_only wake this chat with the result; never does not, so read it with chat_task_status.", NOTIFY_MODES)),
                        ("mode", one_of("Wait mode.", &["async", "wait"])),
                        ("waitSeconds", clamped_integer("Bounded wait time.", 1, MAX_WAIT_SECONDS)),
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
                            .integer_at_most("waitSeconds", MAX_WAIT_SECONDS)
                            .map(|value| value.to_string()),
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
            "Read one delegated task, its lineage, and its bounded result. Do not poll a running task that will wake this chat; its next field says so.",
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
            "Wait for one or more tasks for at most 50 seconds. Use it only when this turn cannot go on without the result; a delegated task wakes this chat when it settles, so otherwise end your turn.",
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
                        ("timeoutSeconds", clamped_integer("Wait time.", 1, MAX_WAIT_SECONDS)),
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
                            .integer_at_most("timeoutSeconds", MAX_WAIT_SECONDS)
                            .map(|value| value.to_string()),
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
                        ("limit", clamped_integer("Maximum tasks.", 1, 200)),
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
                        arguments
                            .integer_at_most("limit", 200)
                            .map(|value| value.to_string()),
                    )
                    .option_if(
                        "--cursor",
                        arguments.integer("cursor").map(|value| value.to_string()),
                    ))
            },
        ),
    ]
}
