use base64::prelude::{Engine as _, BASE64_STANDARD};
use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, ClipboardItem, Context, InteractiveElement as _,
    IntoElement, ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _,
};
use serde_json::json;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::AleraApp;
use crate::{
    design_system::{self, ButtonKind},
    icons::AleraIcon,
    model::WorkspaceTab,
    theme,
};

/// A command that must run in front of the user in a real interactive shell.
///
/// Keeping this value independent of a view lets updater and skill settings
/// share the same PTY dialog without teaching either surface about runtime
/// session ownership.
#[derive(Clone, Debug)]
pub(super) struct CommandTerminalRequest {
    pub title: String,
    pub command: String,
    pub description: Option<String>,
    pub working_directory: Option<String>,
}

/// Ephemeral command-session state. The synthetic tab is never persisted; it
/// only gives the existing terminal renderer a stable identity and lets the
/// runtime host own the PTY lifecycle.
pub(super) struct CommandTerminalState {
    pub request: CommandTerminalRequest,
    pub session_id: String,
    pub working_directory: String,
    pub startup_scheduled: bool,
    pub follow_up_agent_hooks: bool,
    pub follow_up_update_restart: bool,
}

impl CommandTerminalState {
    pub fn tab(&self) -> WorkspaceTab {
        WorkspaceTab {
            id: self.session_id.clone(),
            workspace_id: command_terminal_workspace_id().to_owned(),
            title: self.request.title.clone(),
            kind: "terminal".to_owned(),
            payload: json!({"terminalSessionId": self.session_id}),
        }
    }
}

pub(super) fn command_terminal_workspace_id() -> &'static str {
    "__alera_command_terminal__"
}

impl AleraApp {
    pub(super) fn open_command_terminal(
        &mut self,
        request: CommandTerminalRequest,
        cx: &mut Context<Self>,
    ) {
        self.open_command_terminal_with_follow_up(request, false, false, cx);
    }

    pub(super) fn open_command_terminal_with_follow_up(
        &mut self,
        request: CommandTerminalRequest,
        follow_up_agent_hooks: bool,
        follow_up_update_restart: bool,
        cx: &mut Context<Self>,
    ) {
        if self.command_terminal.is_some() || request.command.trim().is_empty() {
            return;
        }
        let working_directory = request
            .working_directory
            .clone()
            .filter(|path| !path.trim().is_empty())
            .or_else(|| {
                self.selected_workspace_id
                    .as_deref()
                    .and_then(|id| self.snapshot.workspace(id))
                    .map(|workspace| workspace.path.clone())
            })
            .or_else(|| std::env::var("HOME").ok().filter(|path| !path.is_empty()))
            .or_else(|| std::env::var("USERPROFILE").ok().filter(|path| !path.is_empty()))
            .or_else(|| std::env::current_dir().ok().map(|path| path.display().to_string()))
            .unwrap_or_else(|| ".".to_owned());
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let session_id = format!("command-terminal-{nonce}");
        self.command_terminal = Some(CommandTerminalState {
            request,
            session_id,
            working_directory,
            startup_scheduled: false,
            follow_up_agent_hooks,
            follow_up_update_restart,
        });
        cx.notify();
    }

    pub(super) fn close_command_terminal(&mut self, cx: &mut Context<Self>) {
        let Some(state) = self.command_terminal.take() else {
            return;
        };
        let session_id = state.session_id;
        let follow_up_agent_hooks = state.follow_up_agent_hooks;
        let follow_up_update_restart = state.follow_up_update_restart;
        self.terminal_sessions.remove(&session_id);
        self.terminal_frame_views.remove(&session_id);
        self.terminal_output_dirty_sessions.remove(&session_id);
        self.terminal_surface_bounds.remove(&session_id);
        self.terminal_resize_pending.remove(&session_id);
        self.terminal_resize_generation.remove(&session_id);
        self.terminal_scrollbar_last_activity.remove(&session_id);
        if self.terminal_scrollbar_drag.as_deref() == Some(session_id.as_str()) {
            self.terminal_scrollbar_drag = None;
        }
        if self
            .terminal_hovered_link
            .as_ref()
            .is_some_and(|(active, _)| active == &session_id)
        {
            self.terminal_hovered_link = None;
        }
        let bridge = self.bridge.clone();
        cx.spawn(async move |_, _| {
            let _ = bridge.request("terminate", json!({"sessionId": session_id})).await;
        })
        .detach();
        if follow_up_agent_hooks {
            let hooks = serde_json::to_value(&self.settings_state.agent_status_hooks)
                .unwrap_or_else(|_| json!({}));
            self.update_runtime_setting("agentStatusHooks", hooks, cx);
        }
        if follow_up_update_restart {
            self.require_update_restart(cx);
        }
        cx.notify();
    }

