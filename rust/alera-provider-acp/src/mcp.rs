use agent_client_protocol::{AcpInitializeResponse, AcpProtocolGeneration};
use alera_provider_protocol::{
    McpInjectionCapabilities, McpServerSpec, McpTransport, ProviderError,
};
use serde_json::{json, Value};

pub(crate) fn negotiated_capabilities(
    initialized: Option<&AcpInitializeResponse>,
) -> McpInjectionCapabilities {
    let Some(initialized) = initialized else {
        return McpInjectionCapabilities::default();
    };
    let capabilities = &initialized.capabilities.raw;
    match initialized.generation {
        AcpProtocolGeneration::V1 => {
            let mcp = capabilities.get("mcpCapabilities");
            McpInjectionCapabilities {
                // V1 requires stdio without advertising it; retain explicit peer opt-outs.
                stdio: mcp
                    .and_then(|value| value.get("stdio"))
                    .is_none_or(|value| advertised_transport(Some(value))),
                http: mcp
                    .and_then(|value| value.get("http"))
                    .and_then(Value::as_bool)
                    == Some(true),
            }
        }
        AcpProtocolGeneration::V2 => {
            // A modern session declaration takes precedence, including disabled MCP support.
            let mcp = capabilities.get("session").map_or_else(
                || {
                    capabilities
                        .get("sessionCapabilities")
                        .and_then(|value| value.get("mcp"))
                        .or_else(|| capabilities.get("mcpCapabilities"))
                },
                |session| session.get("mcp"),
            );
            McpInjectionCapabilities {
                stdio: advertised_transport(mcp.and_then(|value| value.get("stdio"))),
                http: advertised_transport(mcp.and_then(|value| value.get("http"))),
            }
        }
    }
}

fn advertised_transport(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(supported)) => *supported,
        Some(Value::Object(_)) => true,
        _ => false,
    }
}

pub(crate) fn map_servers(
    servers: &[McpServerSpec],
    capabilities: McpInjectionCapabilities,
    generation: AcpProtocolGeneration,
) -> Result<Vec<Value>, ProviderError> {
    servers
        .iter()
        .map(|server| map_server(server, capabilities, generation))
        .collect()
}

fn map_server(
    server: &McpServerSpec,
    capabilities: McpInjectionCapabilities,
    generation: AcpProtocolGeneration,
) -> Result<Value, ProviderError> {
    server.validate()?;
    if !capabilities.supports(server) {
        return Err(ProviderError::Unsupported(format!(
            "ACP agent did not advertise {} MCP server injection for `{}`",
            transport_name(&server.transport),
            server.name
        )));
    }
    match &server.transport {
        McpTransport::Stdio {
            command,
            args,
            env,
            cwd,
        } => {
            if cwd.is_some() {
                return Err(ProviderError::Unsupported(format!(
                    "ACP stdio MCP server `{}` cannot represent cwd",
                    server.name
                )));
            }
            let command = command.to_str().ok_or_else(|| {
                ProviderError::Validation(format!(
                    "ACP stdio MCP server `{}` command must be valid UTF-8",
                    server.name
                ))
            })?;
            if !command_path_is_absolute(command) {
                return Err(ProviderError::Unsupported(format!(
                    "ACP stdio MCP server `{}` command must be absolute",
                    server.name
                )));
            }
            let env = env
                .iter()
                .map(|(name, value)| json!({"name": name, "value": value}))
                .collect::<Vec<_>>();
            let mut mapped = json!({
                "name": server.name,
                "command": command,
                "args": args,
                "env": env,
            });
            if generation == AcpProtocolGeneration::V2 {
                mapped["type"] = Value::String("stdio".into());
            }
            Ok(mapped)
        }
        McpTransport::Http { url, headers } => {
            let headers = headers
                .iter()
                .map(|(name, value)| json!({"name": name, "value": value}))
                .collect::<Vec<_>>();
            Ok(json!({
                "type": "http",
                "name": server.name,
                "url": url,
                "headers": headers,
            }))
        }
    }
}

fn command_path_is_absolute(command: &str) -> bool {
    std::path::Path::new(command).is_absolute()
}

fn transport_name(transport: &McpTransport) -> &'static str {
    match transport {
        McpTransport::Stdio { .. } => "stdio",
        McpTransport::Http { .. } => "HTTP",
    }
}
