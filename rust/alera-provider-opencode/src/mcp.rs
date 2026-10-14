use crate::{config::mcp_config, provider::OpenCodeProvider};
use alera_provider_protocol::{McpServerSpec, McpTransport, ProviderError, SessionStartInput};
use opencode_agent_sdk::{normalized_mcp_server_name, HttpTransport, PermissionRule};
use std::{collections::HashSet, time::Duration};

pub(crate) fn validate_input(
    server_url: Option<&str>,
    support: crate::config::OpenCodeConfigSupport,
    input: &SessionStartInput,
) -> Result<(), ProviderError> {
    if input.mcp_servers.is_empty() {
        return Ok(());
    }
    if server_url.is_some() {
        return Err(ProviderError::Unsupported(
            "OpenCode MCP injection requires a provider-owned local server".into(),
        ));
    }
    let mut namespaces = HashSet::new();
    for server in &input.mcp_servers {
        if !namespaces.insert(normalized_mcp_server_name(&server.name)) {
            return Err(ProviderError::Validation(
                "OpenCode MCP server names share a native tool namespace".into(),
            ));
        }
        let supported = match &server.transport {
            McpTransport::Stdio { .. } => support.mcp_stdio,
            McpTransport::Http { .. } => support.mcp_http,
        };
        if !supported {
            return Err(ProviderError::Unsupported(
                "OpenCode MCP server transport is not supported by this configuration".into(),
            ));
        }
    }
    Ok(())
}

pub(crate) async fn preflight<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    servers: &[McpServerSpec],
) -> Result<(), ProviderError> {
    if servers.is_empty() {
        return Ok(());
    }
    let existing = crate::provider::timed(
        provider.config.request_timeout,
        "mcp.list",
        provider.client.mcp_server_names(),
    )
    .await?;
    let namespaces = existing
        .iter()
        .map(|name| normalized_mcp_server_name(name))
        .collect::<HashSet<_>>();
    if servers
        .iter()
        .any(|server| namespaces.contains(&normalized_mcp_server_name(&server.name)))
    {
        return Err(ProviderError::Validation(
            "OpenCode MCP server name collides with a configured native server".into(),
        ));
    }
    Ok(())
}

pub(crate) fn permission_rules(servers: &[McpServerSpec]) -> Vec<PermissionRule> {
    if servers.is_empty() {
        return Vec::new();
    }
    let mut rules = ["alera-*", "alera_*"]
        .into_iter()
        .map(|action| PermissionRule {
            action: action.into(),
            resource: "*".into(),
            effect: "deny".into(),
        })
        .collect::<Vec<_>>();
    for server in servers {
        let normalized = normalized_mcp_server_name(&server.name);
        rules.push(PermissionRule {
            action: format!("{normalized}_*"),
            resource: "*".into(),
            effect: "allow".into(),
        });
    }
    rules
}

pub(crate) async fn install<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    servers: &[McpServerSpec],
) -> Result<Vec<String>, ProviderError> {
    let mut installed = Vec::new();
    for server in servers {
        if let Err(error) = crate::provider::timed(
            provider.config.request_timeout,
            "mcp.add",
            provider
                .client
                .add_mcp_server(&server.name, mcp_config(server)),
        )
        .await
        {
            let mut installed_names = installed;
            let cleanup_error = cleanup(provider, &mut installed_names).await;
            return Err(combine_errors(error, cleanup_error));
        }
        installed.push(server.name.clone());
    }
    Ok(installed)
}

pub(crate) async fn cleanup<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    names: &mut Vec<String>,
) -> Option<ProviderError> {
    let mut first = None;
    while let Some(name) = names.pop() {
        if let Err(error) = crate::provider::timed(
            provider.config.request_timeout,
            "mcp.remove",
            provider.client.remove_mcp_server(&name),
        )
        .await
        {
            if first.is_none() {
                first = Some(error);
            }
        }
    }
    first
}

pub(crate) fn combine_errors(
    primary: ProviderError,
    cleanup: Option<ProviderError>,
) -> ProviderError {
    match cleanup {
        Some(cleanup) => {
            ProviderError::Protocol(format!("{primary}; MCP cleanup failed: {cleanup}"))
        }
        None => primary,
    }
}

pub(crate) async fn close<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    timeout: Duration,
) -> Result<(), ProviderError> {
    let mut names = std::mem::take(&mut provider.scoped_mcp_servers);
    let cleanup_error = cleanup(provider, &mut names).await;
    let close_error = crate::provider::timed(timeout, "client.close", provider.client.close())
        .await
        .err();
    provider.closed = true;
    provider.pending.clear();
    provider.active_turn = None;
    provider.mcp_tool_ids.clear();
    provider.native_parts.clear();
    provider.queued_events.clear();
    if let Some(session) = provider.session.as_mut() {
        session.status = alera_provider_protocol::SessionStatus::Stopped;
        session.active_turn_id = None;
    }
    match (close_error, cleanup_error) {
        (Some(close), Some(cleanup)) => Err(combine_errors(close, Some(cleanup))),
        (Some(close), None) => Err(close),
        (None, Some(cleanup)) => Err(cleanup),
        (None, None) => Ok(()),
    }
}
