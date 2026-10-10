use clap::{Args, Subcommand, ValueEnum};

use crate::cli::{OutputArgs, RuntimeDirArgs};

/// Ask agents questions from outside a terminal and read their replies.
#[derive(Debug, Args)]
pub struct InboxCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: InboxAction,
}

#[derive(Debug, Subcommand)]
pub enum InboxAction {
    /// List running agents that can be asked, with how a question reaches them.
    Targets(InboxTargetsArgs),
    /// Ask an agent a question. Prints the question id to wait on.
    Ask(InboxAskArgs),
    /// List inboxes with their counts.
    List,
    /// List question threads.
    Threads(InboxThreadsArgs),
    /// Show a thread with every question and reply.
    Show(InboxShowArgs),
    /// Wait for a reply to a question, or for anything new sent to an inbox.
    Wait(InboxWaitArgs),
    /// Cancel a question that has not reached the agent yet.
    Cancel(InboxQuestionArgs),
    /// Mark the replies in a thread as read.
    Read(InboxShowArgs),
    /// Delete an inbox and every thread it started.
    Purge(InboxPurgeArgs),
    /// List conversations between agents (read only).
    Conversations(InboxConversationsArgs),
    /// Show one conversation between agents (read only).
    Conversation(InboxConversationArgs),
}

#[derive(Debug, Args)]
pub struct InboxConversationsArgs {
    /// Only conversations in this workspace.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// Only conversations this terminal took part in.
    #[arg(long = "participant", value_name = "handle")]
    pub participant: Option<String>,
    /// Maximum conversations returned (default 50).
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<i64>,
    /// Continue a listing from the `nextBefore` value it returned.
    #[arg(long = "before", value_name = "sequence")]
    pub before: Option<i64>,
}

#[derive(Debug, Args)]
pub struct InboxConversationArgs {
    #[arg(long = "thread", value_name = "thread_id")]
    pub thread: String,
}

#[derive(Debug, Args)]
pub struct InboxAddressArgs {
    /// Inbox address (`ext:<name>`). Defaults to ALERA_EXTERNAL_INBOX, then `ext:user`.
    #[arg(long = "inbox", value_name = "ext:name")]
    pub inbox: Option<String>,
}

#[derive(Debug, Args)]
pub struct InboxTargetsArgs {
    /// Only agents in this workspace.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
}

#[derive(Debug, Args)]
pub struct InboxAskArgs {
    #[command(flatten)]
    pub address: InboxAddressArgs,
    /// Terminal handle of the agent to ask.
    #[arg(long = "to", value_name = "handle", conflicts_with = "workspace")]
    pub to: Option<String>,
    /// Ask the single running agent of this workspace.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// With --workspace, only agents of this type (claude, codex, ...).
    #[arg(long = "agent", value_name = "type", requires = "workspace")]
    pub agent: Option<String>,
    /// Continue an earlier question's thread with the same agent.
    #[arg(long = "thread", value_name = "question_id", conflicts_with_all = ["to", "workspace"])]
    pub thread: Option<String>,
    /// Short subject. Defaults to the first line of the body.
    #[arg(long = "subject", value_name = "text")]
    pub subject: Option<String>,
    /// Question body.
    #[arg(long = "body", value_name = "text", conflicts_with_all = ["body_file", "body_stdin"])]
    pub body: Option<String>,
    /// Read the question body from a file.
    #[arg(long = "body-file", value_name = "path", conflicts_with_all = ["body", "body_stdin"])]
    pub body_file: Option<String>,
    /// Read the question body from standard input.
    #[arg(long = "body-stdin", conflicts_with_all = ["body", "body_file"])]
    pub body_stdin: bool,
    /// normal, high (default) or urgent.
    #[arg(long = "priority", value_name = "level")]
    pub priority: Option<String>,
    /// Drop the question if it has not reached the agent in time, such as 30m or 2h (default 5h, at most 7d).
    #[arg(long = "expires-in", value_name = "duration", value_parser = parse_duration_ms)]
    pub expires_in_ms: Option<u64>,
    /// Retry key (8 to 128 characters): asking again with it returns the first question.
    #[arg(long = "request-key", value_name = "key")]
    pub request_key: Option<String>,
}

