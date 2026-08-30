use std::rc::Rc;
use gpui::{App, ClipboardItem, Context, SharedString, Window};
use serde_json::{Value, json};

use super::{AleraApp, agent_canvas_catalog, agent_canvas_confirmation::CanvasConfirmationKind};
use crate::activity::ContextPanel;

pub(super) type CanvasActionHandler = Rc<dyn Fn(&Value, &mut Window, &mut App)>;

#[derive(Clone)]
pub(super) struct CanvasActionContext {
    pub workspace_id: String,
    pub canvas_id: String,
    pub revision: i64,
    pub source_control_path: Option<String>,
}

impl CanvasActionContext {
    pub(super) fn matches(&self, selected_workspace: Option<&str>, canvases: &[Value]) -> bool {
        selected_workspace == Some(self.workspace_id.as_str()) && canvases.iter().any(|canvas|
            canvas["id"] == self.canvas_id && canvas["revision"].as_i64() == Some(self.revision))
    }
}

pub(super) fn confirmation_kind(kind: &str) -> Option<CanvasConfirmationKind> {
    match kind {
        "stage" | "unstage" | "discard" | "commit" | "pull" | "push" | "mergePullRequest" | "terminateTerminal" | "deleteArtifact" => Some(CanvasConfirmationKind::DestructiveAction),
        "approveExecutionPlan" | "rejectExecutionPlan" | "editPullRequestComment" | "rerunValidation" => Some(CanvasConfirmationKind::ControlledAction),
        _ => None,
    }
}

impl AleraApp {
    pub(super) fn canvas_ui_message(&mut self, message: impl Into<SharedString>, cx: &mut Context<Self>) {
        self.local_message = Some(message.into());
        self.local_message_started_at = Some(std::time::Instant::now());
        cx.notify();
    }

    pub(super) fn canvas_action_handler(&self, canvas: &Value, cx: &Context<Self>) -> CanvasActionHandler {
        let context = CanvasActionContext {
            workspace_id: canvas["workspaceId"].as_str().unwrap_or_default().to_owned(),
            canvas_id: canvas["id"].as_str().unwrap_or_default().to_owned(),
            revision: canvas["revision"].as_i64().unwrap_or_default(),
            source_control_path: self.selected_source_control_scope().map(|scope| scope.path),
        };
        let owner = cx.entity().downgrade();
        Rc::new(move |action, window, cx| {
            let _ = owner.update(cx, |this, cx| this.request_canvas_ui_action(context.clone(), action.clone(), window, cx));
        })
    }

    fn request_canvas_ui_action(&mut self, context: CanvasActionContext, mut action: Value, window: &mut Window, cx: &mut Context<Self>) {
        if self.agent_canvas_busy || !context.matches(self.selected_workspace_id.as_deref(), &self.agent_canvas_values) { return; }
        let Some(kind) = action["kind"].as_str().filter(|kind| !kind.is_empty()).map(str::to_owned) else {
            self.canvas_ui_message("Agent Canvas action is missing its kind.", cx); return;
        };
        if let Some(action) = action.as_object_mut() { action.remove("confirmed"); }
        if kind == "resolveDecision" {
            let owned = self.agent_canvas_values.iter().find(|canvas| canvas["id"] == context.canvas_id)
                .and_then(|canvas| canvas["decisions"].as_array()).is_some_and(|decisions| decisions.iter().any(|decision| decision["id"] == action["decisionId"]));
            if !owned { self.canvas_ui_message("This decision does not belong to the selected Agent Canvas.", cx); return; }
            action["confirmed"] = json!(true);
        }
        if kind == "focusTerminal" && action["terminalSessionId"].as_str().is_none_or(str::is_empty) {
            if let Some(canvas) = self.agent_canvas_values.iter().find(|canvas| canvas["id"] == context.canvas_id) {
                action["terminalSessionId"] = canvas["terminalSessionId"].clone();
            }
        }
        if let Some(kind) = confirmation_kind(&kind) {
            self.request_canvas_action_confirmation(context, action, kind, window, cx);
        } else {
            self.execute_canvas_ui_action(context, action, window, cx);
        }
    }

