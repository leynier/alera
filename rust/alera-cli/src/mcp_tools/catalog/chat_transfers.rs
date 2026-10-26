//! `chat_transfers`, T3 Code's `t3_thread_transfers`: the context moved into
//! a chat (forks, merge-backs, provider handoffs, delegated briefs and
//! results), for the credentialed caller's own chat when it names none.

use super::read;
use crate::mcp_tools::schema::{object, string};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![read(
        "chat_transfers",
        "Read Chat Context Transfers",
        "Read the context transfers recorded in a chat, newest first: forks, merge-backs, provider handoffs, delegated briefs and delegated results. Omit chatId for this chat.",
        || object(&[("chatId", string("Chat id; defaults to this chat."))], &[]),
        |arguments| {
            Ok(Invocation::new("chat", &["transfers"])
                .option_if("--chat-id", arguments.string("chatId")))
        },
    )]
}
