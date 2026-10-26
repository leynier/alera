use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError};
use serde_json::{json, Map, Value};

/// Merge host-owned MCP servers into the app-server's thread config.
///
/// Codex reads these values from `config.mcp_servers`, while the outer
/// `thread/start` and `thread/resume` params retain their normal fields. An
/// existing server name is a configuration conflict: silently replacing a
/// caller-owned server could redirect tool traffic to an unexpected process.
pub(crate) fn merge_thread_config(
    params: &mut Map<String, Value>,
    servers: &[McpServerSpec],
) -> Result<(), ProviderError> {
    if servers.is_empty() {
        return Ok(());
    }
    if params.contains_key("mcp_servers") {
        return Err(ProviderError::Validation(
            "Codex MCP servers must be configured under params.config.mcp_servers".into(),
        ));
    }

    let projected = servers
        .iter()
        .map(project_server)
        .collect::<Result<Vec<_>, _>>()?;
    let config = params
        .entry("config")
        .or_insert_with(|| Value::Object(Map::new()));
    let config = config.as_object_mut().ok_or_else(|| {
        ProviderError::Validation("Codex thread config must be a JSON object".into())
    })?;
    let mcp_servers = config
        .entry("mcp_servers")
        .or_insert_with(|| Value::Object(Map::new()));
    let mcp_servers = mcp_servers.as_object_mut().ok_or_else(|| {
        ProviderError::Validation("Codex config.mcp_servers must be a JSON object".into())
    })?;

    for (name, _) in &projected {
        if mcp_servers.contains_key(name) {
            return Err(ProviderError::Validation(format!(
                "Codex MCP server name collides with caller config: {name}"
            )));
        }
    }
    for (name, value) in projected {
        mcp_servers.insert(name, value);
    }
    Ok(())
}

fn project_server(server: &McpServerSpec) -> Result<(String, Value), ProviderError> {
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
                    "Codex MCP server {} does not support a stdio cwd",
                    server.name
                )));
            }
            let command = command.to_str().ok_or_else(|| {
                ProviderError::Unsupported(format!(
                    "Codex MCP server {} command path is not valid UTF-8",
                    server.name
                ))
            })?;
            Ok((
                server.name.clone(),
                json!({ "command": command, "args": args, "env": env }),
            ))
        }
        McpTransport::Http { url, headers } => Ok((
            server.name.clone(),
            json!({ "url": url, "http_headers": headers }),
        )),
    }
}
