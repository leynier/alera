//! The Alera skills coding agents use in Alera terminals. The skills MCP
//! clients read are served by the Alera cloud, not by the runtime.

use super::{admin, no_arguments, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{object, one_of, string_list};
use crate::mcp_tools::{Invocation, ToolSpec};

const SKILLS: &[&str] = &["cli", "orchestration", "automations", "agent-profiles"];

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "check_agent_skills",
            "Check Agent Skills",
            "Show whether the Alera skills that coding agents use in Alera terminals (alera-cli, alera-orchestration, alera-automations, alera-agent-profiles) are installed on this runtime's machine, and whether each matches this runtime's version.",
            no_arguments,
            |_| Ok(Invocation::new("skill", &["status"])),
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            idempotent: true,
            ..admin(
                "install_agent_skills",
                "Install Agent Skills",
                "Install or update the Alera skills that coding agents use, at this runtime's own version, through the skills installer (npx or bunx) on its machine. Installs every skill unless skills is given. Returns the outcome and the new status.",
                || {
                    object(
                        &[
                            ("skills", string_list("Skills to install (default all).", SKILLS)),
                            (
                                "runner",
                                one_of(
                                    "Package runner: auto (default) tries npx, then bunx.",
                                    &["auto", "npx", "bunx"],
                                ),
                            ),
                        ],
                        &[],
                    )
                },
                |arguments| {
                    let mut invocation = Invocation::new("skill", &["install"]);
                    for skill in arguments.list("skills").unwrap_or_default() {
                        invocation = invocation.option("--skill", skill);
                    }
                    Ok(invocation.option_if("--runner", arguments.string("runner")))
                },
            )
        },
    ]
}
