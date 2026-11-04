use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError};
use serde_json::{Map, Value};

/// Build the open session configuration accepted by the native MSP schema.
/// The host owns credentials and transports; the provider only forwards the
/// validated per-chat description and never starts a second MCP process.
pub(crate) fn config(
    servers: &[McpServerSpec],
) -> Result<Option<Map<String, Value>>, ProviderError> {
    if servers.is_empty() {
        return Ok(None);
    }
    let mut mcp_servers = Map::new();
    for server in servers {
        let mut native = Map::new();
        match &server.transport {
            McpTransport::Http { url, headers } => {
                native.insert("transport".into(), Value::String("streamableHttp".into()));
                native.insert("url".into(), Value::String(url.clone()));
                native.insert("mode".into(), Value::String("required".into()));
                if !headers.is_empty() {
                    native.insert(
                        "headers".into(),
                        headers
                            .iter()
                            .map(|(key, value)| (key.clone(), Value::String(value.clone())))
                            .collect::<Map<_, _>>()
                            .into(),
                    );
                }
            }
            McpTransport::Stdio {
                command,
                args,
                env,
                cwd,
            } => {
                if cwd.is_some() {
                    return Err(ProviderError::Unsupported(
                        "Muse MSP stdio MCP has no cwd field".into(),
                    ));
                }
                let command = command.to_str().ok_or_else(|| {
                    ProviderError::Validation("MCP stdio command must be valid UTF-8".into())
                })?;
                native.insert("transport".into(), Value::String("stdio".into()));
                native.insert("command".into(), Value::String(command.into()));
                native.insert("mode".into(), Value::String("required".into()));
                if !args.is_empty() {
                    native.insert(
                        "args".into(),
                        Value::Array(args.iter().cloned().map(Value::String).collect()),
                    );
                }
                if !env.is_empty() {
                    native.insert(
                        "env".into(),
                        env.iter()
                            .map(|(key, value)| (key.clone(), Value::String(value.clone())))
                            .collect::<Map<_, _>>()
                            .into(),
                    );
                }
            }
        }
        mcp_servers.insert(server.name.clone(), Value::Object(native));
    }
    let mut config = Map::new();
    config.insert("mcpServers".into(), Value::Object(mcp_servers));
    Ok(Some(config))
}
