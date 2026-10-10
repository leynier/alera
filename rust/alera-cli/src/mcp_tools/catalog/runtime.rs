//! The runtime itself.

use super::{no_arguments, read};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![read(
        "runtime_status",
        "Runtime Status",
        "Show whether the Alera runtime host is running, its database, and its active sessions.",
        no_arguments,
        |_| Ok(Invocation::new("runtime", &["status"])),
    )]
}
