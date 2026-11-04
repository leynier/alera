//! OpenCode 1.x session permission rules. 2.x uses [`crate::PermissionRule`]
//! under `permissions`; 1.x uses `{permission, pattern, action}` under
//! `permission`, and the last matching rule wins in both.

use crate::{Generation, HttpTransport, OpenCodeClient, OpenCodeError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LegacyPermissionRule {
    pub permission: String,
    pub pattern: String,
    pub action: String,
}

impl LegacyPermissionRule {
    pub fn new(permission: &str, pattern: &str, action: &str) -> Self {
        Self {
            permission: permission.into(),
            pattern: pattern.into(),
            action: action.into(),
        }
    }

    /// The rules a 1.x session record carries; malformed entries are skipped.
    pub fn from_session(session: &Value) -> Option<Vec<Self>> {
        let rules = session.get("permission")?.as_array()?;
        Some(
            rules
                .iter()
                .filter_map(|rule| serde_json::from_value(rule.clone()).ok())
                .collect(),
        )
    }
}

impl<T: HttpTransport> OpenCodeClient<T> {
    /// Replaces a 1.x session's permission rules.
    pub async fn update_session_legacy_permission(
        &mut self,
        session_id: &str,
        rules: &[LegacyPermissionRule],
    ) -> Result<Value, OpenCodeError> {
        if self.config().generation != Generation::Legacy1 {
            return Err(OpenCodeError::Unsupported(
                "legacy session permission rules are only available in OpenCode 1.x".into(),
            ));
        }
        Ok(self
            .raw_request(
                "PATCH",
                &format!("/session/{session_id}"),
                Some(json!({ "permission": rules })),
            )
            .await?
            .body)
    }

    /// A session's full native record, including its permission rules.
    pub async fn session_record(&mut self, session_id: &str) -> Result<Value, OpenCodeError> {
        let body = self
            .raw_request("GET", &format!("/session/{session_id}"), None)
            .await?
            .body;
        Ok(body.get("data").cloned().unwrap_or(body))
    }
}
