use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError};
use claude_agent_sdk::ClaudeAgentOptions;
use serde_json::json;

/// Merge host-owned MCP servers into the SDK's native `mcp_servers` map.
/// Existing names are retained as caller configuration and therefore cannot
/// be replaced by a launch hook with a different endpoint or process.
pub(crate) fn merge_options(
    options: &mut ClaudeAgentOptions,
    servers: &[McpServerSpec],
) -> Result<bool, ProviderError> {
    if servers.is_empty() {
        return Ok(false);
    }
    let projected = servers
        .iter()
        .map(project_server)
        .collect::<Result<Vec<_>, _>>()?;
    for (name, _) in &projected {
        if options.mcp_servers.contains_key(name) {
            return Err(ProviderError::Validation(format!(
                "Claude MCP server name collides with caller config: {name}"
            )));
        }
    }
    for (name, value) in projected {
        options.mcp_servers.insert(name, value);
    }
    Ok(true)
}

fn project_server(server: &McpServerSpec) -> Result<(String, serde_json::Value), ProviderError> {
    server.validate()?;
    match &server.transport {
        McpTransport::Stdio {
            command,
            args,
            env,
            cwd,
        } => {
            if cwd.is_some() {
                return Err(ProviderError::Unsupported(format!(
                    "Claude MCP server {} does not support a stdio cwd",
                    server.name
                )));
            }
            let command = command.to_str().ok_or_else(|| {
                ProviderError::Unsupported(format!(
                    "Claude MCP server {} command path is not valid UTF-8",
                    server.name
                ))
            })?;
            Ok((
                server.name.clone(),
                json!({ "type": "stdio", "command": command, "args": args, "env": env }),
            ))
        }
        McpTransport::Http { url, headers } => Ok((
            server.name.clone(),
            json!({ "type": "http", "url": url, "headers": headers }),
        )),
    }
}
