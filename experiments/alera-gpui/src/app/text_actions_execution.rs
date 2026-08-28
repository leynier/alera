use std::time::{Duration, SystemTime, UNIX_EPOCH};

use gpui::{
    Action, App, Context, Entity, SharedString, Window,
};
use gpui_component::input::{
    Copy, Cut, EditorState, GoToDefinition, Paste, SelectAll, ToggleCodeActions,
};
use gpui_component::native_menu::NativeMenu;
use serde::Deserialize;
use serde_json::json;

use super::state_types::TextActionPending;
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
    let editable = capabilities.is_editable();
    let mut menu = if capabilities.is_code_editor() {
        menu.menu_with_disabled(
            "Go To Definition",
            !(capabilities.has_definition() && !capabilities.is_disabled()),
            Box::new(GoToDefinition),
        )
        .menu_with_disabled(
            "Show Code Actions",
            !(capabilities.has_code_actions() && editable),
            Box::new(ToggleCodeActions),
        )
        .separator()
    } else {
        menu
    };
    menu = menu
        .menu_with_disabled("Cut", !(editable && capabilities.is_copyable()), Box::new(Cut))
        .menu_with_disabled("Copy", !capabilities.is_copyable(), Box::new(Copy))
        .menu_with_disabled(
            "Paste",
            !(editable && cx.read_from_clipboard().is_some()),
            Box::new(Paste),
        )
        .separator()
        .menu("Select All", Box::new(SelectAll));

    let enabled_actions = actions
        .into_iter()
        .filter(|action| action.enabled)
        .collect::<Vec<_>>();
    if ai_enabled && editable && capabilities.has_selection() && !enabled_actions.is_empty() {
        let submenu = enabled_actions.into_iter().fold(NativeMenu::new(), |menu, action| {
            menu.menu(
                action.name,
                Box::new(RunTextAction { id: action.id }),
            )
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
        if self.text_action_operation_id.is_some() {
            return;
        }
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
            path,
            captured_text,
            selected_range,
        });
        self.local_message = Some("Running Text Action".into());
        let bridge = self.bridge.clone();
        let timeout = self.settings_state.ai_text_timeout_seconds.max(10) as u64 + 10;
        let action_id = action.id.clone();
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
                        let editor = this.editor_input_for_path(&pending.path);
                        let current_text = editor.read(cx).value().to_string();
                        let current_range = editor.read(cx).selected_range();
                        if current_text != pending.captured_text
                            || current_range != pending.selected_range
                        {
                            this.local_message = Some(
                                "Generated Replacement Was Not Applied Because The Field Changed"
                                    .into(),
                            );
                        } else if replacement.trim().is_empty() {
                            this.local_message = Some("Text Action Returned No Replacement".into());
                        } else {
                            let range = pending.selected_range.clone();
                            editor.update(cx, |input, cx| {
                                input.set_selected_range(range, cx);
                                input.replace(replacement, window, cx);
                            });
                            this.local_message =
                                Some(format!("Text Action Applied With {agent}").into());
                        }
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
