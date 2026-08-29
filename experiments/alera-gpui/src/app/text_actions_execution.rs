use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gpui::{Action, App, Context, Entity, SharedString, Window};
use gpui_component::input::{
    Copy, Cut, EditorState, GoToDefinition, Paste, SelectAll, TextareaState, ToggleCodeActions,
};
use gpui_component::native_menu::NativeMenu;
use serde::Deserialize;
use serde_json::json;

use super::state_types::{TextActionPending, TextActionTarget};
use super::{AleraApp, TextActionSetting};

#[derive(Action, Clone, PartialEq, Eq, Deserialize)]
#[action(namespace = alera, no_json)]
pub(super) struct RunTextAction {
    pub(super) id: String,
}

/// Add Alera's text actions to the regular editor context menu while keeping
/// the native cut/copy/paste/select-all entries intact.
pub(super) fn editor_context_menu(
    menu: NativeMenu,
    editor: Entity<EditorState>,
    actions: Vec<TextActionSetting>,
    ai_enabled: bool,
    _window: &mut Window,
    cx: &mut App,
) -> NativeMenu {
    let capabilities = editor.read(cx).context_menu_capabilities();
    build_context_menu(
        menu,
        capabilities.is_code_editor(),
        capabilities.is_disabled(),
        capabilities.is_editable(),
        capabilities.has_definition(),
        capabilities.has_code_actions(),
        capabilities.is_copyable(),
        cx.read_from_clipboard().is_some(),
        capabilities.has_selection(),
        actions,
        ai_enabled,
    )
}

pub(super) fn textarea_context_menu(
    menu: NativeMenu,
    textarea: Entity<TextareaState>,
    actions: Vec<TextActionSetting>,
    ai_enabled: bool,
    cx: &mut App,
) -> NativeMenu {
    let capabilities = textarea.read(cx).context_menu_capabilities();
    build_context_menu(
        menu,
        capabilities.is_code_editor(),
        capabilities.is_disabled(),
        capabilities.is_editable(),
        capabilities.has_definition(),
        capabilities.has_code_actions(),
        capabilities.is_copyable(),
        cx.read_from_clipboard().is_some(),
        capabilities.has_selection(),
        actions,
        ai_enabled,
    )
}

#[allow(clippy::too_many_arguments)]
fn build_context_menu(
    mut menu: NativeMenu,
    code_editor: bool,
    disabled: bool,
    editable: bool,
    has_definition: bool,
    has_code_actions: bool,
    copyable: bool,
    clipboard_available: bool,
    has_selection: bool,
    actions: Vec<TextActionSetting>,
    ai_enabled: bool,
) -> NativeMenu {
    if code_editor {
        menu = menu
            .menu_with_disabled(
                "Go To Definition",
                !has_definition || disabled,
                Box::new(GoToDefinition),
            )
            .menu_with_disabled(
                "Show Code Actions",
                !(has_code_actions && editable),
                Box::new(ToggleCodeActions),
            )
            .separator();
    }
    menu = menu
        .menu_with_disabled("Cut", !(editable && copyable), Box::new(Cut))
        .menu_with_disabled("Copy", !copyable, Box::new(Copy))
        .menu_with_disabled("Paste", !(editable && clipboard_available), Box::new(Paste))
        .separator()
        .menu("Select All", Box::new(SelectAll));

    let enabled_actions = actions
        .into_iter()
        .filter(|action| action.enabled)
        .collect::<Vec<_>>();
    if ai_enabled && editable && has_selection && !enabled_actions.is_empty() {
        let submenu = enabled_actions
            .into_iter()
            .fold(NativeMenu::new(), |menu, action| {
                menu.menu(action.name, Box::new(RunTextAction { id: action.id }))
            });
        menu.separator().submenu("Text Actions", submenu)
    } else {
        menu
    }
}

