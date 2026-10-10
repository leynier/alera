//! Agent profiles: reading them and launching them.

use super::{
    execute, no_arguments, profile_schema, read, with_profile, LAUNCH_TIMEOUT, PROMPT_LIMIT,
};
use crate::mcp_tools::schema::{object, string, text};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_agent_profiles",
            "List Agent Profiles",
            "List the agent profiles (Claude, Codex, and others) that can be launched or delegated to, with their ids and names.",
            no_arguments,
            |_| Ok(Invocation::new("agent-profile", &["list"])),
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            client_request_flag: Some("--client-mutation-id"),
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
    ]
}
