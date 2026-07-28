use std::collections::HashSet;

use alera_core::runtime::{BrowserHistoryEntry, WorkspaceTabRecord};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::browser_broker::{BrowserDriver, BrowserPage, BrowserPageChange};
use super::browser_catalog_requests::browser_failure;
use super::browser_requests::browser_page_id;
use super::browser_url_privacy::browser_url_for_persistence;
use super::requests::{optional_string_key, require_string_key};
use super::ServerActor;

#[path = "browser_driver_payload.rs"]
mod browser_driver_payload;
use browser_driver_payload::{
    completed_history_url, normalized_capabilities, normalized_page_title, store_error,
    sync_failure, tab_profile_id,
};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DriverRegistration {
    app_instance_id: String,
    driver_instance_id: String,
    #[serde(default)]
    engine: String,
    #[serde(default)]
    platform: String,
    #[serde(default)]
    capabilities: Vec<String>,
}

impl ServerActor {
    pub(super) async fn handle_browser_driver_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let value = match request_type {
            "browser.driver.register" => self.register_browser_driver(client_id, payload)?,
            "browser.driver.sync" => self.sync_browser_driver(client_id, payload).await?,
            "browser.driver.pageChanged" => {
                self.browser_driver_page_changed(client_id, payload).await?
            }
            "browser.driver.unregister" => self.unregister_browser_driver(client_id, payload)?,
            "browser.driver.complete" => self.complete_browser_driver_call(client_id, payload)?,
            _ => return Ok(None),
        };
        Ok(Some(value))
    }

    fn register_browser_driver(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        self.require_browser_app_client(client_id)?;
        let registration: DriverRegistration = serde_json::from_value(payload.clone())
            .map_err(|error| HostError::format(format!("invalid browser driver: {error}")))?;
        for (label, value) in [
            ("appInstanceId", registration.app_instance_id.as_str()),
            ("driverInstanceId", registration.driver_instance_id.as_str()),
        ] {
            if value.trim().is_empty() {
                return Err(HostError::format(format!("{label} is required.")));
            }
        }
        let driver = BrowserDriver {
            owner_client_id: client_id,
            app_instance_id: registration.app_instance_id.trim().to_string(),
            driver_instance_id: registration.driver_instance_id.trim().to_string(),
            engine: registration.engine.trim().to_string(),
            platform: registration.platform.trim().to_string(),
            capabilities: normalized_capabilities(registration.capabilities),
        };
        let drain = self.browser.register_driver(driver.clone());
        self.apply_browser_drain(
            drain,
            browser_failure(
                "driver_replaced",
                "The browser app registered a replacement driver.".to_string(),
                &["Retry after the replacement driver synchronizes its pages."],
            ),
        );
        self.broadcast_authenticated(event(
            "browserDriverChanged",
            json!({"registered": true, "driver": driver}),
        ));
        Ok(json!({"ok": true, "registered": true, "driver": driver}))
    }

    async fn sync_browser_driver(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        self.require_browser_driver_identity(client_id, payload)?;
        let pages = payload
            .get("pages")
            .and_then(Value::as_array)
            .ok_or_else(|| HostError::format("browser driver pages are required."))?;
        if pages.len() > 256 {
            return Err(HostError::format(
                "browser driver sync accepts at most 256 pages.",
            ));
        }
        let mut seen = HashSet::new();
        let mut results = Vec::with_capacity(pages.len());
        for raw in pages {
            let page_id = match browser_page_id(raw) {
                Ok(page_id) => page_id,
                Err(error) => {
                    results.push(json!({
                        "accepted": false,
                        "error": error.wire_message(),
                    }));
                    continue;
                }
            };
            seen.insert(page_id.clone());
            let Some(tab) = self
                .runtime_store
                .find_workspace_tab(&page_id)
                .await
                .map_err(store_error)?
            else {
                results.push(sync_failure(&page_id, "page_not_found"));
                continue;
            };
            if tab.kind != "browser" {
                results.push(sync_failure(&page_id, "not_browser_tab"));
                continue;
            }
            let workspace_id =
                optional_string_key(raw, "workspaceId").unwrap_or_else(|| tab.workspace_id.clone());
            if workspace_id != tab.workspace_id {
                results.push(sync_failure(&page_id, "workspace_mismatch"));
                continue;
            }
            let profile_id = optional_string_key(raw, "profileId")
                .or_else(|| tab_profile_id(&tab))
                .unwrap_or_else(|| "default".to_string());
            if self
                .runtime_store
                .find_browser_profile(&profile_id)
                .await
                .map_err(store_error)?
                .is_none()
            {
                results.push(sync_failure(&page_id, "profile_not_found"));
                continue;
            }
            let raw_url = optional_string_key(raw, "url");
            let (title, _) = normalized_page_title(raw, raw_url.as_deref());
            let page = BrowserPage {
                tab_id: page_id.clone(),
                workspace_id,
                profile_id,
                generation: 0,
                document_generation: raw
                    .get("documentGeneration")
                    .and_then(Value::as_u64)
                    .unwrap_or(0),
                url: raw_url.and_then(|url| browser_url_for_persistence(&url)),
                title,
                capabilities: raw
                    .get("capabilities")
                    .and_then(Value::as_array)
                    .map(|items| {
                        normalized_capabilities(
                            items
                                .iter()
                                .filter_map(Value::as_str)
                                .map(str::to_string)
                                .collect(),
                        )
                    })
                    .unwrap_or_default(),
                owner_client_id: client_id,
            };
            match self.browser.sync_page(client_id, page) {
                Ok((page, drain)) => {
                    self.apply_browser_drain(
                        drain,
                        browser_failure(
                            "page_resynchronized",
                            format!("Browser tab {page_id} was resynchronized."),
                            &["Take a new snapshot before retrying the operation."],
                        ),
                    );
                    results.push(json!({
                        "accepted": true,
                        "pageId": page_id,
                        "generation": page.generation,
                    }));
                }
                Err(error) => results.push(json!({
                    "accepted": false,
                    "pageId": page_id,
                    "error": error.payload()["error"].clone(),
                })),
            }
        }
        let stale_pages = self
            .browser
            .pages()
            .into_iter()
            .filter(|page| page.owner_client_id == client_id && !seen.contains(&page.tab_id))
            .map(|page| page.tab_id)
            .collect::<Vec<_>>();
        for page_id in stale_pages {
            if let Ok(drain) = self.browser.remove_page_owned(client_id, &page_id) {
                self.apply_browser_drain(
                    drain,
                    browser_failure(
                        "page_unregistered",
                        format!("Browser tab {page_id} is no longer owned by the app."),
                        &["Choose a synchronized browser tab and retry."],
                    ),
                );
            }
        }
        self.broadcast_authenticated(event(
            "browserDriverChanged",
            json!({"registered": true, "pages": self.browser.pages()}),
        ));
        Ok(json!({"ok": true, "pages": results}))
    }

    async fn browser_driver_page_changed(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_browser_driver_identity(client_id, payload)?;
        let page_id = browser_page_id(payload)?;
        let expected_generation = payload
            .get("generation")
            .and_then(Value::as_u64)
            .ok_or_else(|| HostError::format("generation is required."))?;
        let profile_id = optional_string_key(payload, "profileId");
        if let Some(profile_id) = profile_id.as_deref() {
            if self
                .runtime_store
                .find_browser_profile(profile_id)
                .await
                .map_err(store_error)?
                .is_none()
            {
                return Ok(browser_failure(
                    "profile_not_found",
                    format!("Browser profile {profile_id} was not found."),
                    &["Synchronize the page with a current browser profile."],
                ));
            }
        }
        let raw_url = optional_string_key(payload, "url");
        let persisted_page_url = raw_url.as_deref().and_then(browser_url_for_persistence);
        let (title, title_may_persist) = normalized_page_title(payload, raw_url.as_deref());
        let document_generation = payload.get("documentGeneration").and_then(Value::as_u64);
        let document_changed = payload
            .get("documentChanged")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let navigation_correlation_id = optional_string_key(payload, "navigationCorrelationId");
        let navigation_completed = payload
            .get("navigationCompleted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let (page, drain, generation_changed, preserved_navigation_correlation_id) =
            match self.browser.change_page(
                client_id,
                &page_id,
                BrowserPageChange {
                    expected_generation,
                    profile_id,
                    document_generation,
                    document_changed,
                    navigation_correlation_id,
                    url_changed: raw_url.is_some(),
                    url: persisted_page_url,
                    title: title.clone(),
                },
            ) {
                Ok(result) => result,
                Err(error) => return Ok(error.payload()),
            };
        self.apply_browser_drain(
            drain,
            browser_failure(
                "stale_page",
                format!("Browser tab {page_id} changed while an operation was active."),
                &["Take a new snapshot and retry against the new generation."],
            ),
        );
        let tab = self
            .persist_browser_page_change(
                &page,
                raw_url.as_deref(),
                title.as_deref(),
                raw_url.is_some() && !title_may_persist,
                navigation_completed,
            )
            .await?;
        self.broadcast_workspace_tabs_changed(Some(&page.workspace_id));
        Ok(json!({
            "ok": true,
            "page": page,
            "tab": tab,
            "generationChanged": generation_changed,
            "preservedNavigationCorrelationId": preserved_navigation_correlation_id,
        }))
    }

    fn unregister_browser_driver(&mut self, client_id: u64, payload: &Value) -> HostResult<Value> {
        self.require_browser_driver_identity(client_id, payload)?;
        let page_id = optional_string_key(payload, "pageId")
            .or_else(|| optional_string_key(payload, "tabId"));
        let drain = match page_id.as_deref() {
            Some(page_id) => match self.browser.remove_page_owned(client_id, page_id) {
                Ok(drain) => drain,
                Err(error) => return Ok(error.payload()),
            },
            None => self.browser.remove_driver(client_id),
        };
        self.apply_browser_drain(
            drain,
            browser_failure(
                "page_unregistered",
                "The browser app unregistered the page driver.".to_string(),
                &["Wait for the page to synchronize before retrying."],
            ),
        );
        self.broadcast_authenticated(event(
            "browserDriverChanged",
            json!({"registered": false, "pageId": page_id}),
        ));
        Ok(json!({"ok": true, "unregistered": true, "pageId": page_id}))
    }

    fn complete_browser_driver_call(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_browser_driver_identity(client_id, payload)?;
        let correlation_id = require_string_key(payload, "correlationId")?;
        let page_id = browser_page_id(payload)?;
        let generation = payload
            .get("generation")
            .and_then(Value::as_u64)
            .ok_or_else(|| HostError::format("generation is required."))?;
        let outcome = payload
            .get("outcome")
            .or_else(|| payload.get("result"))
            .cloned()
            .unwrap_or_else(|| {
                payload
                    .get("error")
                    .cloned()
                    .map_or_else(|| json!({}), |error| json!({"ok": false, "error": error}))
            });
        if self
            .browser
            .call(&correlation_id)
            .is_some_and(|call| call.deadline_at_ms <= Utc::now().timestamp_millis())
        {
            self.handle_browser_timeout(&correlation_id);
            return Ok(browser_failure(
                "timeout",
                "The browser response arrived after its deadline.".to_string(),
                &["Discard this response and wait for a new driver request."],
            ));
        }
        match self
            .browser
            .complete(client_id, &correlation_id, &page_id, generation)
        {
            Ok(completion) => {
                self.respond_browser_completion(completion, outcome);
                Ok(json!({
                    "ok": true,
                    "accepted": true,
                    "correlationId": correlation_id,
                }))
            }
            Err(error) => Ok(error.payload()),
        }
    }

    async fn persist_browser_page_change(
        &self,
        page: &BrowserPage,
        raw_url: Option<&str>,
        title: Option<&str>,
        clear_runtime_title: bool,
        navigation_completed: bool,
    ) -> HostResult<WorkspaceTabRecord> {
        let mut tab = self
            .runtime_store
            .find_workspace_tab(&page.tab_id)
            .await
            .map_err(store_error)?
            .ok_or_else(|| HostError::state(format!("browser tab not found: {}", page.tab_id)))?;
        if tab.kind != "browser" {
            return Err(HostError::state(format!(
                "workspace tab is not a browser: {}",
                page.tab_id
            )));
        }
        if !tab.payload.is_object() {
            tab.payload = json!({});
        }
        let payload = tab
            .payload
            .as_object_mut()
            .expect("browser payload was normalized");
        payload.insert("browserProfileId".to_string(), json!(page.profile_id));
        let persisted_url = raw_url.and_then(browser_url_for_persistence);
        if raw_url.is_some() {
            match persisted_url.as_deref() {
                Some(url) => {
                    payload.insert("browserUrl".to_string(), json!(url));
                }
                None => {
                    payload.remove("browserUrl");
                }
            }
        }
        if clear_runtime_title {
            payload.remove("browserRuntimeTitle");
        } else if let Some(title) = title {
            payload.insert("browserRuntimeTitle".to_string(), json!(title));
            if payload.get("manualTitle").and_then(Value::as_bool) != Some(true) {
                tab.title = title.to_string();
            }
        }
        tab.updated_at = Utc::now();
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(store_error)?;
        if let Some(url) = completed_history_url(persisted_url, navigation_completed) {
            self.runtime_store
                .record_browser_history(BrowserHistoryEntry {
                    id: Uuid::new_v4().to_string(),
                    profile_id: page.profile_id.clone(),
                    workspace_id: Some(page.workspace_id.clone()),
                    tab_id: Some(page.tab_id.clone()),
                    url,
                    title: if clear_runtime_title {
                        String::new()
                    } else {
                        title.unwrap_or(&tab.title).to_string()
                    },
                    visit_count: 1,
                    visited_at: Utc::now(),
                })
                .await
                .map_err(store_error)?;
        }
        Ok(tab)
    }

    fn require_browser_driver_identity(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<BrowserDriver> {
        self.require_browser_app_client(client_id)?;
        let driver = self
            .browser
            .driver(client_id)
            .cloned()
            .ok_or_else(|| HostError::state("Browser driver is not registered."))?;
        let requested = require_string_key(payload, "driverInstanceId")?;
        if requested != driver.driver_instance_id {
            return Err(HostError::state(
                "Browser driver instance does not own this connection.",
            ));
        }
        Ok(driver)
    }
}

#[cfg(test)]
#[path = "browser_driver_requests_tests.rs"]
mod tests;
