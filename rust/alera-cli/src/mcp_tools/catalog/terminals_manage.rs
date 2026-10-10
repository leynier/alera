//! Tab and terminal lifecycle beyond reading and writing.

use super::{admin, execute, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolInputError, ToolSpec};

/// Terminal Pulse input limit, as the runtime host enforces it.
const PULSE_INPUT_LIMIT: u64 = 4_096;
const TITLE_LIMIT: u64 = 200;

fn handle_schema() -> serde_json::Value {
    object(
        &[("handle", string("Terminal handle from list_terminals."))],
        &["handle"],
    )
}

fn tab_schema() -> serde_json::Value {
    object(&[("tabId", string("Tab id from list_tabs."))], &["tabId"])
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        execute(
            "create_tab",
            "Create Tab",
            "Open a terminal tab in a workspace and start it, optionally running a command such as an agent CLI.",
            || {
                object(
                    &[
                        ("workspaceId", string("Workspace id.")),
                        ("title", text("Tab title.", TITLE_LIMIT)),
                        ("command", text("Command typed after the shell starts.", 8_192)),
                    ],
                    &["workspaceId", "title"],
                )
            },
            |arguments| {
                Ok(Invocation::new("tab", &["create"])
                    .option("--workspace-id", arguments.required("workspaceId")?)
                    .option("--title", arguments.required("title")?)
                    .option_if("--command", arguments.string("command"))
                    .flag("--spawn"))
            },
        ),
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..execute(
                "close_tab",
                "Close Tab",
                "Close a tab and end its terminal session, as closing it in the app does.",
                tab_schema,
                |arguments| {
                    Ok(Invocation::new("tab", &["remove"])
                        .option("--id", arguments.required("tabId")?)
                        .flag("--terminate"))
                },
            )
        },
        ToolSpec {
            idempotent: true,
            ..execute(
                "rename_tab",
                "Rename Tab",
                "Rename a tab.",
                || {
                    object(
                        &[
                            ("tabId", string("Tab id from list_tabs.")),
                            ("title", text("New tab title.", TITLE_LIMIT)),
                        ],
                        &["tabId", "title"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("tab", &["rename"])
                        .option("--id", arguments.required("tabId")?)
                        .option("--title", arguments.required("title")?))
                },
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "generate_tab_title",
                "Generate Tab Title",
                "Name an agent tab from its conversation with AI Assist, as the app does.",
                tab_schema,
                |arguments| {
                    Ok(Invocation::new("tab", &["generate-title"])
                        .option("--id", arguments.required("tabId")?))
                },
            )
        },
        ToolSpec {
            idempotent: true,
            ..execute(
                "link_agent_to_tab",
                "Link Agent To Tab",
                "Bind a running agent conversation to a tab again so the agent's status updates that tab.",
                || {
                    object(
                        &[
                            ("tabId", string("Tab id from list_tabs.")),
                            ("agent", string("Agent type, such as claude or codex.")),
                            ("sessionId", string("The agent's conversation id.")),
                            ("state", one_of("Status shown until the agent reports again.", &["working", "waiting", "blocked", "done"])),
                        ],
                        &["tabId", "agent", "sessionId"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("tab", &["link-agent"])
                        .option("--tab", arguments.required("tabId")?)
                        .option("--agent", arguments.required("agent")?)
                        .option("--session-id", arguments.required("sessionId")?)
                        .option_if("--state", arguments.string("state")))
                },
            )
        },
        ToolSpec {
            destructive: true,
            ..execute(
                "restart_terminal",
                "Restart Terminal",
                "Replace a terminal's process, keeping its tab and scrollback, and start its command or agent again.",
                handle_schema,
                |arguments| {
                    Ok(Invocation::new("terminal", &["restart"])
                        .option("--handle", arguments.required("handle")?))
                },
            )
        },
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..execute(
                "terminate_terminal",
                "Terminate Terminal",
                "End a terminal session and close its tab, as the Resource Manager does.",
                handle_schema,
                |arguments| {
                    Ok(Invocation::new("terminal", &["terminate"])
                        .option("--handle", arguments.required("handle")?))
                },
            )
        },
        ToolSpec {
            destructive: true,
            ..admin(
                "prune_terminals",
                "Prune Terminals",
                "List stopped terminal tabs, or remove them with apply. Limit it to one workspace with workspaceId.",
                || {
                    object(
                        &[
                            ("workspaceId", string("Workspace id. Omit for every workspace.")),
                            ("apply", boolean("Remove the stopped terminals instead of listing them.")),
                        ],
                        &[],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("terminal", &["prune"])
                        .option_if("--workspace", arguments.string("workspaceId"))
                        .flag_if("--apply", arguments.flag("apply")))
                },
            )
        },
        read(
            "get_terminal_pulse",
            "Get Terminal Pulse",
            "Show a terminal's Pulse: the input typed into it after workspace files change, its delay, and whether it is armed.",
            handle_schema,
            |arguments| {
                Ok(Invocation::new("terminal", &["pulse", "show"])
                    .option("--handle", arguments.required("handle")?))
            },
        ),
        ToolSpec {
            idempotent: true,
            ..execute(
                "configure_terminal_pulse",
                "Configure Terminal Pulse",
                "Change a terminal's Pulse and arm or disarm it. Fields left out keep their saved values.",
                || {
                    object(
                        &[
                            ("handle", string("Terminal handle from list_terminals.")),
                            ("input", text("Text typed into the terminal after files change.", PULSE_INPUT_LIMIT)),
                            ("enter", boolean("Press Enter after the input.")),
                            ("delayMs", integer("Quiet time after the last change before typing, in milliseconds.", 100, 3_600_000)),
                            ("watch", one_of("Arm or disarm the Pulse. Omit to keep its state.", &["arm", "disarm"])),
                        ],
                        &["handle"],
                    )
                },
                |arguments| {
                    let watch = match arguments.string("watch").as_deref() {
                        Some("arm") => Some("--arm"),
                        Some("disarm") => Some("--disarm"),
                        Some(_) => return Err(ToolInputError("Unsupported watch value.".into())),
                        None => None,
                    };
                    let invocation = Invocation::new("terminal", &["pulse", "set"])
                        .option("--handle", arguments.required("handle")?)
                        .option_if("--input", arguments.string("input"))
                        .option_if("--enter", arguments.optional_flag("enter").map(|value| value.to_string()))
                        .option_if("--delay-ms", arguments.integer("delayMs").map(|value| value.to_string()));
                    Ok(match watch {
                        Some(flag) => invocation.flag(flag),
                        None => invocation,
                    })
                },
            )
        },
    ]
}
