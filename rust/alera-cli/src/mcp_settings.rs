//! MCP Control level and the user-chosen runtime name, kept in `runtimeMetadata`.

use alera_core::runtime::RuntimeStore;
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

use crate::mcp_tools::ToolAccess;

const ACCESS_KEY: &str = "settings.mcp.access";
const RUNTIME_NAME_KEY: &str = "settings.runtime.name";
pub(crate) const MAX_RUNTIME_NAME_CHARS: usize = 64;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum McpAccess {
    #[default]
    Off,
    Read,
    Full,
}

impl McpAccess {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Read => "read",
            Self::Full => "full",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value.trim() {
            "off" => Some(Self::Off),
            "read" => Some(Self::Read),
            "full" => Some(Self::Full),
            _ => None,
        }
    }

    pub(crate) fn allows(self, access: ToolAccess) -> bool {
        match self {
            Self::Off => false,
            Self::Read => access == ToolAccess::Read,
            Self::Full => true,
        }
    }
}

pub(crate) async fn mcp_access(store: &RuntimeStore) -> Result<McpAccess> {
    Ok(store
        .get_metadata(ACCESS_KEY)
        .await?
        .as_deref()
        .and_then(McpAccess::parse)
        .unwrap_or_default())
}

pub(crate) async fn set_mcp_access(store: &RuntimeStore, access: McpAccess) -> Result<()> {
    store.set_metadata(ACCESS_KEY, access.as_str()).await
}

pub(crate) async fn runtime_name(store: &RuntimeStore) -> Result<Option<String>> {
    Ok(store
        .get_metadata(RUNTIME_NAME_KEY)
        .await?
        .map(|name| name.trim().to_owned())
        .filter(|name| !name.is_empty()))
}

pub(crate) async fn set_runtime_name(store: &RuntimeStore, name: &str) -> Result<()> {
    store.set_metadata(RUNTIME_NAME_KEY, name).await
}

/// The name the cloud shows: the chosen one, else the host name.
pub(crate) async fn effective_runtime_name(store: &RuntimeStore) -> String {
    runtime_name(store)
        .await
        .ok()
        .flatten()
        .unwrap_or_else(crate::mobile_access::host_name)
}

pub(crate) fn validate_runtime_name(name: &str) -> Result<String> {
    let name = name.trim();
    if name.is_empty() {
        bail!("The runtime name cannot be empty.");
    }
    if name.chars().count() > MAX_RUNTIME_NAME_CHARS {
        bail!("The runtime name can have at most {MAX_RUNTIME_NAME_CHARS} characters.");
    }
    if name.chars().any(char::is_control) {
        bail!("The runtime name cannot contain control characters.");
    }
    Ok(name.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn access_levels_gate_tool_classes() {
        assert!(!McpAccess::Off.allows(ToolAccess::Read));
        assert!(McpAccess::Read.allows(ToolAccess::Read));
        assert!(!McpAccess::Read.allows(ToolAccess::Execute));
        assert!(McpAccess::Full.allows(ToolAccess::Execute));
        assert_eq!(McpAccess::parse("full"), Some(McpAccess::Full));
        assert_eq!(McpAccess::parse("all"), None);
    }

    #[test]
    fn runtime_names_are_trimmed_and_bounded() {
        assert_eq!(validate_runtime_name("  Work Mac ").unwrap(), "Work Mac");
        assert!(validate_runtime_name("   ").is_err());
        assert!(validate_runtime_name(&"x".repeat(65)).is_err());
        assert!(validate_runtime_name("a\nb").is_err());
    }

    #[tokio::test]
    async fn settings_round_trip_through_runtime_metadata() {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        assert_eq!(mcp_access(&store).await.unwrap(), McpAccess::Off);
        set_mcp_access(&store, McpAccess::Read).await.unwrap();
        assert_eq!(mcp_access(&store).await.unwrap(), McpAccess::Read);
        assert_eq!(runtime_name(&store).await.unwrap(), None);
        set_runtime_name(&store, "Build Box").await.unwrap();
        assert_eq!(effective_runtime_name(&store).await, "Build Box");
    }
}
