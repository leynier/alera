use alera_core::runtime::{BrowserClosedTab, WorkbenchLayoutRecord, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::browser_catalog_requests::browser_failure;
use super::browser_url_privacy::{browser_url_for_persistence, sanitize_browser_tab_payload};
use super::requests::{optional_string_key, require_string_key};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_browser_tab_request(
        &mut self,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let value = match request_type {
            "browser.tabs.list" => {
                let workspace_id = optional_string_key(payload, "workspaceId");
                let tabs = self.list_browser_tabs(workspace_id.as_deref()).await?;
                let items = tabs
                    .into_iter()
                    .map(|tab| {
                        let live = self.browser.page(&tab.id).cloned();
                        json!({"tab": tab, "livePage": live})
                    })
                    .collect::<Vec<_>>();
                json!({"ok": true, "tabs": items})
            }
            "browser.tabs.get" => {
                let page_id = page_id(payload)?;
                let Some(mut tab) = self
                    .runtime_store
                    .find_workspace_tab(&page_id)
                    .await
                    .map_err(store_error)?
                else {
                    return Ok(Some(browser_failure(
                        "page_not_found",
                        format!("Browser tab {page_id} was not found."),
                        &["List browser tabs and retry with a current page id."],
                    )));
                };
                if tab.kind != "browser" {
                    return Ok(Some(not_browser_tab(&page_id)));
                }
                sanitize_browser_tab_payload(&mut tab.payload);
                json!({
                    "ok": true,
                    "tab": tab,
                    "livePage": self.browser.page(&page_id),
                })
            }
            "browser.tabs.open" => self.open_browser_tab(payload).await?,
            "browser.tabs.close" => self.close_browser_tab(payload).await?,
            "browser.tabs.reopen" | "browser.closedTabs.reopen" => {
                self.reopen_browser_tab(payload).await?
            }
            _ => return Ok(None),
        };
        Ok(Some(value))
    }

    async fn list_browser_tabs(
        &self,
        workspace_id: Option<&str>,
    ) -> HostResult<Vec<WorkspaceTabRecord>> {
        let mut tabs = Vec::new();
        if let Some(workspace_id) = workspace_id {
            tabs.extend(
                self.runtime_store
                    .list_workspace_tabs(workspace_id)
                    .await
                    .map_err(store_error)?,
            );
        } else {
            for workspace in self
                .runtime_store
                .list_all_workspaces()
                .await
                .map_err(store_error)?
            {
                tabs.extend(
                    self.runtime_store
                        .list_workspace_tabs(&workspace.id)
                        .await
                        .map_err(store_error)?,
                );
            }
        }
        tabs.retain(|tab| tab.kind == "browser");
        for tab in &mut tabs {
            sanitize_browser_tab_payload(&mut tab.payload);
        }
        Ok(tabs)
    }

    async fn open_browser_tab(&mut self, payload: &Value) -> HostResult<Value> {
        if !self.browser.stable_driver_available() {
            return Ok(browser_failure(
                "browser_unavailable",
                "No Alera app browser driver currently passes the stable capability gate."
                    .to_string(),
                &["Open the desktop app on a supported platform and wait for it to synchronize."],
            ));
        }
        let workspace_id = require_string_key(payload, "workspaceId")?;
        if self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(store_error)?
            .is_none()
        {
            return Ok(browser_failure(
                "workspace_not_found",
                format!("Workspace {workspace_id} was not found."),
                &["List workspaces and retry with a current workspace id."],
            ));
        }
        let profile_id =
            optional_string_key(payload, "profileId").unwrap_or_else(|| "default".to_string());
        if self
            .runtime_store
            .find_browser_profile(&profile_id)
            .await
            .map_err(store_error)?
            .is_none()
        {
            return Ok(browser_failure(
                "profile_not_found",
                format!("Browser profile {profile_id} was not found."),
                &["List browser profiles and retry with a current profile id."],
            ));
        }
        let page_id = optional_string_key(payload, "pageId")
            .or_else(|| optional_string_key(payload, "tabId"))
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        if self
            .runtime_store
            .find_workspace_tab(&page_id)
            .await
            .map_err(store_error)?
            .is_some()
        {
            return Ok(browser_failure(
                "page_exists",
                format!("A workspace tab already uses page id {page_id}."),
                &["Omit --page-id or choose a unique page id."],
            ));
        }
        let requested_url = optional_string_key(payload, "url")
            .or_else(|| optional_string_key(payload, "initialUrl"))
            .unwrap_or_else(|| "about:blank".to_string());
        let stored_url = browser_url_for_persistence(&requested_url)
            .unwrap_or_else(|| "about:blank".to_string());
        let title = optional_string_key(payload, "title").unwrap_or_else(|| "New Tab".to_string());
        let now = Utc::now();
        let tab = WorkspaceTabRecord {
            id: page_id.clone(),
            workspace_id: workspace_id.clone(),
            kind: "browser".to_string(),
            title,
            created_at: now,
            updated_at: now,
            payload: json!({
                "browserProfileId": profile_id,
                "browserUrl": stored_url,
            }),
        };
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(store_error)?;
        let target_group_id = optional_string_key(payload, "targetGroupId");
        let group_id = match self
            .add_tab_to_layout(&workspace_id, &page_id, target_group_id.as_deref())
            .await
        {
            Ok(group_id) => group_id,
            Err(error) => {
                let _ = self.runtime_store.remove_workspace_tab(&page_id).await;
                return Err(error);
            }
        };
        self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "workbenchLayoutsChanged",
            json!({"workspaceId": workspace_id}),
        ));
        Ok(json!({
            "ok": true,
            "pageId": page_id,
            "tab": tab,
            "layoutTarget": {"groupId": group_id},
            "urlWasSanitized": requested_url != stored_url,
        }))
    }

    async fn close_browser_tab(&mut self, payload: &Value) -> HostResult<Value> {
        let page_id = page_id(payload)?;
        let Some(tab) = self
            .runtime_store
            .find_workspace_tab(&page_id)
            .await
            .map_err(store_error)?
        else {
            return Ok(browser_failure(
                "page_not_found",
                format!("Browser tab {page_id} was not found."),
                &["List browser tabs and retry with a current page id."],
            ));
        };
        if tab.kind != "browser" {
            return Ok(not_browser_tab(&page_id));
        }
        let profile_id = tab
            .payload
            .get("browserProfileId")
            .and_then(Value::as_str)
            .unwrap_or("default")
            .to_string();
        let url = tab
            .payload
            .get("browserUrl")
            .and_then(Value::as_str)
            .and_then(browser_url_for_persistence)
            .unwrap_or_else(|| "about:blank".to_string());
        let mut closed_payload = tab.payload.clone();
        sanitize_browser_tab_payload(&mut closed_payload);
        let closed = BrowserClosedTab {
            id: Uuid::new_v4().to_string(),
            profile_id,
            workspace_id: tab.workspace_id.clone(),
            url,
            title: tab.title.clone(),
            payload: closed_payload,
            closed_at: Utc::now(),
        };
        self.runtime_store
            .record_closed_browser_tab(closed.clone())
            .await
            .map_err(store_error)?;
        if let Err(error) = self.runtime_store.remove_workspace_tab(&page_id).await {
            let _ = self
                .runtime_store
                .remove_closed_browser_tab(&closed.id)
                .await;
            return Err(store_error(error));
        }
        if let Err(error) = self
            .remove_tab_from_layout(&tab.workspace_id, &page_id)
            .await
        {
            let _ = self.runtime_store.upsert_workspace_tab(tab.clone()).await;
            let _ = self
                .runtime_store
                .remove_closed_browser_tab(&closed.id)
                .await;
            return Err(error);
        }
        self.handle_browser_tab_removed(&page_id);
        self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "workbenchLayoutsChanged",
            json!({"workspaceId": tab.workspace_id}),
        ));
        Ok(json!({"ok": true, "closed": true, "pageId": page_id}))
    }

    async fn reopen_browser_tab(&mut self, payload: &Value) -> HostResult<Value> {
        let closed_id = require_string_key(payload, "id")?;
        let closed = self
            .runtime_store
            .list_closed_browser_tabs(None, 1_000)
            .await
            .map_err(store_error)?
            .into_iter()
            .find(|tab| tab.id == closed_id);
        let Some(closed) = closed else {
            return Ok(browser_failure(
                "closed_tab_not_found",
                format!("Closed browser tab {closed_id} was not found."),
                &["List recently closed tabs and retry with a current id."],
            ));
        };
        let mut open_payload = json!({
            "workspaceId": closed.workspace_id,
            "profileId": closed.profile_id,
            "url": closed.url,
            "title": closed.title,
        });
        if let Some(group_id) = optional_string_key(payload, "targetGroupId") {
            open_payload["targetGroupId"] = json!(group_id);
        }
        let previous_layout = self
            .runtime_store
            .find_workbench_layout(&closed.workspace_id)
            .await
            .map_err(store_error)?;
        let mut result = self.open_browser_tab(&open_payload).await?;
        if result["ok"].as_bool() == Some(true) {
            let page_id = result["pageId"]
                .as_str()
                .ok_or_else(|| HostError::state("successful browser open has no page id"))?
                .to_string();
            let reopened: HostResult<_> = async {
                let mut reopened = self
                    .runtime_store
                    .find_workspace_tab(&page_id)
                    .await
                    .map_err(store_error)?
                    .ok_or_else(|| HostError::state("successful browser open lost its tab"))?;
                reopened.payload = closed.payload.clone();
                if !reopened.payload.is_object() {
                    reopened.payload = json!({});
                }
                let restored_payload = reopened.payload.as_object_mut().unwrap();
                restored_payload.insert("browserProfileId".to_string(), json!(closed.profile_id));
                restored_payload.insert("browserUrl".to_string(), json!(closed.url));
                reopened.updated_at = Utc::now();
                let reopened = self
                    .runtime_store
                    .upsert_workspace_tab(reopened)
                    .await
                    .map_err(store_error)?;
                self.runtime_store
                    .remove_closed_browser_tab(&closed_id)
                    .await
                    .map_err(store_error)?;
                Ok(reopened)
            }
            .await;
            let reopened = match reopened {
                Ok(reopened) => reopened,
                Err(error) => {
                    if let Err(rollback_error) = self
                        .rollback_reopened_browser_tab(
                            &closed.workspace_id,
                            &page_id,
                            previous_layout,
                        )
                        .await
                    {
                        return Err(HostError::state(format!(
                            "{error}; reopen rollback failed: {rollback_error}"
                        )));
                    }
                    return Err(error);
                }
            };
            result["tab"] = json!(reopened);
            self.broadcast_workspace_tabs_changed(Some(&closed.workspace_id));
        }
        Ok(result)
    }

    async fn add_tab_to_layout(
        &self,
        workspace_id: &str,
        tab_id: &str,
        requested_group_id: Option<&str>,
    ) -> HostResult<String> {
        let existing = self
            .runtime_store
            .find_workbench_layout(workspace_id)
            .await
            .map_err(store_error)?;
        let (mut data, group_id) = match existing {
            Some(layout) => {
                let group_id = requested_group_id
                    .map(str::to_string)
                    .or_else(|| {
                        layout
                            .data
                            .get("activeGroupId")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                    })
                    .ok_or_else(|| HostError::state("workbench layout has no active group"))?;
                (layout.data, group_id)
            }
            None => {
                let group_id = requested_group_id
                    .map(str::to_string)
                    .unwrap_or_else(|| format!("{workspace_id}/main"));
                let tabs = self
                    .runtime_store
                    .list_workspace_tabs(workspace_id)
                    .await
                    .map_err(store_error)?
                    .into_iter()
                    .map(|tab| tab.id)
                    .collect::<Vec<_>>();
                (
                    json!({
                        "workspaceId": workspace_id,
                        "root": {"type": "leaf", "groupId": group_id},
                        "groups": {
                            group_id.clone(): {
                                "id": group_id,
                                "tabIds": tabs,
                                "activeTabId": tab_id,
                            }
                        },
                        "activeGroupId": group_id,
                    }),
                    group_id,
                )
            }
        };
        let groups = data
            .get_mut("groups")
            .and_then(Value::as_object_mut)
            .ok_or_else(|| HostError::state("workbench layout groups are invalid"))?;
        let group = groups
            .get_mut(&group_id)
            .and_then(Value::as_object_mut)
            .ok_or_else(|| HostError::state(format!("workbench group not found: {group_id}")))?;
        let tab_ids = group
            .entry("tabIds")
            .or_insert_with(|| json!([]))
            .as_array_mut()
            .ok_or_else(|| HostError::state("workbench group tabIds are invalid"))?;
        if !tab_ids.iter().any(|value| value.as_str() == Some(tab_id)) {
            tab_ids.push(json!(tab_id));
        }
        group.insert("activeTabId".to_string(), json!(tab_id));
        data["activeGroupId"] = json!(group_id);
        self.runtime_store
            .upsert_workbench_layout(WorkbenchLayoutRecord {
                workspace_id: workspace_id.to_string(),
                data,
            })
            .await
            .map_err(store_error)?;
        Ok(group_id)
    }

    async fn remove_tab_from_layout(&self, workspace_id: &str, tab_id: &str) -> HostResult<()> {
        let Some(mut layout) = self
            .runtime_store
            .find_workbench_layout(workspace_id)
            .await
            .map_err(store_error)?
        else {
            return Ok(());
        };
        let Some(groups) = layout.data.get_mut("groups").and_then(Value::as_object_mut) else {
            return Ok(());
        };
        for group in groups.values_mut().filter_map(Value::as_object_mut) {
            let was_active = group.get("activeTabId").and_then(Value::as_str) == Some(tab_id);
            let Some(tab_ids) = group.get_mut("tabIds").and_then(Value::as_array_mut) else {
                continue;
            };
            tab_ids.retain(|value| value.as_str() != Some(tab_id));
            let next_active = was_active.then(|| tab_ids.last().cloned().unwrap_or(Value::Null));
            if let Some(next_active) = next_active {
                group.insert("activeTabId".to_string(), next_active);
            }
        }
        self.runtime_store
            .upsert_workbench_layout(layout)
            .await
            .map_err(store_error)?;
        Ok(())
    }
}

fn page_id(payload: &Value) -> HostResult<String> {
    optional_string_key(payload, "pageId")
        .or_else(|| optional_string_key(payload, "tabId"))
        .ok_or_else(|| HostError::format("pageId is required."))
}

fn not_browser_tab(page_id: &str) -> Value {
    browser_failure(
        "not_browser_tab",
        format!("Workspace tab {page_id} is not a browser tab."),
        &["Choose a tab whose kind is browser."],
    )
}

fn store_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
#[path = "browser_tab_requests_tests.rs"]
mod tests;
