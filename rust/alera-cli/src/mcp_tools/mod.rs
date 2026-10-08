//! The MCP tool catalog shared by `alera mcp serve` and the remote MCP link.
//!
//! Every tool is one typed `alera <group> --json <action>` invocation, so the
//! MCP surface keeps the CLI's semantics instead of reimplementing them. The
//! edge serves a generated copy of this catalog (`edge/src/mcp/tool_catalog.json`).

mod arguments;
mod catalog_execute;
mod catalog_read;
mod executor;
mod schema;
mod stdio_server;

#[cfg(test)]
mod tests;

use std::time::Duration;

use serde_json::{json, Value};

pub(crate) use arguments::{ToolArguments, ToolInputError};
pub(crate) use executor::{run_tool, ToolExecution, ToolResult};
pub(crate) use stdio_server::serve_stdio;

pub(crate) const CATALOG_VERSION: u64 = 1;
/// Hosted MCP clients abandon a call after about a minute, so every wait stays
/// below that and the agent polls again.
pub(crate) const MAX_WAIT_SECONDS: u64 = 50;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ToolAccess {
    Read,
    Execute,
}

impl ToolAccess {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::Execute => "execute",
        }
    }
}

/// One CLI invocation: `alera <group> --runtime-dir <dir> --json <args...>`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Invocation {
    pub(crate) group: &'static str,
    pub(crate) args: Vec<String>,
    pub(crate) stdin: Option<String>,
}

impl Invocation {
    pub(crate) fn new(group: &'static str, action: &[&str]) -> Self {
        Self {
            group,
            args: action.iter().map(|value| (*value).to_owned()).collect(),
            stdin: None,
        }
    }

    pub(crate) fn flag(mut self, name: &str) -> Self {
        self.args.push(name.to_owned());
        self
    }

    pub(crate) fn flag_if(self, name: &str, enabled: bool) -> Self {
        if enabled {
            self.flag(name)
        } else {
            self
        }
    }

    /// `--name=value` keeps a value that starts with a dash from being read as
    /// another flag.
    pub(crate) fn option(mut self, name: &str, value: impl Into<String>) -> Self {
        self.args.push(format!("{name}={}", value.into()));
        self
    }

    pub(crate) fn option_if(self, name: &str, value: Option<impl Into<String>>) -> Self {
        match value {
            Some(value) => self.option(name, value),
            None => self,
        }
    }

    pub(crate) fn stdin(mut self, text: String) -> Self {
        self.stdin = Some(text);
        self
    }
}

pub(crate) struct ToolSpec {
    pub(crate) name: &'static str,
    pub(crate) title: &'static str,
    pub(crate) description: &'static str,
    pub(crate) access: ToolAccess,
    /// Upper bound for the whole CLI process, including any wait it performs.
    pub(crate) timeout_seconds: u64,
    pub(crate) destructive: bool,
    /// Top-level result fields dropped before returning, such as a base64 copy
    /// of text the result already carries.
    pub(crate) omit_fields: &'static [&'static str],
    pub(crate) input_schema: fn() -> Value,
    pub(crate) build: fn(&ToolArguments) -> Result<Invocation, ToolInputError>,
}

impl ToolSpec {
    pub(crate) fn timeout(&self) -> Duration {
        Duration::from_secs(self.timeout_seconds)
    }

    pub(crate) fn invocation(&self, arguments: &Value) -> Result<Invocation, ToolInputError> {
        let arguments = ToolArguments::parse(arguments, &(self.input_schema)())?;
        (self.build)(&arguments)
    }

    pub(crate) fn to_json(&self) -> Value {
        json!({
            "name": self.name,
            "title": self.title,
            "description": self.description,
            "access": self.access.as_str(),
            "timeoutSeconds": self.timeout_seconds,
            "inputSchema": (self.input_schema)(),
            "annotations": {
                "title": self.title,
                "readOnlyHint": self.access == ToolAccess::Read,
                "destructiveHint": self.destructive,
                "openWorldHint": false,
            },
        })
    }
}

pub(crate) fn catalog() -> Vec<ToolSpec> {
    let mut tools = catalog_read::tools();
    tools.extend(catalog_execute::tools());
    tools
}

pub(crate) fn find_tool(name: &str) -> Option<ToolSpec> {
    catalog().into_iter().find(|tool| tool.name == name)
}

/// The catalog as the edge serves it. Stable key order keeps the generated
/// file diffable.
pub(crate) fn catalog_json() -> Value {
    json!({
        "version": CATALOG_VERSION,
        "tools": catalog().iter().map(ToolSpec::to_json).collect::<Vec<_>>(),
    })
}
