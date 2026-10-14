use clap::{ArgAction, Args, Subcommand};

use crate::cli::{OutputArgs, RuntimeDirArgs};

#[derive(Debug, Args)]
pub struct ChatCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: ChatAction,
}

#[derive(Debug, Subcommand)]
pub enum ChatAction {
    /// Submit an exact structured human task request; unavailable to bound agents.
    Human(crate::chat_task_commands::ChatHumanArgs),
    /// Show the chat orchestration capability and supported actions.
    Capabilities,
    /// List chat orchestration tasks and child chats.
    List(ChatListArgs),
    /// Read a bounded chat transcript for a task or chat.
    Read(ChatReadArgs),
    /// Delegate a brief to an existing or newly-created chat.
    Delegate(Box<ChatDelegateArgs>),
    /// Send a message to an existing child chat.
    Send(ChatSendArgs),
    /// Read one delegated task and its bounded result.
    Task(ChatTaskArgs),
    /// List delegated tasks, including lineage and delivery state.
    #[command(name = "task-list")]
    TaskList(ChatTaskListArgs),
    /// Wait for a task for at most 50 seconds.
    Wait(ChatWaitArgs),
    /// Cancel a task and its descendants.
    Cancel(ChatCancelArgs),
    /// Interrupt the active turn of a child chat.
    Interrupt(ChatInterruptArgs),
    /// List open runtime requests for a child chat.
    Requests(ChatRequestsArgs),
    /// Answer an open runtime request.
    Respond(ChatRespondArgs),
    /// Change an idle chat's provider, model, or interaction policy.
    Configure(ChatConfigureArgs),
}

#[derive(Debug, Args)]
pub struct ChatListArgs {
    /// Restrict results to one workspace.
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    /// Restrict results to one project.
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    /// Restrict results to one host.
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    /// Include archived child chats.
    #[arg(long)]
    pub include_archived: bool,
}

#[derive(Debug, Args)]
pub struct ChatReadArgs {
    /// Chat id whose user and assistant transcript is read.
    #[arg(long = "chat-id")]
    pub chat_id: String,
    /// Maximum number of entries to return.
    #[arg(long, default_value_t = 100, value_parser = clap::value_parser!(u64).range(1..=200))]
    pub limit: u64,
}

#[derive(Debug, Args)]
#[command(group(
    clap::ArgGroup::new("task-source")
        .required(true)
        .multiple(false)
        .args(["task", "task_file", "task_stdin"])
))]
pub struct ChatTaskSourceArgs {
    /// The brief sent to the child chat.
    #[arg(long, value_name = "text")]
    pub task: Option<String>,
    /// Read the brief from a UTF-8 file.
    #[arg(long = "task-file", value_name = "path")]
    pub task_file: Option<String>,
    /// Read the brief from standard input.
    #[arg(long = "task-stdin")]
    pub task_stdin: bool,
}

#[derive(Debug, Args)]
pub struct ChatDelegateArgs {
    #[command(flatten)]
    pub source: ChatTaskSourceArgs,
    /// Human caller's parent chat; bound callers retain their credentialed parent.
    #[arg(long = "parent-chat-id")]
    pub parent_chat_id: Option<String>,
    /// Exactly one JSON target: chat, workspace, or newWorkspace.
    #[arg(long, value_name = "json")]
    pub target: String,
    /// Stable retry key. A fresh id is generated when omitted.
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
    /// Optional user-facing title for the task and child chat.
    #[arg(long)]
    pub title: Option<String>,
    /// Optional role label for the child task.
    #[arg(long)]
    pub role: Option<String>,
    /// Completion notification policy.
    #[arg(long, value_parser = ["always", "settled_only", "never"])]
    pub notify: Option<String>,
    /// Run asynchronously or wait for completion before returning.
    #[arg(long, default_value = "async", value_parser = ["async", "wait"])]
    pub mode: String,
    /// Maximum wait when --mode wait is selected.
    #[arg(long = "wait-seconds", default_value_t = 50, value_parser = clap::value_parser!(u64).range(1..=50))]
    pub wait_seconds: u64,
    /// Provider instance and model selection as a JSON object.
    #[arg(long = "agent", value_name = "json")]
    pub agent: Option<String>,
    /// Runtime policy ceiling for the child.
    #[arg(long = "runtime-mode", value_parser = ["approval-required", "auto-accept-edits", "auto", "full-access"])]
    pub runtime_mode: Option<String>,
    /// Interaction mode for the child.
    #[arg(long = "interaction-mode", value_parser = ["default", "plan"])]
    pub interaction_mode: Option<String>,
}

#[derive(Debug, Args)]
#[command(group(
    clap::ArgGroup::new("message-source")
        .required(true)
        .multiple(false)
        .args(["message", "message_file", "message_stdin"])
))]
pub struct ChatMessageSourceArgs {
    /// Message text sent to the child chat.
    #[arg(long, value_name = "text")]
    pub message: Option<String>,
    /// Read the message from a UTF-8 file.
    #[arg(long = "message-file", value_name = "path")]
    pub message_file: Option<String>,
    /// Read the message from standard input.
    #[arg(long = "message-stdin")]
    pub message_stdin: bool,
}