/// Whose threads an MCP client sees in the shared inbox.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum InboxScope {
    /// Only threads the calling MCP client started.
    Own,
    /// Every thread of the inbox.
    All,
}

#[derive(Debug, Args)]
pub struct InboxThreadsArgs {
    #[command(flatten)]
    pub address: InboxAddressArgs,
    /// Include threads from every inbox.
    #[arg(long = "all-inboxes", conflicts_with = "inbox")]
    pub all_inboxes: bool,
    /// Only threads with agents of this workspace.
    #[arg(long = "workspace", value_name = "workspace_id")]
    pub workspace: Option<String>,
    /// pending, received, delivered, expired, answered or cancelled.
    #[arg(long = "status", value_name = "status")]
    pub status: Option<String>,
    /// Maximum threads returned (default 50).
    #[arg(long = "limit", value_name = "n")]
    pub limit: Option<i64>,
    /// Continue a listing from the `nextBefore` value it returned.
    #[arg(long = "before", value_name = "sequence")]
    pub before: Option<i64>,
    /// Only threads started by this MCP client id.
    #[arg(long = "origin-client-id", value_name = "id", conflicts_with = "scope")]
    pub origin_client_id: Option<String>,
    /// own: only threads the calling MCP client started (default all).
    #[arg(long = "scope", value_enum)]
    pub scope: Option<InboxScope>,
}

#[derive(Debug, Args)]
pub struct InboxShowArgs {
    /// Any question in the thread.
    #[arg(long = "question", value_name = "question_id")]
    pub question: String,
}

#[derive(Debug, Args)]
pub struct InboxWaitArgs {
    #[command(flatten)]
    pub address: InboxAddressArgs,
    /// Wait for news about this question.
    #[arg(long = "question", value_name = "question_id")]
    pub question: Option<String>,
    /// Only report messages after this cursor (from a previous result).
    #[arg(long = "after", value_name = "cursor", default_value_t = 0)]
    pub after: i64,
    /// How long to wait, such as 90s, 30m or 2h (default 10m).
    #[arg(long = "timeout", value_name = "duration", value_parser = parse_duration_ms)]
    pub timeout_ms: Option<u64>,
    /// Inbox waits only. own: only replies in threads the calling MCP client started.
    #[arg(long = "scope", value_enum, conflicts_with = "question")]
    pub scope: Option<InboxScope>,
}

#[derive(Debug, Args)]
pub struct InboxQuestionArgs {
    #[arg(long = "question", value_name = "question_id")]
    pub question: String,
}

#[derive(Debug, Args)]
pub struct InboxPurgeArgs {
    #[command(flatten)]
    pub address: InboxAddressArgs,
    /// Required: purging deletes the inbox's questions and replies.
    #[arg(long = "confirm")]
    pub confirm: bool,
}

/// Accepts `500ms`, `90s`, `30m`, `5h`, `7d`, or a bare number of seconds.
pub fn parse_duration_ms(value: &str) -> Result<u64, String> {
    let value = value.trim();
    let split = value
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(value.len());
    let (number, unit) = value.split_at(split);
    let number: u64 = number
        .parse()
        .map_err(|_| format!("invalid duration `{value}`; use forms like 90s, 30m or 2h"))?;
    let factor = match unit {
        "ms" => 1,
        "" | "s" => 1_000,
        "m" => 60_000,
        "h" => 3_600_000,
        "d" => 86_400_000,
        _ => {
            return Err(format!(
                "invalid duration unit in `{value}`; use ms, s, m, h or d"
            ))
        }
    };
    number
        .checked_mul(factor)
        .filter(|ms| *ms > 0)
        .ok_or_else(|| format!("duration `{value}` must be positive and reasonable"))
}
