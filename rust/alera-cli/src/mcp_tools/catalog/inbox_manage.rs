//! Inbox maintenance and agent conversations.

use super::{
    admin, execute, no_arguments, read, wait_schema, wait_seconds, MCP_INBOX, WAIT_TIMEOUT,
};
use crate::mcp_tools::schema::{integer, object, one_of, string};
use crate::mcp_tools::{Invocation, ToolSpec};

const CURSOR_MAX: u64 = u64::MAX >> 11;

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_inbox",
                "Wait For Inbox",
                "Wait up to timeoutSeconds for any new reply or message in the shared MCP inbox, so one call covers every open question. By default only replies to questions this MCP client asked count. Pass the returned cursor as after to skip what was already seen. Each message carries threadId, origin, and isOwn.",
                || {
                    object(
                        &[
                            ("after", integer("Cursor from a previous result (default 0).", 0, CURSOR_MAX)),
                            ("scope", one_of("own (default): only threads this MCP client asked. all: every client's threads. Not used with threadId.", &["own", "all"])),
                            ("threadId", string("Only news in this thread, by any question id in it.")),
                            ("timeoutSeconds", wait_schema()),
                        ],
                        &[],
                    )
                },
                |arguments| {
                    let invocation = Invocation::new("inbox", &["wait"]).option("--inbox", MCP_INBOX);
                    let invocation = match arguments.string("threadId") {
                        Some(thread) => invocation.option("--question", thread),
                        None => invocation.option(
                            "--scope",
                            arguments.string("scope").unwrap_or_else(|| "own".into()),
                        ),
                    };
                    Ok(invocation
                        .option_if("--after", arguments.integer("after").map(|value| value.to_string()))
                        .option("--timeout", format!("{}s", wait_seconds(arguments, 30))))
                },
            )
        },
        execute(
            "cancel_question",
            "Cancel Question",
            "Cancel a question asked with ask_agent before it reaches the agent. A question the agent already received cannot be cancelled.",
            || object(&[("questionId", string("Question id returned by ask_agent."))], &["questionId"]),
            |arguments| {
                Ok(Invocation::new("inbox", &["cancel"])
                    .option("--question", arguments.required("questionId")?))
            },
        ),
        ToolSpec {
            idempotent: true,
            ..execute(
                "mark_thread_read",
                "Mark Thread Read",
                "Mark every reply in a question thread as read for all clients sharing the inbox.",
                || object(&[("questionId", string("Any question id in the thread."))], &["questionId"]),
                |arguments| {
                    Ok(Invocation::new("inbox", &["read"])
                        .option("--question", arguments.required("questionId")?))
                },
            )
        },
        read(
            "list_inboxes",
            "List Inboxes",
            "List the external inboxes, such as the shared MCP inbox and the one the Alera apps use, with their thread, pending, awaiting reply, and unread counts.",
            no_arguments,
            |_| Ok(Invocation::new("inbox", &["list"])),
        ),
        read(
            "list_agent_conversations",
            "List Agent Conversations",
            "List conversations between agents, newest first, optionally for one workspace or one participating terminal.",
            || {
                object(
                    &[
                        ("workspaceId", string("Workspace id.")),
                        ("participant", string("Terminal handle that took part.")),
                        ("limit", integer("Maximum conversations (default 50).", 1, 200)),
                        ("before", integer("Continue from the nextBefore value of a previous listing.", 0, CURSOR_MAX)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("inbox", &["conversations"])
                    .option_if("--workspace", arguments.string("workspaceId"))
                    .option_if("--participant", arguments.string("participant"))
                    .option_if("--limit", arguments.integer("limit").map(|value| value.to_string()))
                    .option_if("--before", arguments.integer("before").map(|value| value.to_string())))
            },
        ),
        read(
            "show_agent_conversation",
            "Show Agent Conversation",
            "Show every message of one conversation between agents.",
            || object(&[("threadId", string("Conversation thread id from list_agent_conversations."))], &["threadId"]),
            |arguments| {
                Ok(Invocation::new("inbox", &["conversation"])
                    .option("--thread", arguments.required("threadId")?))
            },
        ),
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..admin(
                "purge_inbox",
                "Purge MCP Inbox",
                "Delete every question and reply of the shared MCP inbox, including the threads other MCP clients asked.",
                no_arguments,
                |_| {
                    Ok(Invocation::new("inbox", &["purge"])
                        .option("--inbox", MCP_INBOX)
                        .flag("--confirm"))
                },
            )
        },
    ]
}
