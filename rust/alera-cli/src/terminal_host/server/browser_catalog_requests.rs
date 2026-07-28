use alera_core::runtime::{
    BrowserPermission, BrowserPermissionDecision, BrowserProfile, BrowserProfileSource,
    BrowserSettings, DEFAULT_BROWSER_PROFILE_ID,
};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::requests::{optional_string_key, require_string_key};
use super::ServerActor;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BrowserProfileUpsert {
    id: Option<String>,
    name: String,
    #[serde(default = "default_true")]
    persistent: bool,
    #[serde(default)]
    is_default: bool,
    #[serde(default)]
    source: Option<BrowserProfileSource>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BrowserPermissionUpsert {
    profile_id: String,
    origin: String,
    permission: String,
    decision: BrowserPermissionDecision,
}

impl ServerActor {
    pub(super) async fn handle_browser_catalog_request(
        &mut self,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let value = match request_type {
            "browser.settings.get" => {
                let settings = self
                    .runtime_store
                    .browser_settings()
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "settings": settings})
            }
            "browser.settings.set" => {
                let settings: BrowserSettings =
                    serde_json::from_value(payload.clone()).map_err(|error| {
                        HostError::format(format!("invalid browser settings: {error}"))
                    })?;
                let settings = self
                    .runtime_store
                    .set_browser_settings(settings)
                    .await
                    .map_err(store_error)?;
                self.broadcast_authenticated(crate::terminal_host::protocol::event(
                    "browserSettingsChanged",
                    json!({"settings": settings}),
                ));
                json!({"ok": true, "settings": settings})
            }
            "browser.profiles.list" => {
                self.runtime_store
                    .ensure_default_browser_profile()
                    .await
                    .map_err(store_error)?;
                let profiles = self
                    .runtime_store
                    .list_browser_profiles()
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "profiles": profiles})
            }
            "browser.profiles.upsert" => {
                let request: BrowserProfileUpsert = serde_json::from_value(payload.clone())
                    .map_err(|error| {
                        HostError::format(format!("invalid browser profile: {error}"))
                    })?;
                let id = request
                    .id
                    .map(|id| id.trim().to_string())
                    .filter(|id| !id.is_empty())
                    .unwrap_or_else(|| Uuid::new_v4().to_string());
                let existing = self
                    .runtime_store
                    .find_browser_profile(&id)
                    .await
                    .map_err(store_error)?;
                let now = Utc::now();
                let profile = self
                    .runtime_store
                    .upsert_browser_profile(BrowserProfile {
                        id,
                        name: request.name,
                        persistent: request.persistent,
                        is_default: request.is_default,
                        source: request.source.or_else(|| {
                            existing.as_ref().and_then(|profile| profile.source.clone())
                        }),
                        created_at: existing.as_ref().map_or(now, |profile| profile.created_at),
                        updated_at: now,
                    })
                    .await
                    .map_err(store_error)?;
                self.broadcast_browser_profiles_changed();
                json!({"ok": true, "profile": profile})
            }
            "browser.profiles.validateRemoval" => {
                let id = require_string_key(payload, "id")?;
                if id == DEFAULT_BROWSER_PROFILE_ID {
                    return Ok(Some(browser_failure(
                        "default_profile",
                        "The default browser profile cannot be removed.".to_string(),
                        &["Choose an isolated browser profile instead."],
                    )));
                }
                if self.browser_profile_is_in_use(&id).await? {
                    return Ok(Some(profile_in_use_failure(&id)));
                }
                json!({"ok": true, "id": id})
            }
            "browser.profiles.remove" => {
                let id = require_string_key(payload, "id")?;
                if self.browser_profile_is_in_use(&id).await? {
                    return Ok(Some(profile_in_use_failure(&id)));
                }
                let removed = self
                    .runtime_store
                    .remove_browser_profile(&id)
                    .await
                    .map_err(store_error)?;
                self.broadcast_browser_profiles_changed();
                json!({"ok": true, "removed": removed, "id": id})
            }
            "browser.history.list" => {
                let profile_id = optional_string_key(payload, "profileId");
                let limit = list_limit(payload);
                let entries = self
                    .runtime_store
                    .list_browser_history(profile_id.as_deref(), limit)
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "entries": entries})
            }
            "browser.history.clear" => {
                let profile_id = optional_string_key(payload, "profileId");
                let removed = self
                    .runtime_store
                    .clear_browser_history(profile_id.as_deref())
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "removed": removed})
            }
            "browser.closedTabs.list" => {
                let profile_id = optional_string_key(payload, "profileId");
                let tabs = self
                    .runtime_store
                    .list_closed_browser_tabs(profile_id.as_deref(), list_limit(payload))
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "tabs": tabs})
            }
            "browser.closedTabs.remove" => {
                let id = require_string_key(payload, "id")?;
                let removed = self
                    .runtime_store
                    .remove_closed_browser_tab(&id)
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "removed": removed, "id": id})
            }
            "browser.permissions.list" => {
                let profile_id = optional_string_key(payload, "profileId");
                let origin = optional_string_key(payload, "origin");
                let permissions = self
                    .runtime_store
                    .list_browser_permissions(profile_id.as_deref(), origin.as_deref())
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "permissions": permissions})
            }
            "browser.permissions.set" => {
                let request: BrowserPermissionUpsert = serde_json::from_value(payload.clone())
                    .map_err(|error| {
                        HostError::format(format!("invalid browser permission: {error}"))
                    })?;
                let permission = self
                    .runtime_store
                    .upsert_browser_permission(BrowserPermission {
                        profile_id: request.profile_id,
                        origin: request.origin,
                        permission: request.permission,
                        decision: request.decision,
                        updated_at: Utc::now(),
                    })
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "permission": permission})
            }
            "browser.permissions.remove" => {
                let profile_id = require_string_key(payload, "profileId")?;
                let origin = require_string_key(payload, "origin")?;
                let permission = require_string_key(payload, "permission")?;
                let removed = self
                    .runtime_store
                    .remove_browser_permission(&profile_id, &origin, &permission)
                    .await
                    .map_err(store_error)?;
                json!({"ok": true, "removed": removed})
            }
            _ => return Ok(None),
        };
        Ok(Some(value))
    }

    async fn browser_profile_is_in_use(&self, profile_id: &str) -> HostResult<bool> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(store_error)?;
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(store_error)?;
            if tabs.into_iter().any(|tab| {
                tab.kind == "browser"
                    && tab
                        .payload
                        .get("browserProfileId")
                        .and_then(Value::as_str)
                        .unwrap_or("default")
                        == profile_id
            }) {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn broadcast_browser_profiles_changed(&self) {
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "browserProfilesChanged",
            json!({}),
        ));
    }
}

