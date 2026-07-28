use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const DEFAULT_BROWSER_PROFILE_ID: &str = "default";

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BrowserSearchEngine {
    #[default]
    Google,
    DuckDuckGo,
    Bing,
    Kagi,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BrowserSettings {
    #[serde(default)]
    pub search_engine: BrowserSearchEngine,
}

/// A browser storage partition owned by Alera.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BrowserProfile {
    pub id: String,
    pub name: String,
    #[serde(default = "default_true")]
    pub persistent: bool,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub source: Option<BrowserProfileSource>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BrowserProfileSourceFamily {
    Chrome,
    Edge,
    Arc,
    Brave,
    Comet,
    Helium,
    Firefox,
    Safari,
    Manual,
}

impl BrowserProfileSourceFamily {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Chrome => "chrome",
            Self::Edge => "edge",
            Self::Arc => "arc",
            Self::Brave => "brave",
            Self::Comet => "comet",
            Self::Helium => "helium",
            Self::Firefox => "firefox",
            Self::Safari => "safari",
            Self::Manual => "manual",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "chrome" => Self::Chrome,
            "edge" => Self::Edge,
            "arc" => Self::Arc,
            "brave" => Self::Brave,
            "comet" => Self::Comet,
            "helium" => Self::Helium,
            "firefox" => Self::Firefox,
            "safari" => Self::Safari,
            _ => Self::Manual,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BrowserProfileSource {
    pub family: BrowserProfileSourceFamily,
    #[serde(default)]
    pub profile_name: Option<String>,
    pub imported_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BrowserHistoryEntry {
    pub id: String,
    pub profile_id: String,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub tab_id: Option<String>,
    pub url: String,
    #[serde(default)]
    pub title: String,
    #[serde(default = "default_visit_count")]
    pub visit_count: i64,
    pub visited_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BrowserClosedTab {
    pub id: String,
    pub profile_id: String,
    pub workspace_id: String,
    pub url: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub payload: serde_json::Value,
    pub closed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BrowserPermissionDecision {
    Ask,
    Allow,
    Deny,
}

impl BrowserPermissionDecision {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Ask => "ask",
            Self::Allow => "allow",
            Self::Deny => "deny",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "allow" => Self::Allow,
            "deny" => Self::Deny,
            _ => Self::Ask,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BrowserPermission {
    pub profile_id: String,
    pub origin: String,
    pub permission: String,
    pub decision: BrowserPermissionDecision,
    pub updated_at: DateTime<Utc>,
}

fn default_true() -> bool {
    true
}

fn default_visit_count() -> i64 {
    1
}
