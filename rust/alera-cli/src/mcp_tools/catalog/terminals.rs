//! Workspace tabs and live terminal sessions.

use super::{execute, read, wait_schema, wait_seconds, PROMPT_LIMIT, WAIT_TIMEOUT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_tabs",
            "List Tabs",
            "List the tabs of a workspace, including terminal and agent tabs.",
            || object(&[("workspaceId", string("Workspace id."))], &["workspaceId"]),
            |arguments| {
                Ok(Invocation::new("tab", &["list"])
                    .option("--workspace-id", arguments.required("workspaceId")?))
            },
        ),
        read(
            "list_terminals",
            "List Terminals",
            "List live terminal sessions with their handles, optionally for one workspace.",
            || object(&[("workspaceId", string("Workspace id."))], &[]),
            |arguments| {
                Ok(Invocation::new("terminal", &["list"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "show_terminal",
            "Show Terminal",
            "Show one terminal session by handle, including its agent and lifecycle state.",
            || object(&[("handle", string("Terminal handle from list_terminals."))], &["handle"]),
            |arguments| {
                Ok(Invocation::new("terminal", &["show"])
                    .option("--handle", arguments.required("handle")?))
            },
        ),
        ToolSpec {
            omit_fields: &["dataBase64"],
            ..read(
                "read_terminal",
                "Read Terminal",
                "Read retained terminal output. Pass the returned cursor on the next call to read only new output.",
                || {
                    object(
                        &[
                            ("handle", string("Terminal handle from list_terminals.")),
                            ("cursor", integer("Cursor returned by a previous read.", 0, u64::MAX >> 11)),
                            ("maxBytes", integer("Maximum bytes to return (default 32768).", 1, 262_144)),
                        ],
                        &["handle"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("terminal", &["read"])
                        .option("--handle", arguments.required("handle")?)
                        .option_if("--cursor", arguments.integer("cursor").map(|value| value.to_string()))
                        .option(
                            "--max-bytes",
                            arguments.integer("maxBytes").unwrap_or(32_768).to_string(),
                        ))
                },
            )
        },
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_terminal",
                "Wait For Terminal",
                "Wait up to timeoutSeconds for a terminal to reach a lifecycle state, such as an agent becoming ready.",
                || {
                    object(
                        &[
                            ("handle", string("Terminal handle.")),
                            ("state", one_of("Lifecycle state.", &["process-started", "agent-detected", "agent-ready", "dispatch-accepted"])),
                            ("timeoutSeconds", wait_schema()),
                        ],
                        &["handle", "state"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("terminal", &["wait"])
                        .option("--terminal", arguments.required("handle")?)
                        .option("--for", arguments.required("state")?)
                        .option("--timeout-ms", (wait_seconds(arguments, 30) * 1000).to_string()))
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
    ]
}