fn profile_in_use_failure(id: &str) -> Value {
    browser_failure(
        "profile_in_use",
        format!("Browser profile {id} is used by an open tab."),
        &["Close or move every tab using this profile and retry."],
    )
}

pub(super) fn browser_failure(code: &str, message: String, next_steps: &[&str]) -> Value {
    let retryable = !matches!(
        code,
        "default_profile"
            | "not_browser_tab"
            | "not_page_owner"
            | "not_request_owner"
            | "page_exists"
            | "profile_in_use"
            | "workspace_not_found"
    );
    json!({
        "ok": false,
        "error": {
            "code": code,
            "message": message,
            "nextSteps": next_steps,
            "retryable": retryable,
        }
    })
}

fn list_limit(payload: &Value) -> i64 {
    payload
        .get("limit")
        .and_then(Value::as_i64)
        .unwrap_or(100)
        .clamp(1, 1_000)
}

fn store_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

fn default_true() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use crate::terminal_host::server::actor_test_harness::test_actor;

    use super::*;

    #[tokio::test]
    async fn profile_removal_validation_does_not_mutate_the_catalog() {
        let dir = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        let now = Utc::now();
        actor
            .runtime_store
            .upsert_browser_profile(BrowserProfile {
                id: "work".to_string(),
                name: "Work".to_string(),
                persistent: true,
                is_default: false,
                source: None,
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();

        let response = actor
            .handle_browser_catalog_request(
                "browser.profiles.validateRemoval",
                &json!({"id": "work"}),
            )
            .await
            .unwrap()
            .unwrap();

        assert_eq!(response["ok"], true);
        assert!(actor
            .runtime_store
            .find_browser_profile("work")
            .await
            .unwrap()
            .is_some());
    }
}