    pub(super) fn copy_command_terminal_command(&mut self, cx: &mut Context<Self>) {
        let Some(state) = self.command_terminal.as_ref() else {
            return;
        };
        cx.write_to_clipboard(ClipboardItem::new_string(state.request.command.clone()));
        self.local_message = Some("Command Copied".into());
        cx.notify();
    }

    pub(super) fn schedule_command_terminal_startup(
        &mut self,
        session_id: String,
        command: String,
        cx: &mut Context<Self>,
    ) {
        let Some(state) = self.command_terminal.as_mut() else {
            return;
        };
        if state.session_id != session_id || state.startup_scheduled {
            return;
        }
        state.startup_scheduled = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(Duration::from_millis(120))
                .await;
            let bytes = format!("{}\r", command.replace("\r\n", "\n").replace('\r', "\n"));
            let _ = bridge
                .send_ordered(
                    "write",
                    json!({
                        "sessionId": session_id,
                        "dataBase64": BASE64_STANDARD.encode(bytes.as_bytes()),
                    }),
                );
            let _ = this.update(cx, |_, cx| cx.notify());
        })
        .detach();
    }

    pub(super) fn render_command_terminal_dialog(
        &self,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let Some(state) = self.command_terminal.as_ref() else {
            return div().into_any_element();
        };
        let tab = state.tab();
        let command = state.request.command.clone();
        let title = state.request.title.clone();
        let description = state.request.description.clone();
        let session_id = state.session_id.clone();
        let terminal = self.render_terminal_surface_for(Some(&tab), true, cx);
        div()
            .id("command-terminal-dialog-overlay")
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                design_system::dialog_shell("command-terminal-dialog", title.clone(), 720.0)
                    .h(gpui::px(560.0))
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_size(gpui::px(17.0))
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child(title),
                            )
                            .child(
                                design_system::icon_button(
                                    "close-command-terminal",
                                    "Close",
                                    AleraIcon::Close,
                                    true,
                                    30.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.close_command_terminal(cx);
                                    cx.stop_propagation();
                                })),
                            ),
                    )
                    .when_some(description, |dialog, description| {
                        dialog.child(
                            div()
                                .mt_1()
                                .text_size(gpui::px(12.0))
                                .text_color(theme::text_muted())
                                .child(description),
                        )
                    })
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .mt_3()
                            .p(gpui::px(10.0))
                            .gap(gpui::px(8.0))
                            .rounded_md()
                            .border_1()
                            .border_color(theme::border_subtle())
                            .bg(theme::surface_selected())
                            .child(
                                div()
                                    .flex_1()
                                    .overflow_x_scroll()
                                    .whitespace_nowrap()
                                    .font_family("JetBrains Mono")
                                    .text_size(gpui::px(12.0))
                                    .child(command),
                            )
                            .child(
                                design_system::icon_button(
                                    "copy-command-terminal-command",
                                    "Copy Command",
                                    AleraIcon::Copy,
                                    true,
                                    28.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.copy_command_terminal_command(cx);
                                    cx.stop_propagation();
                                })),
                            ),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!(
                                "command-terminal-surface-{session_id}"
                            )))
                            .relative()
                            .flex_1()
                            .min_h(gpui::px(180.0))
                            .mt_3()
                            .overflow_hidden()
                            .rounded_lg()
                            .border_1()
                            .border_color(theme::border_subtle())
                            .child(terminal),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .mt_3()
                            .child(
                                design_system::button(
                                    "close-command-terminal-footer",
                                    "Close",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.close_command_terminal(cx);
                                    cx.stop_propagation();
                                })),
                            ),
                    ),
            )
            .into_any_element()
    }
}
