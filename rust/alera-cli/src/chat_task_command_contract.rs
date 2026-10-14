//! Exact human chat-task payloads shared by CLI and the public MCP catalog.

use serde_json::{json, Map, Value};

pub(crate) const QUERY_OPERATIONS: &[&str] = &[
    "capabilities",
    "list",
    "read",
    "task",
    "task-list",
    "wait",
    "requests",
];
pub(crate) const CONTROL_OPERATIONS: &[&str] =
    &["acknowledge", "cancel", "interrupt", "respond", "configure"];
pub(crate) const OPERATIONS: &[&str] = &[
    "capabilities",
    "list",
    "read",
    "task",
    "task-list",
    "wait",
    "requests",
    "delegate",
    "send",
    "acknowledge",
    "cancel",
    "interrupt",
    "respond",
    "configure",
];
pub(crate) const PERSON_PARENT_CAPABILITY: &str = "chatOrchestrationPersonParentV1";
pub(crate) const EFFORT_CAPABILITY: &str = "chatOrchestrationEffortV1";
const RUNTIME_MODES: &[&str] = &[
    "approval-required",
    "auto-accept-edits",
    "auto",
    "full-access",
];

pub(crate) fn verb(operation: &str) -> &str {
    match operation {
        "task-list" => "tasks.list",
        "acknowledge" => "task",
        other => other,
    }
}

pub(crate) fn is_mutation(operation: &str) -> bool {
    matches!(operation, "delegate" | "send") || CONTROL_OPERATIONS.contains(&operation)
}

pub(crate) fn object(properties: &[(&str, Value)], required: &[&str]) -> Value {
    let properties = properties
        .iter()
        .map(|(key, value)| ((*key).into(), value.clone()))
        .collect::<Map<String, Value>>();
    json!({"type":"object", "properties":properties, "required":required, "additionalProperties":false})
}

fn id() -> Value {
    json!({"type":"string", "minLength":1, "maxLength":4096})
}
fn boolean() -> Value {
    json!({"type":"boolean"})
}
fn choices(values: &[&str]) -> Value {
    json!({"type":"string", "enum":values})
}
fn number(minimum: u64, maximum: u64) -> Value {
    json!({"type":"integer", "minimum":minimum, "maximum":maximum})
}
fn texts(minimum: u64) -> Value {
    json!({"type":"array", "items":id(), "minItems":minimum, "maxItems":200})
}
fn reset() -> Value {
    json!({"type":["string","null"], "minLength":1, "maxLength":4096})
}

