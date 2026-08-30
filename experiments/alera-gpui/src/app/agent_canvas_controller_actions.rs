use gpui::Context;
use serde_json::Value;
use super::{AleraApp, agent_canvas_ui_actions::CanvasActionContext};
use crate::workspace_git::GitAction;

impl AleraApp {
    pub(super) fn perform_canvas_controller_action(&mut self, context: &CanvasActionContext, action: &Value, cx: &mut Context<Self>) -> Result<(), String> {
        let Some(scope) = self.selected_source_control_scope() else { return Err("This Agent Canvas action is not connected to an Alera controller.".into()); };
        if context.source_control_path.as_deref() != Some(scope.path.as_str()) { return Err("The source control root changed before this action completed.".into()); }
        let path = match action["relativePath"].as_str() {
            Some(path) => Some(scope.to_source_relative_path(path).ok_or_else(|| "The action path is outside the active source control root.".to_owned())?),
            None => None,
        };
        let operation = match action["kind"].as_str().unwrap_or_default() {
            "stage" => path.map(GitAction::StagePath).unwrap_or(GitAction::StageAll),
            "unstage" => path.map(GitAction::UnstagePath).unwrap_or(GitAction::UnstageAll),
            "discard" => path.map(GitAction::DiscardPath).unwrap_or(GitAction::DiscardAll),
            "commit" => {
                let message = action["message"].as_str().filter(|message| !message.trim().is_empty()).ok_or_else(|| "A commit message is required.".to_owned())?;
                GitAction::Commit(message.to_owned())
            }
            "pull" => GitAction::Pull,
            "push" => GitAction::Push,
            "terminateTerminal" => {
                let id = action["terminalSessionId"].as_str().ok_or_else(|| "The terminal session id is required.".to_owned())?;
                let tab = self.snapshot.tabs.iter().find(|tab| tab.kind == "terminal" && super::terminal_surface::terminal_session_id(tab) == id).map(|tab| tab.id.clone())
                    .ok_or_else(|| "The Agent Canvas terminal is no longer open.".to_owned())?;
                self.request_close_tab(tab, cx); return Ok(());
            }
            _ => return Err("This Agent Canvas action has no registered controller.".into()),
        };
        if self.git_busy { return Err("Source control is busy. Wait for the current action to finish.".into()); }
        self.run_git_action(operation, cx);
        Ok(())
    }
}