    pub(super) fn execute_canvas_ui_action(&mut self, context: CanvasActionContext, action: Value, window: &mut Window, cx: &mut Context<Self>) {
        if self.agent_canvas_busy || !context.matches(self.selected_workspace_id.as_deref(), &self.agent_canvas_values) { return; }
        self.agent_canvas_busy = true;
        self.agent_canvas_action_epoch = self.agent_canvas_action_epoch.wrapping_add(1);
        let epoch = self.agent_canvas_action_epoch;
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge.request("agentCanvas.action", json!({"canvasId":context.canvas_id,"action":action})).await;
            let _ = this.update_in(cx, |this, window, cx| {
                if this.agent_canvas_action_epoch != epoch || this.selected_workspace_id.as_deref() != Some(context.workspace_id.as_str()) { return; }
                this.agent_canvas_busy = false;
                match result {
                    Ok(result) if result["accepted"] == true => {
                        let selected = agent_canvas_catalog::selected(&this.agent_canvas_values, this.agent_canvas_selected_id.as_deref()).is_some_and(|canvas| canvas["id"] == context.canvas_id);
                        if selected && this.context_panel == ContextPanel::AgentCanvas && context.matches(this.selected_workspace_id.as_deref(), &this.agent_canvas_values) {
                            if let Err(error) = this.perform_canvas_ui_action(&context, &action, window, cx) { this.canvas_ui_message(error, cx); }
                        }
                    }
                    Ok(_) => this.canvas_ui_message("The runtime did not accept this Agent Canvas action.", cx),
                    Err(error) => this.canvas_ui_message(error, cx),
                }
                this.refresh_agent_canvas(cx);
                cx.notify();
            });
        }).detach();
        cx.notify();
    }

    fn perform_canvas_ui_action(&mut self, context: &CanvasActionContext, action: &Value, window: &mut Window, cx: &mut Context<Self>) -> Result<(), String> {
        match action["kind"].as_str().unwrap_or_default() {
            "openFile" => if let Some(path) = action["relativePath"].as_str() { self.open_file_tab(path.into(), cx); },
            "openDiff" => if let Some(path) = action["relativePath"].as_str().and_then(|path| self.selected_source_control_scope()?.to_source_relative_path(path)) { self.open_git_diff_tab(Some(path), None, cx); },
            "openSearch" => self.select_context_panel(ContextPanel::Search, cx),
            "openPullRequest" => self.select_context_panel(ContextPanel::PullRequest, cx),
            "focusTerminal" => {
                let id = action["terminalSessionId"].as_str().unwrap_or_default();
                let tab = self.snapshot.tabs.iter().find(|tab| tab.kind == "terminal" && super::terminal_surface::terminal_session_id(tab) == id).map(|tab| tab.id.clone());
                let Some(tab) = tab else { return Err("The Agent Canvas terminal is no longer open.".into()); };
                self.activate_workspace_tab(tab, cx); self.terminal_focus.focus(window, cx);
            }
            "copyText" => if let Some(text) = action["text"].as_str() {
                cx.write_to_clipboard(ClipboardItem::new_string(text.to_owned()));
                self.canvas_ui_message("Text copied to the clipboard.", cx);
            },
            "openArtifact" => if let Some(id) = action["artifactId"].as_str() { self.canvas_ui_message(format!("Artifact {id} is registered for this Agent Canvas."), cx); },
            "switchContextPanel" => if let Some(panel) = context_panel(action["panel"].as_str().unwrap_or_default()) { self.select_context_panel(panel, cx); },
            "resolveDecision" => self.canvas_ui_message("Agent Canvas action completed.", cx),
            _ => self.perform_canvas_controller_action(context, action, cx)?,
        }
        Ok(())
    }
}

fn context_panel(key: &str) -> Option<ContextPanel> {
    match key { "agentCanvas" => Some(ContextPanel::AgentCanvas), "explorer" => Some(ContextPanel::Explorer), "search" => Some(ContextPanel::Search), "gitDiff" => Some(ContextPanel::SourceControl), "pullRequests" => Some(ContextPanel::PullRequest), _ => None }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn agent_canvas_action_context_rejects_navigation_and_revised_content() {
        let context = CanvasActionContext { workspace_id:"w".into(),canvas_id:"a".into(),revision:1,source_control_path:None };
        assert!(context.matches(Some("w"), &[json!({"id":"a","revision":1})]));
        assert!(!context.matches(Some("other"), &[json!({"id":"a","revision":1})]));
        assert!(!context.matches(Some("w"), &[json!({"id":"a","revision":2})]));
        assert!(!context.matches(Some("w"), &[]));
        assert!(confirmation_kind("discard").is_some());
        assert!(confirmation_kind("rerunValidation").is_some());
        assert!(confirmation_kind("openFile").is_none());
        assert_eq!(context_panel("gitDiff"), Some(ContextPanel::SourceControl));
        assert_eq!(context_panel("browser"), None);
    }
}
