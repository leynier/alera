use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError};
use cursor_agent_sdk::{
    HttpMcpServerConfig, HttpMcpTransportType, McpServerConfig, StdioMcpServerConfig,
};
use std::collections::BTreeMap;

pub(crate) fn native_mcp_servers(
    servers: &[McpServerSpec],
) -> Result<Option<BTreeMap<String, McpServerConfig>>, ProviderError> {
    if servers.is_empty() {
        return Ok(None);
    }
    let mut native = BTreeMap::new();
    for server in servers {
        server.validate()?;
        let config = match &server.transport {
            McpTransport::Stdio {
                command,
                args,
                env,
                cwd,
            } => McpServerConfig {
                stdio: Some(StdioMcpServerConfig {
                    command: command
                        .to_str()
                        .ok_or_else(|| {
                            ProviderError::Unsupported(format!(
                                "MCP server {} command path is not valid UTF-8",
                                server.name
                            ))
                        })?
                        .to_owned(),
                    args: args.clone(),
                    env: env.clone(),
                    cwd: cwd
                        .as_ref()
                        .map(|path| {
                            path.to_str().ok_or_else(|| {
                                ProviderError::Unsupported(format!(
                                    "MCP server {} cwd is not valid UTF-8",
                                    server.name
                                ))
                            })
                        })
                        .transpose()?
                        .unwrap_or_default()
                        .to_owned(),
                }),
                http: None,
            },
            McpTransport::Http { url, headers } => McpServerConfig {
                stdio: None,
                http: Some(HttpMcpServerConfig {
                    transport_type: HttpMcpTransportType::Http,
                    url: url.clone(),
                    headers: headers.clone(),
                }),
            },
        };
        if native.insert(server.name.clone(), config).is_some() {
            return Err(ProviderError::Validation(format!(
                "duplicate MCP server name {}",
                server.name
            )));
        }
    }
    Ok(Some(native))
}
