//! Projects registered in the runtime.

use super::{no_arguments, read};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![read(
        "list_projects",
        "List Projects",
        "List the projects registered in this Alera runtime with their ids, names, and the hosts each one is on.",
        no_arguments,
        |_| Ok(Invocation::new("project", &["list"])),
    )]
}
