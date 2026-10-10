//! Questions an MCP client asks running agents, and their replies.

use super::{execute, read, wait_schema, wait_seconds, MCP_INBOX, PROMPT_LIMIT, WAIT_TIMEOUT};
use crate::mcp_tools::schema::{integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolInputError, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_inbox_targets",
            "List Askable Agents",
            "List running agents that ask_agent can reach, optionally for one workspace.",
            || object(&[("workspaceId", string("Workspace id."))], &[]),
            |arguments| {
                Ok(Invocation::new("inbox", &["targets"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "list_inbox_threads",
            "List Question Threads",
            "List question threads asked through ask_agent by every MCP client sharing this inbox, newest first. Each thread carries origin, the MCP client that asked, and isOwn, whether this client asked it.",
            || {
                object(
                    &[
                        ("scope", one_of("own: only threads this MCP client asked. all (default): every client's threads.", &["all", "own"])),
                        ("originClientId", string("Only threads asked by this MCP client id, from a thread's origin.clientId.")),
                        ("status", one_of("Thread status.", &["pending", "received", "delivered", "expired", "answered", "cancelled"])),
                        ("workspaceId", string("Workspace id.")),
                        ("limit", integer("Maximum threads (default 50).", 1, 200)),
                        ("before", integer("Continue from the nextBefore value of a previous listing.", 0, u64::MAX >> 11)),
                    ],
                    &[],
                )
            },
            |arguments| {
                if arguments.string("originClientId").is_some() && arguments.string("scope").is_some() {
                    return Err(ToolInputError("Pass scope or originClientId, not both.".into()));
                }
                Ok(Invocation::new("inbox", &["threads"])
                    .option("--inbox", MCP_INBOX)
                    .option_if("--scope", arguments.string("scope"))
                    .option_if("--origin-client-id", arguments.string("originClientId"))
                    .option_if("--status", arguments.string("status"))
                    .option_if("--workspace", arguments.string("workspaceId"))
                    .option_if("--limit", arguments.integer("limit").map(|value| value.to_string()))
                    .option_if("--before", arguments.integer("before").map(|value| value.to_string())))
            },
        ),
        read(
            "show_inbox_thread",
            "Show Question Thread",
            "Show a question thread with every question and reply.",
            || object(&[("questionId", string("Any question id in the thread."))], &["questionId"]),
            |arguments| {
                Ok(Invocation::new("inbox", &["show"])
                    .option("--question", arguments.required("questionId")?))
            },
        ),
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_reply",
                "Wait For Reply",
                "Wait up to timeoutSeconds for news about a question asked with ask_agent. Pass the returned cursor as after to skip what was already seen.",
                || {
                    object(
                        &[
                            ("questionId", string("Question id returned by ask_agent.")),
                            ("after", integer("Cursor from a previous result.", 0, u64::MAX >> 11)),
                            ("timeoutSeconds", wait_schema()),
                        ],
                        &["questionId"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("inbox", &["wait"])
                        .option("--inbox", MCP_INBOX)
                        .option("--question", arguments.required("questionId")?)
                        .option_if("--after", arguments.integer("after").map(|value| value.to_string()))
                        .option("--timeout", format!("{}s", wait_seconds(arguments, 30))))
                },
            )
        },
        ToolSpec {
            client_request_flag: Some("--request-key"),
            ..execute(
                "ask_agent",
                "Ask Agent",
                "Ask a running agent a question by terminal handle, or the single agent of a workspace. The agent sees which MCP client asked. Returns the question id, its thread id, and the recorded origin; follow it with wait_for_reply or wait_for_inbox.",
                || {
                    object(
                        &[
                            ("body", text("The question.", PROMPT_LIMIT)),
                            ("to", string("Terminal handle of the agent.")),
                            ("workspaceId", string("Ask the single running agent of this workspace.")),
                            ("agent", string("With workspaceId, only agents of this type (claude, codex, ...).")),
                            ("threadId", string("Continue an earlier question's thread.")),
                            ("subject", string("Short subject.")),
                            ("priority", one_of("Priority.", &["normal", "high", "urgent"])),
                            ("expiresIn", string("Drop the question if undelivered in time, such as 30m or 2h.")),
                        ],
                        &["body"],
                    )
                },
                |arguments| {
                    let named = [arguments.string("to"), arguments.string("workspaceId"), arguments.string("threadId")]
                        .iter()
                        .filter(|value| value.is_some())
                        .count();
                    if named > 1 {
                        return Err(ToolInputError("Pass only one of to, workspaceId, or threadId.".into()));
                    }
                    if arguments.string("agent").is_some() && arguments.string("workspaceId").is_none() {
                        return Err(ToolInputError("agent needs workspaceId.".into()));
                    }
                    Ok(Invocation::new("inbox", &["ask"])
                        .option("--inbox", MCP_INBOX)
                        .option_if("--to", arguments.string("to"))
                        .option_if("--workspace", arguments.string("workspaceId"))
                        .option_if("--agent", arguments.string("agent"))
                        .option_if("--thread", arguments.string("threadId"))
                        .option_if("--subject", arguments.string("subject"))
                        .option_if("--priority", arguments.string("priority"))
                        .option_if("--expires-in", arguments.string("expiresIn"))
                        .flag("--body-stdin")
                        .stdin(arguments.required("body")?))
                },
            )
        },
    ]
}