impl AleraApp {
    pub(super) fn on_run_text_action(
        &mut self,
        action: &RunTextAction,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(path) = self
            .selected_tab_id
            .as_deref()
            .and_then(|tab_id| self.snapshot.tabs.iter().find(|tab| tab.id == tab_id))
            .and_then(|tab| tab.payload.get("filePath"))
            .and_then(|path| path.as_str())
            .map(str::to_owned)
            .or_else(|| self.opened_file_path.clone())
        else {
            return;
        };
        let editor = self.editor_input_for_path(&path);
        let captured_text = editor.read(cx).value().to_string();
        let selected_range = editor.read(cx).selected_range();
        if selected_range.is_empty() || selected_range.end > captured_text.len() {
            return;
        }
        let selected_text = captured_text[selected_range.clone()].to_owned();
        if selected_text.is_empty() {
            return;
        }
        let Some(workspace_path) = self.selected_source_control_path() else {
            self.local_message = Some("Text Action Requires An Active Workspace".into());
            cx.notify();
            return;
        };
        self.start_text_action(
            action.id.clone(),
            TextActionTarget::Editor { path },
            captured_text,
            selected_range,
            workspace_path,
            window,
            cx,
        );
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn start_text_action(
        &mut self,
        action_id: String,
        target: TextActionTarget,
        captured_text: String,
        selected_range: std::ops::Range<usize>,
        workspace_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.text_action_operation_id.is_some()
            || selected_range.is_empty()
            || selected_range.end > captured_text.len()
        {
            return;
        }
        let selected_text = captured_text[selected_range.clone()].to_owned();
        if selected_text.is_empty() {
            return;
        }
        let operation_id = format!(
            "gpui-text-action-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
        );
        self.text_action_operation_id = Some(operation_id.clone());
        self.text_action_pending = Some(TextActionPending {
            target,
            captured_text,
            selected_range,
        });
        self.local_message = Some("Running Text Action".into());
        let bridge = self.bridge.clone();
        let timeout = self.settings_state.ai_assist_timeout_seconds.max(10) as u64 + 10;
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "aiText.textAction.generate",
                    json!({
                        "operationId": operation_id,
                        "workspacePath": workspace_path,
                        "actionId": action_id,
                        "selectedText": selected_text,
                    }),
                    Duration::from_secs(timeout),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, move |this, window, cx| {
                this.text_action_operation_id = None;
                let Some(pending) = this.text_action_pending.take() else {
                    return;
                };
                match result {
                    Ok(value) => {
                        let replacement = value
                            .get("text")
                            .and_then(|value| value.as_str())
                            .unwrap_or_default()
                            .to_owned();
                        let agent = value
                            .get("agentLabel")
                            .and_then(|value| value.as_str())
                            .unwrap_or("AI");
                        this.apply_text_action_result(pending, replacement, agent, window, cx);
                    }
                    Err(error) if error.contains("canceled") => {
                        this.local_message = Some("Text Action Canceled".into());
                    }
                    Err(error) => {
                        this.local_message = Some(SharedString::from(error));
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn apply_text_action_result(
        &mut self,
        pending: TextActionPending,
        replacement: String,
        agent: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let (current_text, current_range) = match &pending.target {
            TextActionTarget::Editor { path } => {
                let input = self.editor_input_for_path(path);
                (
                    input.read(cx).value().to_string(),
                    input.read(cx).selected_range(),
                )
            }
            TextActionTarget::TerminalComposer { session_id } => {
                let Some(input) = self.terminal_composer_inputs.get(session_id) else {
                    self.local_message = Some("Text Action Target Is Unavailable".into());
                    return;
                };
                (
                    input.read(cx).value().to_string(),
                    input.read(cx).selected_range(),
                )
            }
        };
        if current_text != pending.captured_text || current_range != pending.selected_range {
            self.local_message =
                Some("Generated Replacement Was Not Applied Because The Field Changed".into());
            return;
        }
        if replacement.trim().is_empty() {
            self.local_message = Some("Text Action Returned No Replacement".into());
            return;
        }
        let range = pending.selected_range.clone();
        match pending.target {
            TextActionTarget::Editor { path } => {
                let input = self.editor_input_for_path(&path);
                input.update(cx, |input, cx| {
                    input.set_selected_range(range, cx);
                    input.replace(replacement, window, cx);
                });
            }
            TextActionTarget::TerminalComposer { session_id } => {
                let Some(input) = self.terminal_composer_inputs.get(&session_id).cloned() else {
                    self.local_message = Some("Text Action Target Is Unavailable".into());
                    return;
                };
                input.update(cx, |input, cx| {
                    input.set_selected_range(range, cx);
                    input.replace(replacement, window, cx);
                });
            }
        }
        self.local_message = Some(format!("Text Action Applied With {agent}").into());
    }

    pub(super) fn cancel_text_action(&mut self, cx: &mut Context<Self>) {
        let Some(operation_id) = self.text_action_operation_id.clone() else {
            return;
        };
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request("aiText.cancel", json!({"operationId": operation_id}))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if result.is_ok() {
                    this.local_message = Some("Text Action Canceled".into());
                }
                cx.notify();
            });
        })
        .detach();
    }
}