#[derive(Debug, Args)]
pub struct ChatSendArgs {
    #[command(flatten)]
    pub source: ChatMessageSourceArgs,
    /// Attribute human-initiated task/wake delivery to this parent chat.
    #[arg(long = "parent-chat-id")]
    pub parent_chat_id: Option<String>,
    #[arg(long = "chat-id")]
    pub chat_id: String,
    /// Stable message id used for idempotent retries.
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
    /// Queue behind the active turn or let the runtime choose.
    #[arg(long, default_value = "auto", value_parser = ["auto", "queue"])]
    pub delivery: String,
    /// Ask the child to deliver a completion notification for this message.
    #[arg(long)]
    pub expect_reply: bool,
}

#[derive(Debug, Args)]
pub struct ChatTaskArgs {
    #[arg(long = "task-id")]
    pub task_id: String,
    /// Mark a delivered result as acknowledged.
    #[arg(long)]
    pub acknowledge: bool,
    /// Stable acknowledgement retry key; omission preserves legacy no-id behavior.
    #[arg(long = "request-id", requires = "acknowledge")]
    pub request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatTaskListArgs {
    #[arg(long = "parent-chat-id")]
    pub parent_chat_id: Option<String>,
    #[arg(long = "child-chat-id")]
    pub child_chat_id: Option<String>,
    #[arg(long = "root-task-id")]
    pub root_task_id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long = "host-id")]
    pub host_id: Option<String>,
    /// Repeat or comma-separate status values to include.
    #[arg(long = "status", action = ArgAction::Append, value_delimiter = ',')]
    pub statuses: Vec<String>,
    /// Restrict results to tasks needing attention.
    #[arg(long)]
    pub attention: bool,
    #[arg(long, default_value_t = 100, value_parser = clap::value_parser!(u64).range(1..=200))]
    pub limit: u64,
    #[arg(long, value_parser = clap::value_parser!(i64).range(0..))]
    pub cursor: Option<i64>,
}

#[derive(Debug, Args)]
pub struct ChatWaitArgs {
    #[arg(
        long = "task-id",
        required = true,
        action = ArgAction::Append,
        value_delimiter = ','
    )]
    pub task_ids: Vec<String>,
    #[arg(long = "timeout-seconds", default_value_t = 50, value_parser = clap::value_parser!(u64).range(1..=50))]
    pub timeout_seconds: u64,
    /// Return when any task settles instead of waiting for all tasks.
    #[arg(long, default_value = "all", value_parser = ["any", "all"])]
    pub until: String,
}

#[derive(Debug, Args)]
pub struct ChatCancelArgs {
    #[arg(long = "task-id")]
    pub task_id: String,
    #[arg(long)]
    pub reason: Option<String>,
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatInterruptArgs {
    #[arg(long = "chat-id")]
    pub chat_id: String,
    #[arg(long = "turn-id")]
    pub turn_id: Option<String>,
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatRequestsArgs {
    /// Restrict requests to one chat.
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
    /// Restrict requests to tasks whose result is waiting on input.
    #[arg(long = "task-id")]
    pub task_id: Option<String>,
}

#[derive(Debug, Args)]
#[command(group(
    clap::ArgGroup::new("response-source")
        .required(true)
        .multiple(false)
        .args(["response", "response_file", "response_stdin"])
))]
pub struct ChatRespondArgs {
    #[arg(long = "chat-id")]
    pub chat_id: String,
    /// Runtime request id from `alera chat requests`.
    #[arg(long = "runtime-request-id")]
    pub runtime_request_id: String,
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
    /// Response object, for example {"type":"approval","decision":"accept"}.
    #[arg(long, value_name = "json")]
    pub response: Option<String>,
    #[arg(long = "response-file", value_name = "path")]
    pub response_file: Option<String>,
    #[arg(long = "response-stdin")]
    pub response_stdin: bool,
}

#[derive(Debug, Args)]
pub struct ChatConfigureArgs {
    #[arg(long = "chat-id")]
    pub chat_id: String,
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
    #[arg(long)]
    pub provider: Option<String>,
    #[arg(long = "provider-instance-id")]
    pub provider_instance_id: Option<String>,
    #[arg(long, conflicts_with = "reset_model")]
    pub model: Option<String>,
    /// Explicitly reset the model to the provider default.
    #[arg(long = "reset-model")]
    pub reset_model: bool,
    #[arg(long = "reasoning-effort", conflicts_with = "reset_reasoning_effort")]
    pub reasoning_effort: Option<String>,
    /// Explicitly reset reasoning effort to the provider default.
    #[arg(long = "reset-reasoning-effort")]
    pub reset_reasoning_effort: bool,
    #[arg(long = "runtime-mode", value_parser = ["approval-required", "auto-accept-edits", "auto", "full-access"])]
    pub runtime_mode: Option<String>,
    #[arg(long = "interaction-mode", value_parser = ["default", "plan"])]
    pub interaction_mode: Option<String>,
}