pub(crate) fn payload_schema(operation: &str) -> Value {
    match operation {
        "capabilities" => object(&[("workspaceId", id()), ("hostId", id())], &[]),
        "list" => object(
            &[
                ("workspaceId", id()),
                ("projectId", id()),
                ("hostId", id()),
                ("includeArchived", boolean()),
            ],
            &[],
        ),
        "read" => object(&[("chatId", id()), ("limit", number(1, 200))], &["chatId"]),
        "task" | "acknowledge" => object(&[("taskId", id())], &["taskId"]),
        "task-list" => {
            let mut statuses = texts(0);
            statuses["items"] = choices(&[
                "preparing",
                "running",
                "needs_input",
                "completed",
                "failed",
                "interrupted",
                "cancel_requested",
                "cancelled",
            ]);
            object(
                &[
                    ("parentChatId", id()),
                    ("childChatId", id()),
                    ("rootTaskId", id()),
                    ("workspaceId", id()),
                    ("projectId", id()),
                    ("hostId", id()),
                    ("statuses", statuses),
                    ("attention", boolean()),
                    ("limit", number(1, 200)),
                    ("cursor", number(0, i64::MAX as u64)),
                ],
                &[],
            )
        }
        "wait" => object(
            &[
                ("taskIds", texts(1)),
                ("waitSeconds", number(1, 50)),
                ("until", choices(&["any", "all"])),
            ],
            &["taskIds"],
        ),
        "requests" => {
            let mut schema = object(&[("chatId", id()), ("taskId", id())], &[]);
            schema["anyOf"] = json!([{"required":["chatId"]},{"required":["taskId"]}]);
            schema
        }
        "delegate" => object(
            &[
                (
                    "task",
                    json!({"type":"string","minLength":1,"maxLength":65536}),
                ),
                ("target", target_schema()),
                ("parentChatId", id()),
                ("title", id()),
                ("role", id()),
                ("notify", choices(&["always", "settled_only", "never"])),
                ("mode", choices(&["async", "wait"])),
                ("waitSeconds", number(1, 50)),
                ("agent", agent_schema()),
                ("runtimeMode", choices(RUNTIME_MODES)),
                ("interactionMode", choices(&["default", "plan"])),
            ],
            &["task", "target"],
        ),
        "send" => object(
            &[
                ("chatId", id()),
                (
                    "message",
                    json!({"type":"string","minLength":1,"maxLength":65536}),
                ),
                ("parentChatId", id()),
                ("delivery", choices(&["auto", "queue"])),
                ("expectReply", boolean()),
            ],
            &["chatId", "message"],
        ),
        "cancel" => object(&[("taskId", id()), ("reason", id())], &["taskId"]),
        "interrupt" => object(&[("chatId", id()), ("turnId", id())], &["chatId"]),
        "respond" => object(
            &[
                ("chatId", id()),
                ("runtimeRequestId", id()),
                ("response", json!({"type":"object"})),
            ],
            &["chatId", "runtimeRequestId", "response"],
        ),
        "configure" => {
            let mut schema = object(
                &[
                    ("chatId", id()),
                    ("provider", id()),
                    ("providerInstanceId", id()),
                    ("model", reset()),
                    ("reasoningEffort", reset()),
                    ("runtimeMode", choices(RUNTIME_MODES)),
                    ("interactionMode", choices(&["default", "plan"])),
                ],
                &["chatId"],
            );
            schema["anyOf"] = json!([{"required":["provider"]},{"required":["providerInstanceId"]},{"required":["model"]},{"required":["reasoningEffort"]},{"required":["runtimeMode"]},{"required":["interactionMode"]}]);
            schema
        }
        _ => unreachable!("operation is a closed CLI or MCP enum"),
    }
}

fn agent_schema() -> Value {
    object(
        &[
            ("providerInstanceId", id()),
            ("model", id()),
            (
                "options",
                object(
                    &[(
                        "reasoningEffort",
                        json!({"type":"string","minLength":1,"maxLength":128}),
                    )],
                    &[],
                ),
            ),
        ],
        &[],
    )
}

fn target_schema() -> Value {
    let mut new_workspace = object(
        &[
            ("projectId", id()),
            ("hostId", id()),
            ("mode", choices(&["worktree", "shared"])),
            ("branch", id()),
            ("sourceBranch", id()),
            ("reuseExistingBranch", boolean()),
            ("name", id()),
            ("parentWorkspaceId", id()),
            ("setup", choices(&["inline", "deferred"])),
        ],
        &["projectId", "hostId", "mode"],
    );
    new_workspace["oneOf"] = json!([
        {"properties":{"mode":{"enum":["worktree"]}},"required":["branch"]},
        {"properties":{"mode":{"enum":["shared"]}}},
    ]);
    let mut schema = object(
        &[
            ("chat", object(&[("chatId", id())], &["chatId"])),
            (
                "workspace",
                object(&[("workspaceId", id())], &["workspaceId"]),
            ),
            ("newWorkspace", new_workspace),
        ],
        &[],
    );
    schema["minProperties"] = json!(1);
    schema["maxProperties"] = json!(1);
    schema
}

pub(crate) fn tool_schema(operations: &[&str]) -> Value {
    let mut schema = object(
        &[
            ("operation", choices(operations)),
            (
                "payload",
                json!({"type":"object","description":"Exact canonical chatOrchestration fields for the selected operation; caller identity is host-derived. Request ids use clientRequestId outside this payload."}),
            ),
        ],
        &["operation", "payload"],
    );
    schema["oneOf"] = Value::Array(operations.iter().map(|operation| json!({
        "properties":{"operation":{"enum":[operation]},"payload":payload_schema(operation)},
        "required":["operation","payload"],
    })).collect());
    schema
}
