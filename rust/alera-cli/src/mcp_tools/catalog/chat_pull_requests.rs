//! Pull requests linked to the chat (`chatOrchestrationPullRequestsV1`),
//! ported from T3 Code: link, unlink, list, watch and unwatch. A watch wakes
//! the chat with a message on failed or passed checks, new comments or a
//! conflict; delegated children link but never watch.

use super::{execute, read};
use crate::mcp_tools::schema::{object, string};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

fn target() -> serde_json::Value {
    object(
        &[
            ("url", string("The pull request's full web URL.")),
            ("chatId", string("Chat id; this chat when omitted.")),
        ],
        &["url"],
    )
}

fn invocation(action: &str, arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("chat", &["pr", action])
        .option("--url", arguments.required("url")?)
        .option_if("--chat-id", arguments.string("chatId")))
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        execute(
            "link_pull_request",
            "Link Pull Request",
            "Link a PR to this chat. Alera shows it with the chat. Link each PR you create, take over, or push to, as your next call; skip PRs you only read or review.",
            target,
            |arguments| invocation("link", arguments),
        ),
        execute(
            "unlink_pull_request",
            "Unlink Pull Request",
            "Remove a PR link from this chat. Succeeds with wasLinked=false when it was not linked.",
            target,
            |arguments| invocation("unlink", arguments),
        ),
        read(
            "list_chat_pull_requests",
            "List Chat Pull Requests",
            "List PRs linked to a chat and whether each is watched. Call only when you need that list, never as an end-of-work check.",
            || object(&[("chatId", string("Chat id; this chat when omitted."))], &[]),
            |arguments| {
                Ok(Invocation::new("chat", &["pr", "list"])
                    .option_if("--chat-id", arguments.string("chatId")))
            },
        ),
        execute(
            "watch_pull_request",
            "Watch Pull Request",
            "Watch an open PR for this chat, linking it first if needed. Alera wakes you on failed checks, passed checks, new comments or reviews, or conflicts. Handle old comments first; only later ones wake you. After this call, end your turn. The watch stays on after each wake, so do not call this again on a wake. A wake is not a merge decision: check readiness yourself. Delegated children never watch. For PR waits, no sleep, loops or gh --watch.",
            target,
            |arguments| invocation("watch", arguments),
        ),
        execute(
            "unwatch_pull_request",
            "Unwatch Pull Request",
            "Stop watching a PR for this chat. It stays linked. Call it before you hand the work back.",
            target,
            |arguments| invocation("unwatch", arguments),
        ),
    ]
}
