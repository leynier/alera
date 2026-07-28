use std::sync::Arc;

use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::terminal_host::emulator::{
    AndroidLogcatQuery, EmulatorFailure, EmulatorManager, EmulatorResult,
};
use crate::terminal_host::protocol::MOBILE_EMULATOR_TAB_KIND;

use super::emulator_request_payloads::*;

struct EmulatorRequestContext<'a> {
    manager: Option<&'a mut EmulatorManager>,
    runtime_store: RuntimeStore,
    client_id: u64,
    broadcast: Option<EmulatorBroadcast>,
    pointer_transition: Option<PointerTransition>,
}

impl EmulatorRequestContext<'_> {
    async fn try_emulator_request(
        &mut self,
        request_type: &str,
        payload: &Value,
    ) -> EmulatorResult<Value> {
        if request_type == "emulator.capabilities" {
            return Ok(match self.manager.as_deref() {
                Some(manager) => manager.capabilities().await,
                None => unavailable_capabilities(),
            });
        }
        if request_type == "emulator.devices" {
            let platform = optional_platform(payload)?;
            let manager = self.manager_mut()?;
            let items = manager.devices(platform).await?;
            return Ok(json!({
                "ok": true,
                "kind": "emulatorDevices",
                "items": items,
                "filters": {"platform": platform},
            }));
        }
        if request_type == "emulator.attach" {
            return self.attach_emulator(payload).await;
        }
        if request_type == "emulator.list" {
            let workspace_id = payload.get("workspaceId").and_then(Value::as_str);
            return Ok(self.manager_mut()?.list(workspace_id));
        }

        let tab = self.resolve_emulator_tab(payload).await?;
        let tab_id = tab.id.as_str();
        if matches!(
            request_type,
            "emulator.release" | "emulator.detach" | "emulator.shutdown"
        ) && !self.manager_mut()?.contains(tab_id)
        {
            self.broadcast = Some(EmulatorBroadcast {
                tab_id: tab.id.clone(),
                workspace_id: tab.workspace_id.clone(),
                reason: if request_type == "emulator.shutdown" {
                    "shutdown"
                } else {
                    "released"
                },
                workspace_tabs_changed: false,
            });
            if request_type == "emulator.shutdown" {
                return Ok(json!({"ok": true, "stopped": true, "warnings": []}));
            }
            return Ok(json!({
                "ok": true,
                "session": parked_session_value(&tab)?,
            }));
        }
        self.ensure_emulator_session(&tab).await?;
        let snapshot_id = payload.get("snapshotId").and_then(Value::as_str);
        match request_type {
            "emulator.acquire" => {
                let client_id = self.client_id;
                let (session, helper_restarted) =
                    self.manager_mut()?.acquire(tab_id, client_id).await?;
                if helper_restarted {
                    self.broadcast = Some(EmulatorBroadcast {
                        tab_id: tab.id.clone(),
                        workspace_id: tab.workspace_id.clone(),
                        reason: "updated",
                        workspace_tabs_changed: false,
                    });
                }
                Ok(json!({"ok": true, "session": session}))
            }
            "emulator.release" | "emulator.detach" => {
                let client_id = self.client_id;
                let session = self.manager_mut()?.release(tab_id, client_id).await?;
                self.broadcast = Some(EmulatorBroadcast {
                    tab_id: tab.id.clone(),
                    workspace_id: tab.workspace_id.clone(),
                    reason: "released",
                    workspace_tabs_changed: false,
                });
                Ok(json!({"ok": true, "session": session}))
            }
            "emulator.shutdown" => {
                let warnings = self.manager_mut()?.close_tab(tab_id).await;
                let stopped = warnings.is_empty();
                self.broadcast = Some(EmulatorBroadcast {
                    tab_id: tab.id.clone(),
                    workspace_id: tab.workspace_id.clone(),
                    reason: if stopped { "shutdown" } else { "updated" },
                    workspace_tabs_changed: false,
                });
                Ok(json!({"ok": true, "stopped": stopped, "warnings": warnings}))
            }
            "emulator.snapshot" => {
                let include = payload
                    .get("includeScreenshot")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let result = self.manager_mut()?.snapshot(tab_id, include).await;
                self.manager_mut()?.park_if_unleased(tab_id).await;
                result
            }
            "emulator.tap" => {
                let (x, y) = coordinates(payload)?;
                let result = self.manager_mut()?.tap(tab_id, snapshot_id, x, y).await;
                self.manager_mut()?.park_if_unleased(tab_id).await;
                result?;
                Ok(action_ok(tab_id))
            }
            "emulator.pointer" => {
                if !interactive_input(payload) {
                    return Err(EmulatorFailure::invalid(
                        "Pointer events are available only to an acquired interactive surface.",
                    ));
                }
                let (x, y) = coordinates(payload)?;
                let kind = required_string(payload, "type")?;
                let client_id = self.client_id;
                self.manager_mut()?
                    .pointer(tab_id, client_id, kind, x, y)
                    .await?;
                self.pointer_transition = match kind {
                    "begin" => Some(PointerTransition::Began {
                        tab_id: tab_id.to_string(),
                        client_id,
                    }),
                    "end" => Some(PointerTransition::Ended {
                        tab_id: tab_id.to_string(),
                        client_id,
                    }),
                    _ => None,
                };
                Ok(action_ok(tab_id))
            }
            "emulator.gesture" => {
                let points = gesture_points(payload)?;
                let duration = payload
                    .get("durationMs")
                    .and_then(Value::as_u64)
                    .unwrap_or(300)
                    .clamp(1, 60_000);
                let result = self
                    .manager_mut()?
                    .gesture(tab_id, snapshot_id, &points, duration)
                    .await;
                self.manager_mut()?.park_if_unleased(tab_id).await;
                result?;
                Ok(action_ok(tab_id))
            }
            "emulator.type" => {
                let text = required_text(payload)?;
                if interactive_input(payload) {
                    let client_id = self.client_id;
                    self.manager_mut()?
                        .type_text_interactive(tab_id, client_id, text)
                        .await?;
                } else {
                    let result = self
                        .manager_mut()?
                        .type_text(tab_id, snapshot_id, text)
                        .await;
                    self.manager_mut()?.park_if_unleased(tab_id).await;
                    result?;
                }
                Ok(action_ok(tab_id))
            }
            "emulator.key" => {
                if !interactive_input(payload) {
                    return Err(EmulatorFailure::invalid(
                        "Key events are available only to an acquired interactive surface.",
                    ));
                }
                let key = required_string(payload, "key")?;
                let client_id = self.client_id;
                self.manager_mut()?
                    .key_interactive(tab_id, client_id, key)
                    .await?;
                Ok(action_ok(tab_id))
            }
            "emulator.button" => {
                let button = required_string(payload, "button")?;
                let result = self
                    .manager_mut()?
                    .button(tab_id, snapshot_id, button)
                    .await;
                self.manager_mut()?.park_if_unleased(tab_id).await;
                result?;
                Ok(action_ok(tab_id))
            }
            "emulator.rotate" => {
                let orientation = required_string(payload, "orientation")?;
                let result = self
                    .manager_mut()?
                    .rotate(tab_id, snapshot_id, orientation)
                    .await;
                self.manager_mut()?.park_if_unleased(tab_id).await;
                result?;
                self.broadcast = Some(EmulatorBroadcast {
                    tab_id: tab.id.clone(),
                    workspace_id: tab.workspace_id.clone(),
                    reason: "updated",
                    workspace_tabs_changed: false,
                });
                Ok(action_ok(tab_id))
            }
            "emulator.install" => {
                let path = required_string(payload, "path")?;
                self.manager_mut()?.install(tab_id, path).await?;
                Ok(action_ok(tab_id))
            }
            "emulator.launch" => {
                let bundle_id = required_string(payload, "bundleId")?;
                let activity = optional_string(payload, "activity")?;
                let launch = self
                    .manager_mut()?
                    .launch(tab_id, bundle_id, activity)
                    .await?;
                Ok(json!({"ok": true, "tabId": tab_id, "launch": launch}))
            }
            "emulator.permission" => {
                let bundle_id = required_string(payload, "bundleId")?;
                let permission = required_string(payload, "permission")?;
                let operation = required_string(payload, "operation")?;
                self.manager_mut()?
                    .permission(tab_id, operation, bundle_id, permission)
                    .await?;
                Ok(action_ok(tab_id))
            }
            "emulator.logcat" => {
                let request = logcat_request(payload)?;
                let raw = self
                    .manager_mut()?
                    .logcat(
                        tab_id,
                        &AndroidLogcatQuery {
                            max_lines: request.max_lines,
                            tags: &request.tags,
                            level: request.level.as_deref(),
                            since_epoch: request.since_epoch.as_deref(),
                        },
                    )
                    .await?;
                let lines = filter_logcat(
                    &raw,
                    request.contains.as_deref(),
                    request.max_lines as usize,
                );
                Ok(json!({"ok": true, "tabId": tab_id, "lines": lines}))
            }
            _ => Err(EmulatorFailure::invalid(format!(
                "Unknown emulator request `{request_type}`."
            ))),
        }
    }

    async fn attach_emulator(&mut self, payload: &Value) -> EmulatorResult<Value> {
        let platform = required_platform(payload)?;
        let device_id = required_string(payload, "deviceId")?.to_string();
        let explicit_tab = payload.get("tabId").and_then(Value::as_str);
        let workspace_id = if let Some(tab_id) = explicit_tab {
            self.runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(state_failure)?
                .ok_or_else(|| tab_failure("tab_not_found", "Emulator tab not found."))?
                .workspace_id
        } else {
            required_string(payload, "workspaceId")?.to_string()
        };
        self.runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(state_failure)?
            .ok_or_else(|| {
                tab_failure(
                    "workspace_not_found",
                    &format!("Workspace `{workspace_id}` was not found."),
                )
            })?;
        let existing = self
            .runtime_store
            .list_workspace_tabs(&workspace_id)
            .await
            .map_err(state_failure)?
            .into_iter()
            .find(|tab| tab.kind == MOBILE_EMULATOR_TAB_KIND);
        let now = Utc::now();
        let (mut tab, is_new) = match existing {
            Some(tab) => {
                let stored = stored_payload(&tab)?;
                if stored.platform != platform || stored.device_id != device_id {
                    return Err(EmulatorFailure::new(
                        "invalid_argument",
                        "This workspace already has an emulator tab for another device.",
                        ["Close the existing emulator tab before selecting another device."],
                    ));
                }
                if explicit_tab.is_some_and(|id| id != tab.id) {
                    return Err(tab_failure(
                        "tab_kind_mismatch",
                        "The selected tab is not this workspace's emulator tab.",
                    ));
                }
                (tab, false)
            }
            None if explicit_tab.is_some() => {
                return Err(tab_failure(
                    "tab_kind_mismatch",
                    "The selected tab is not a mobile emulator tab.",
                ))
            }
            None => (
                WorkspaceTabRecord {
                    id: Uuid::new_v4().to_string(),
                    workspace_id: workspace_id.clone(),
                    kind: MOBILE_EMULATOR_TAB_KIND.to_string(),
                    title: "Mobile Emulator".to_string(),
                    created_at: now,
                    updated_at: now,
                    payload: json!({
                        "mobileEmulator": {
                            "schemaVersion": 1,
                            "platform": platform,
                            "deviceId": device_id,
                        }
                    }),
                },
                true,
            ),
        };
        if is_new {
            self.runtime_store
                .upsert_workspace_tab(tab.clone())
                .await
                .map_err(state_failure)?;
        }
        let session = match self
            .manager_mut()?
            .attach(workspace_id.clone(), tab.id.clone(), platform, device_id)
            .await
        {
            Ok(session) => session,
            Err(error) => {
                if is_new {
                    let _ = self.runtime_store.remove_workspace_tab(&tab.id).await;
                }
                return Err(error);
            }
        };
        if is_new {
            if let Some(device_name) = session.get("deviceName").and_then(Value::as_str) {
                let titled = WorkspaceTabRecord {
                    title: device_name.to_string(),
                    updated_at: Utc::now(),
                    ..tab.clone()
                };
                if self
                    .runtime_store
                    .upsert_workspace_tab(titled.clone())
                    .await
                    .is_ok()
                {
                    tab = titled;
                }
            }
        }
        self.broadcast = Some(EmulatorBroadcast {
            tab_id: tab.id.clone(),
            workspace_id: workspace_id.clone(),
            reason: "attached",
            workspace_tabs_changed: true,
        });
        Ok(json!({"ok": true, "tab": tab, "session": session}))
    }

    async fn resolve_emulator_tab(&self, payload: &Value) -> EmulatorResult<WorkspaceTabRecord> {
        let tab = if let Some(tab_id) = payload.get("tabId").and_then(Value::as_str) {
            self.runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(state_failure)?
        } else if let Some(workspace_id) = payload.get("workspaceId").and_then(Value::as_str) {
            self.runtime_store
                .list_workspace_tabs(workspace_id)
                .await
                .map_err(state_failure)?
                .into_iter()
                .find(|tab| tab.kind == MOBILE_EMULATOR_TAB_KIND)
        } else {
            return Err(tab_failure(
                "workspace_required",
                "An emulator tab or workspace target is required.",
            ));
        };
        let tab = tab.ok_or_else(|| tab_failure("tab_not_found", "Emulator tab not found."))?;
        if tab.kind != MOBILE_EMULATOR_TAB_KIND {
            return Err(tab_failure(
                "tab_kind_mismatch",
                "The selected tab is not a mobile emulator tab.",
            ));
        }
        Ok(tab)
    }

    async fn ensure_emulator_session(&mut self, tab: &WorkspaceTabRecord) -> EmulatorResult<()> {
        if self.manager_mut()?.contains(&tab.id) {
            return Ok(());
        }
        let stored = stored_payload(tab)?;
        self.manager_mut()?
            .attach(
                tab.workspace_id.clone(),
                tab.id.clone(),
                stored.platform,
                stored.device_id,
            )
            .await?;
        Ok(())
    }

    fn manager_mut(
        &mut self,
    ) -> EmulatorResult<&mut crate::terminal_host::emulator::EmulatorManager> {
        self.manager.as_deref_mut().ok_or_else(|| {
            EmulatorFailure::new(
                "backend_unavailable",
                "The local emulator manager could not start.",
                ["Restart Alera and check local firewall/runtime-directory permissions."],
            )
        })
    }
}

pub(super) async fn run_emulator_request(
    manager: Option<Arc<Mutex<EmulatorManager>>>,
    runtime_store: RuntimeStore,
    client_id: u64,
    request_type: &str,
    payload: &Value,
) -> EmulatorRequestCompletion {
    let mut manager = match manager {
        Some(manager) => Some(manager.lock_owned().await),
        None => None,
    };
    let mut context = EmulatorRequestContext {
        manager: manager.as_deref_mut(),
        runtime_store,
        client_id,
        broadcast: None,
        pointer_transition: None,
    };
    let response = match context.try_emulator_request(request_type, payload).await {
        Ok(value) => value,
        Err(error) => error.to_json(),
    };
    EmulatorRequestCompletion {
        response,
        broadcast: context.broadcast,
        pointer_transition: context.pointer_transition,
    }
}

#[cfg(test)]
#[path = "emulator_requests_tests.rs"]
mod tests;
