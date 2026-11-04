use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError};
use serde_json::{json, Map, Value};

/// Merge host-owned MCP servers into the app-server's thread config.
///
/// Each server goes in as its own dotted `mcp_servers.<name>` key. Codex
/// writes a request override at its final path segment, so a whole
/// `mcp_servers` table would replace the servers a user started Codex with
/// (`codex app-server -c mcp_servers.x.command=...`), while a dotted key adds
/// only this server. The nested table is kept when the caller already sends
/// one, since mixing both forms makes the result depend on override order,
/// and when a name contains a `.`, which Codex would split into a path.
///
/// An existing server name is a configuration conflict: silently replacing a
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
    let caller_table = match config.get("mcp_servers") {
        None => None,
        Some(Value::Object(table)) => Some(table),
        Some(_) => {
            return Err(ProviderError::Validation(
                "Codex config.mcp_servers must be a JSON object".into(),
            ))
        }
    };
    for (name, _) in &projected {
        let dotted = dotted_key(name);
        let nested_prefix = format!("{dotted}.");
        if caller_table.is_some_and(|table| table.contains_key(name))
            || config
                .keys()
                .any(|key| *key == dotted || key.starts_with(&nested_prefix))
        {
            return Err(ProviderError::Validation(format!(
                "Codex MCP server name collides with caller config: {name}"
            )));
        }
    }
    let nested = caller_table.is_some() || projected.iter().any(|(name, _)| name.contains('.'));
    if !nested {
        for (name, value) in projected {
            config.insert(dotted_key(&name), value);
        }
        return Ok(());
    }
    let mcp_servers = config
        .entry("mcp_servers")
        .or_insert_with(|| Value::Object(Map::new()))
        .as_object_mut()
        .expect("config.mcp_servers was checked to be an object");
    for (name, value) in projected {
        mcp_servers.insert(name, value);
    }
    Ok(())
}

fn dotted_key(name: &str) -> String {
    format!("mcp_servers.{name}")
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
