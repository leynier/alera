//! Tools that change runtime state: workspaces, agents, terminals, and messages.
//!
//! Long text always travels on stdin, so it never meets an argument length
//! limit or a shell.

use super::catalog_read::{wait_seconds, MCP_INBOX};
use super::schema::{boolean, integer, object, one_of, string, text};
use super::{Invocation, ToolAccess, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

const MUTATION_TIMEOUT: u64 = 30;
const LAUNCH_TIMEOUT: u64 = MAX_WAIT_SECONDS + 8;
const PROMPT_LIMIT: u64 = 65_536;

fn execute(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    input_schema: fn() -> serde_json::Value,
    build: fn(&ToolArguments) -> Result<Invocation, ToolInputError>,
) -> ToolSpec {
    ToolSpec {
        name,
        title,
        description,
        access: ToolAccess::Execute,
        timeout_seconds: MUTATION_TIMEOUT,
        destructive: false,
        omit_fields: &[],
        input_schema,
        build,
    }
}

/// Profiles are addressed by stable id (`prof_...`) or by unique name.
fn with_profile(invocation: Invocation, profile: String) -> Invocation {
    if profile.starts_with("prof_") {
        invocation.option("--profile-id", profile)
    } else {
        invocation.option("--profile-name", profile)
    }
}

fn profile_schema() -> serde_json::Value {
    string("Agent profile id or unique name from list_agent_profiles.")
}

fn workspace_creation(invocation: Invocation, arguments: &ToolArguments) -> Invocation {
    invocation
        .flag_if("--worktree", arguments.flag("worktree"))
        .option_if("--name", arguments.string("name"))
        .option_if("--branch", arguments.string("branch"))
        .option_if("--source-branch", arguments.string("sourceBranch"))
        .option_if("--host-id", arguments.string("hostId"))
        .option_if("--issue", arguments.string("issueUrl"))
        .option_if("--section", arguments.string("section"))
}

fn workspace_creation_properties() -> Vec<(&'static str, serde_json::Value)> {
    vec![
        (
            "worktree",
            boolean("Create an exclusive Git worktree instead of sharing the project folder."),
        ),
        ("name", string("Workspace display name.")),
        ("branch", string("Branch to create or use.")),
        ("sourceBranch", string("Branch the new branch starts from.")),
        (
            "hostId",
            string("SSH target that owns the worktree. Omit for this machine."),
        ),
        ("issueUrl", string("Issue URL to link to the workspace.")),
        ("section", string("Sidebar section name.")),
    ]
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        execute(
            "create_workspace",
            "Create Workspace",
            "Create a workspace (task) in a project, optionally on its own Git worktree and branch. A worktree also needs sourceBranch, such as main. No agent is started.",
            || {
                let mut properties = vec![("projectId", string("Project id from list_projects."))];
                properties.extend(workspace_creation_properties());
                object(&properties, &["projectId"])
            },
            |arguments| {
                let invocation = Invocation::new("workspace", &["add"])
                    .option("--project-id", arguments.required("projectId")?);
                Ok(workspace_creation(invocation, arguments))
            },
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "start_agent_workspace",
                "Start Agent In New Workspace",
                "Create a workspace and launch an agent profile in it with a prompt. Pass projectId, or workspaceId to infer the project and source branch from an existing workspace. A worktree created from projectId also needs sourceBranch.",
                || {
                    let mut properties = vec![
                        ("profile", profile_schema()),
                        ("prompt", text("Prompt delivered to the agent.", PROMPT_LIMIT)),
                        ("projectId", string("Project id from list_projects.")),
                        ("workspaceId", string("Existing workspace used to infer the project.")),
                    ];
                    properties.extend(workspace_creation_properties());
                    object(&properties, &["profile", "prompt"])
                },
                |arguments| {
                    let project = arguments.string("projectId");
                    let workspace = arguments.string("workspaceId");
                    if project.is_none() && workspace.is_none() {
                        return Err(ToolInputError("Pass projectId or workspaceId.".into()));
                    }
                    let invocation = with_profile(
                        Invocation::new("workspace", &["start"]),
                        arguments.required("profile")?,
                    )
                    .flag("--prompt-stdin")
                    .flag("--no-parent")
                    .option_if("--project-id", project)
                    .option_if("--workspace", workspace)
                    .stdin(arguments.required("prompt")?);
                    Ok(workspace_creation(invocation, arguments))
                },
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "launch_agent",
                "Launch Agent",
                "Launch an agent profile in a new tab of an existing workspace with a prompt.",
                || {
                    object(
                        &[
                            ("workspaceId", string("Workspace id.")),
                            ("profile", profile_schema()),
                            ("prompt", text("Prompt delivered to the agent.", PROMPT_LIMIT)),
                        ],
                        &["workspaceId", "profile", "prompt"],
                    )
                },
                |arguments| {
                    Ok(with_profile(
                        Invocation::new("agent-profile", &["launch"]),
                        arguments.required("profile")?,
                    )
                    .option("--workspace", arguments.required("workspaceId")?)
                    .flag("--prompt-stdin")
                    .stdin(arguments.required("prompt")?))
                },
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "delegate_task",
                "Delegate Task",
                "Create an orchestration task and start an agent profile that accepts it, in an existing workspace or a new child worktree. The coordinator is a running agent terminal (from list_terminals) that receives the worker's messages. Returns the task; follow it with wait_for_task. Without a coordinator terminal, use start_agent_workspace or ask_agent instead.",
                || {
                    object(
                        &[
                            ("profile", profile_schema()),
                            ("spec", text("Task brief the worker receives.", PROMPT_LIMIT)),
                            ("coordinator", string("Terminal handle of the coordinating agent, from list_terminals.")),
                            ("title", string("Short title for listings.")),
                            ("workspaceId", string("Workspace that owns the task, or the source workspace with newWorkspace.")),
                            ("newWorkspace", boolean("Create a child worktree and delegate into it.")),
                            ("projectId", string("Project for the new workspace.")),
                            ("name", string("Name for the new workspace.")),
                            ("branch", string("Branch for the new workspace.")),
                            ("sourceBranch", string("Branch the new workspace starts from.")),
                            ("timeoutSeconds", integer("Seconds to wait for the agent to accept.", 1, MAX_WAIT_SECONDS)),
                        ],
                        &["profile", "spec", "coordinator"],
                    )
                },
                |arguments| {
                    let new_workspace = arguments.flag("newWorkspace");
                    let workspace = arguments.string("workspaceId");
                    if workspace.is_none() && !(new_workspace && arguments.string("projectId").is_some()) {
                        return Err(ToolInputError(
                            "Pass workspaceId, or newWorkspace with projectId.".into(),
                        ));
                    }
                    let workspace_flag = if new_workspace { "--from-workspace" } else { "--workspace" };
                    Ok(with_profile(
                        Invocation::new("orchestration", &["delegate"]),
                        arguments.required("profile")?,
                    )
                    .flag("--spec-stdin")
                    .flag("--keep-on-failure")
                    .option("--from", arguments.required("coordinator")?)
                    .option_if("--task-title", arguments.string("title"))
                    .option_if(workspace_flag, workspace)
                    .flag_if("--new-workspace", new_workspace)
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--name", arguments.string("name"))
                    .option_if("--branch", arguments.string("branch"))
                    .option_if("--source-branch", arguments.string("sourceBranch"))
                    .flag_if("--no-parent", new_workspace && arguments.string("workspaceId").is_none())
                    .option("--timeout-ms", (wait_seconds(arguments, MAX_WAIT_SECONDS) * 1000).to_string())
                    .stdin(arguments.required("spec")?))
                },
            )
        },
        execute(
            "write_terminal",
            "Write To Terminal",
            "Type text into a terminal. Set submit to send it to an interactive agent as a prompt, or enter to press Enter after it.",
            || {
                object(
                    &[
                        ("handle", string("Terminal handle from list_terminals.")),
                        ("text", text("Text to type.", PROMPT_LIMIT)),
                        ("submit", boolean("Submit to an interactive agent with bracketed paste and Enter.")),
                        ("enter", boolean("Press Enter after the text.")),
                    ],
                    &["handle", "text"],
                )
            },
            |arguments| {
                Ok(Invocation::new("terminal", &["write"])
                    .option("--handle", arguments.required("handle")?)
                    .flag("--stdin")
                    .flag_if("--submit", arguments.flag("submit"))
                    .flag_if("--enter", arguments.flag("enter") && !arguments.flag("submit"))
                    .stdin(arguments.required("text")?))
            },
        ),
        execute(
            "send_message",
            "Send Orchestration Message",
            "Send an orchestration message from one agent terminal to a terminal handle or a group such as @all, @idle, or @workspace:<id>. To ask an agent a question from outside, use ask_agent.",
            || {
                object(
                    &[
                        ("from", string("Sender terminal handle, from list_terminals.")),
                        ("to", string("Terminal handle or @group.")),
                        ("subject", string("Message subject.")),
                        ("body", text("Message body.", PROMPT_LIMIT)),
                        ("type", one_of("Message type.", &["status", "dispatch", "merge_ready", "escalation", "handoff", "decision_gate"])),
                        ("priority", one_of("Priority.", &["normal", "high", "urgent"])),
                        ("threadId", string("Thread to attach the message to.")),
                    ],
                    &["from", "to", "subject"],
                )
            },
            |arguments| {
                let invocation = Invocation::new("orchestration", &["send"])
                    .option("--from", arguments.required("from")?)
                    .option("--to", arguments.required("to")?)
                    .option("--subject", arguments.required("subject")?)
                    .option_if("--type", arguments.string("type"))
                    .option_if("--priority", arguments.string("priority"))
                    .option_if("--thread-id", arguments.string("threadId"));
                Ok(match arguments.string("body") {
                    Some(body) => invocation.flag("--body-stdin").stdin(body),
                    None => invocation,
                })
            },
        ),
        execute(
            "ask_agent",
            "Ask Agent",
            "Ask a running agent a question by terminal handle, or the single agent of a workspace. Returns the question id; follow it with wait_for_reply.",
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
        ),
        ToolSpec {
            destructive: true,
            ..execute(
                "cancel_task",
                "Cancel Task",
                "Cancel an orchestration task and its not-yet-started descendants. Runs as an audited administrative cancellation, because an MCP client is not the task's coordinator terminal.",
                || {
                    object(
                        &[("taskId", string("Task id.")), ("reason", string("Why it is cancelled."))],
                        &["taskId", "reason"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("orchestration", &["task-cancel"])
                        .option("--id", arguments.required("taskId")?)
                        .option("--reason", format!("[mcp] {}", arguments.required("reason")?))
                        .flag("--force"))
                },
            )
        },
        ToolSpec {
            destructive: true,
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "sleep_workspace",
                "Sleep Workspace",
                "Stop a workspace's terminal sessions while keeping its tabs, branch, and files. Opening it again wakes it.",
                || object(&[("workspaceId", string("Workspace id."))], &["workspaceId"]),
                |arguments| {
                    Ok(Invocation::new("workspace", &["sleep"])
                        .option("--id", arguments.required("workspaceId")?))
                },
            )
        },
        execute(
            "run_automation",
            "Run Automation",
            "Start one run of an automation immediately.",
            || object(&[("automationId", string("Automation id from list_automations."))], &["automationId"]),
            |arguments| {
                Ok(Invocation::new("automation", &["run-now"])
                    .option("--id", arguments.required("automationId")?))
            },
        ),
    ]
}
