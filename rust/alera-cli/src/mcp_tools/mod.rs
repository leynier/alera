//! The MCP tool catalog shared by `alera mcp serve` and the remote MCP link.
//!
//! Every tool is one typed `alera <group> --json <action>` invocation, so the
//! MCP surface keeps the CLI's semantics instead of reimplementing them. The
//! edge serves a generated copy of this catalog (`edge/src/mcp/tool_catalog.json`).

mod arguments;
mod catalog;
mod executor;
mod origin;
mod schema;
mod stdio_server;
mod subscriptions;

#[cfg(test)]
mod tests;
#[cfg(test)]
mod tests_catalog;

use std::time::Duration;

use serde_json::{json, Value};

pub(crate) use arguments::{ToolArguments, ToolInputError};
pub(crate) use executor::{run_tool, ToolExecution, ToolResult};
pub(crate) use origin::{CallOrigin, ORIGIN_VARIABLE};
pub(crate) use stdio_server::serve_stdio;

/// Version 2 added the `admin` access class and `idempotentHint`.
pub(crate) const CATALOG_VERSION: u64 = 2;
/// Hosted MCP clients abandon a call after about a minute, so every wait stays
/// below that and the agent polls again.
pub(crate) const MAX_WAIT_SECONDS: u64 = 50;
/// Optional retry key of every tool that changes state through a CLI flag
/// that deduplicates repeated requests.
pub(crate) const CLIENT_REQUEST_ID: &str = "clientRequestId";

/// The class of a tool, ordered from least to most privileged. A grant or a
/// runtime level that allows one class also allows every class below it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum ToolAccess {
    Read,
    Execute,
    Admin,
}

impl ToolAccess {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::Execute => "execute",
            Self::Admin => "admin",
        }
    }

    /// The class a cloud call grant allows (`read`, `execute`, or `admin`).
    pub(crate) fn from_grant(value: &str) -> Option<Self> {
        match value {
            "read" => Some(Self::Read),
            "execute" => Some(Self::Execute),
            "admin" => Some(Self::Admin),
            _ => None,
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
    /// Repeating the call with the same arguments has no further effect.
    pub(crate) idempotent: bool,
    /// CLI flag that receives `clientRequestId`, for tools whose command
    /// deduplicates retries. The argument is added to the schema for them.
    pub(crate) client_request_flag: Option<&'static str>,
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

    /// The tool's input schema, including `clientRequestId` when it applies.
    pub(crate) fn schema(&self) -> Value {
        let mut schema = (self.input_schema)();
        if self.client_request_flag.is_some() {
            schema["properties"][CLIENT_REQUEST_ID] = schema::client_request_id();
        }
        schema
    }

    pub(crate) fn invocation(&self, arguments: &Value) -> Result<Invocation, ToolInputError> {
        let arguments = ToolArguments::parse(arguments, &self.schema())?;
        let invocation = (self.build)(&arguments)?;
        Ok(match self.client_request_flag {
            Some(flag) => invocation.option_if(flag, arguments.string(CLIENT_REQUEST_ID)),
            None => invocation,
        })
    }

    pub(crate) fn to_json(&self) -> Value {
        json!({
            "name": self.name,
            "title": self.title,
            "description": self.description,
            "access": self.access.as_str(),
            "timeoutSeconds": self.timeout_seconds,
            "inputSchema": self.schema(),
            "annotations": {
                "title": self.title,
                "readOnlyHint": self.access == ToolAccess::Read,
                "destructiveHint": self.destructive,
                "idempotentHint": self.idempotent || self.access == ToolAccess::Read,
                "openWorldHint": false,
            },
        })
    }
}

pub(crate) fn catalog() -> Vec<ToolSpec> {
    catalog::tools()
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
