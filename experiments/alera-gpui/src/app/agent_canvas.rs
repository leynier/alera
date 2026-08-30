use gpui::Context;
use serde_json::{json, Value};

use super::AleraApp;

impl AleraApp {
    pub(super) fn refresh_agent_canvas(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            self.agent_canvas_generation = self.agent_canvas_generation.wrapping_add(1);
            self.agent_canvas_action_epoch = self.agent_canvas_action_epoch.wrapping_add(1);
            self.agent_canvas_refresh_pending = false;
            self.agent_canvas_loading = false;
            self.agent_canvas_busy = false;
            self.agent_canvas_values.clear();
            self.agent_canvas_selected_id = None;
            self.agent_canvas_error = None;
            cx.notify();
            return;
        };
        if self.agent_canvas_loading {
            self.agent_canvas_refresh_pending = true;
            return;
        }
        self.agent_canvas_generation = self.agent_canvas_generation.wrapping_add(1);
        let generation = self.agent_canvas_generation;
        self.agent_canvas_loading = true;
        self.agent_canvas_error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let capabilities = bridge.request("agentCanvas.capabilities", json!({})).await;
            let catalog = bridge
                .request(
                    "agentCanvas.catalog",
                    json!({"workspaceId": workspace_id.clone(), "includeHistory": true}),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                if generation != this.agent_canvas_generation
                    || this.selected_workspace_id.as_deref() != Some(workspace_id.as_str())
                {
                    return;
                }
                this.agent_canvas_loading = false;
                match capabilities {
                    Ok(value) => this.agent_canvas_capabilities = Some(value),
                    Err(error) => this.agent_canvas_error = Some(error.into()),
                }
                match catalog {
                    Ok(value) => {
                        this.agent_canvas_values = value
                            .get("canvases")
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default();
                        if this.agent_canvas_selected_id.as_ref().is_some_and(|id| {
                            !this
                                .agent_canvas_values
                                .iter()
                                .any(|canvas| value_string(canvas, "id").as_deref() == Some(id))
                        }) {
                            this.agent_canvas_selected_id = None;
                        }
                    }
                    Err(error) => this.agent_canvas_error = Some(error.into()),
                }
                if std::mem::take(&mut this.agent_canvas_refresh_pending) {
                    this.refresh_agent_canvas(cx);
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn agent_canvas_action(&mut self, request_type: &str, payload: Value, cx: &mut Context<Self>) {
        if self.agent_canvas_busy {
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else { return; };
        if !self.agent_canvas_values.iter().any(|canvas| canvas["id"] == payload["canvasId"] && canvas["workspaceId"] == workspace_id) { return; }
        self.agent_canvas_busy = true;
        self.agent_canvas_action_epoch = self.agent_canvas_action_epoch.wrapping_add(1);
        let epoch = self.agent_canvas_action_epoch;
        let bridge = self.bridge.clone();
        let request_type = request_type.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request_type, payload).await;
            let _ = this.update(cx, |this, cx| {
                // Catalog events can arrive before the action reply. They do not own this lease.
                if !action_is_current(epoch, &workspace_id, this.agent_canvas_action_epoch, this.selected_workspace_id.as_deref()) {
                    return;
                }
                this.agent_canvas_busy = false;
                if let Err(error) = result {
                    this.canvas_ui_message(error, cx);
                } else {
                    this.agent_canvas_error = None;
                    this.refresh_agent_canvas(cx);
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }
}

fn action_is_current(epoch: u64, workspace: &str, current_epoch: u64, current_workspace: Option<&str>) -> bool {
    epoch == current_epoch && current_workspace == Some(workspace)
}

#[cfg(test)]
mod request_tests {
    #[test]
    fn agent_canvas_action_reply_is_independent_of_catalog_refresh() {
        let action_epoch = 1;
        for _catalog_epoch in 1..5 {
            assert!(super::action_is_current(action_epoch, "a", action_epoch, Some("a")));
        }
        assert!(!super::action_is_current(action_epoch, "a", action_epoch, Some("b")));
        assert!(!super::action_is_current(action_epoch, "a", action_epoch + 2, Some("a")));
    }
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}
