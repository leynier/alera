use std::collections::BTreeSet;
use std::path::Path;

use base64::prelude::{Engine as _, BASE64_STANDARD};
use gpui::{
    div, prelude::FluentBuilder as _, px, AppContext as _, Context, CursorStyle, Entity,
    ExternalPaths, InteractiveElement as _, IntoElement, KeyDownEvent, MouseButton,
    ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::{InputEvent, Paste, Textarea, TextareaState};
use gpui_component::scroll::ScrollableElement as _;
use serde_json::json;

use super::state_types::{
    ExplorerDragData, TerminalComposerAttachment, TerminalComposerAttachmentKind, TextActionTarget,
};
use super::text_actions_execution::textarea_context_menu;
use super::workspace_prompt_actions::save_prompt_clipboard_image;
use super::{AleraApp, TextActionSetting};
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn ensure_terminal_composer_inputs(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let session_ids = self
            .snapshot
            .tabs
            .iter()
            .filter(|tab| tab.kind == "terminal")
            .map(super::terminal_surface::terminal_session_id)
            .map(str::to_owned)
            .collect::<BTreeSet<_>>();
        self.terminal_composer_inputs
            .retain(|session_id, _| session_ids.contains(session_id));
        self.terminal_composer_subscriptions
            .retain(|session_id, _| session_ids.contains(session_id));
        self.terminal_composer_visible
            .retain(|session_id| session_ids.contains(session_id));
        self.terminal_composer_attachments
            .retain(|session_id, _| session_ids.contains(session_id));
        if self
            .terminal_composer_menu_open
            .as_ref()
            .is_some_and(|session_id| !session_ids.contains(session_id))
        {
            self.terminal_composer_menu_open = None;
        }
        for session_id in session_ids {
            if self.terminal_composer_inputs.contains_key(&session_id) {
                continue;
            }
            let input = cx.new(|cx| {
                TextareaState::new(window, cx)
                    .placeholder("Write A Prompt For This Terminal")
                    .auto_grow(2, 6)
                    .soft_wrap(true)
            });
            let subscription =
                cx.subscribe_in(&input, window, |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                });
            if self.settings_state.terminal_show_composer_by_default {
                self.terminal_composer_visible.insert(session_id.clone());
            }
            self.terminal_composer_subscriptions
                .insert(session_id.clone(), subscription);
            self.terminal_composer_inputs.insert(session_id, input);
        }
    }

    pub(super) fn on_toggle_terminal_composer(
        &mut self,
        _: &super::keyboard_actions::ToggleTerminalComposer,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = self.selected_terminal_session_id() else {
            cx.propagate();
            return;
        };
        self.toggle_terminal_composer(session_id, window, cx);
    }

    pub(super) fn toggle_terminal_composer(
        &mut self,
        session_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.terminal_composer_inputs.contains_key(&session_id) {
            return;
        }
        if !self.terminal_composer_visible.remove(&session_id) {
            self.terminal_composer_visible.insert(session_id.clone());
            if let Some(input) = self.terminal_composer_inputs.get(&session_id) {
                input.update(cx, |input, cx| input.focus(window, cx));
            }
        } else {
            window.focus(&self.terminal_focus, cx);
        }
        self.terminal_composer_menu_open = None;
        cx.stop_propagation();
        cx.notify();
    }

    fn close_terminal_composer(
        &mut self,
        session_id: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.terminal_composer_visible.remove(session_id) {
            self.terminal_composer_menu_open = None;
            window.focus(&self.terminal_focus, cx);
            cx.notify();
        }
    }

    fn on_terminal_composer_paste(
        &mut self,
        session_id: &str,
        _: &Paste,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(clipboard) = cx.read_from_clipboard() else {
            cx.propagate();
            return;
        };
        if clipboard.text().is_some() {
            cx.propagate();
            return;
        }
        let Some(image) = clipboard.entries().iter().find_map(|entry| match entry {
            gpui::ClipboardEntry::Image(image) => Some(image),
            gpui::ClipboardEntry::String(_) | gpui::ClipboardEntry::ExternalPaths(_) => None,
        }) else {
            cx.propagate();
            return;
        };
        if !self.terminal_composer_inputs.contains_key(session_id) {
            cx.propagate();
            return;
        }
        match save_prompt_clipboard_image(image) {
            Ok(path) => self.add_terminal_composer_path(
                session_id,
                path,
                TerminalComposerAttachmentKind::Image,
                cx,
            ),
            Err(error) => self.local_message = Some(error.into()),
        }
        cx.stop_propagation();
        cx.notify();
    }

    fn add_terminal_composer_path(
        &mut self,
        session_id: &str,
        path: String,
        kind: TerminalComposerAttachmentKind,
        cx: &mut Context<Self>,
    ) {
        let path = path.trim().to_owned();
        if path.is_empty() {
            return;
        }
        let display_name = Path::new(&path)
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.is_empty())
            .unwrap_or(match kind {
                TerminalComposerAttachmentKind::Image => "Pasted Image",
                TerminalComposerAttachmentKind::File => "Pasted File",
            })
            .to_owned();
        let id = format!("attachment-{}", self.terminal_composer_attachment_counter);
        self.terminal_composer_attachment_counter =
            self.terminal_composer_attachment_counter.wrapping_add(1);
        self.terminal_composer_attachments
            .entry(session_id.to_owned())
            .or_default()
            .push(TerminalComposerAttachment {
                id,
                kind,
                path,
                display_name,
            });
        cx.notify();
    }

    fn add_terminal_composer_paths(
        &mut self,
        session_id: &str,
        paths: impl IntoIterator<Item = String>,
        cx: &mut Context<Self>,
    ) {
        for path in paths {
            let kind = terminal_composer_attachment_kind(&path);
            self.add_terminal_composer_path(session_id, path, kind, cx);
        }
    }

    fn remove_terminal_composer_attachment(
        &mut self,
        session_id: &str,
        attachment_id: &str,
        cx: &mut Context<Self>,
    ) {
        if let Some(attachments) = self.terminal_composer_attachments.get_mut(session_id) {
            attachments.retain(|attachment| attachment.id != attachment_id);
            if attachments.is_empty() {
                self.terminal_composer_attachments.remove(session_id);
            }
            cx.notify();
        }
    }

    fn submit_terminal_composer(
        &mut self,
        session_id: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(input) = self.terminal_composer_inputs.get(session_id).cloned() else {
            return;
        };
        let prompt = input.read(cx).value().to_string();
        let attachments = self
            .terminal_composer_attachments
            .get(session_id)
            .cloned()
            .unwrap_or_default();
        if prompt.trim().is_empty() && attachments.is_empty() {
            return;
        }
        let submission = build_terminal_composer_submission(&prompt, &attachments);
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        session.emulator.clear_restore_prompt_cleanup();
        session.emulator.clear_selection();
        let bytes = session.emulator.encode_paste(&submission);
        let supports_deferred = self
            .settings_state
            .runtime_capabilities
            .iter()
            .any(|capability| capability == "terminalDeferredInputV1");
        if supports_deferred {
            self.write_terminal_bytes_with_deferred_enter_for(session_id, bytes);
        } else {
            self.write_terminal_bytes_for(session_id, bytes);
            let bridge = self.bridge.clone();
            let session_id = session_id.to_owned();
            cx.spawn(async move |_, cx| {
                cx.background_executor()
                    .timer(std::time::Duration::from_millis(500))
                    .await;
                let _ = bridge.send_ordered(
                    "write",
                    json!({
                        "sessionId": session_id,
                        "dataBase64": BASE64_STANDARD.encode(b"\r"),
                    }),
                );
            })
            .detach();
        }
        input.update(cx, |input, cx| input.set_value("", window, cx));
        self.terminal_composer_attachments.remove(session_id);
        input.update(cx, |input, cx| input.focus(window, cx));
        self.reset_terminal_cursor_blink();
        self.terminal_composer_menu_open = None;
        cx.notify();
    }

    pub(super) fn render_terminal_composer(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> gpui::AnyElement {
        let Some(input) = self.terminal_composer_inputs.get(session_id).cloned() else {
            return div().into_any_element();
        };
        let actions = self
            .settings_state
            .text_actions
            .iter()
            .filter(|action| action.enabled)
            .cloned()
            .collect::<Vec<_>>();
        let has_selection = !input.read(cx).selected_range().is_empty();
        let ai_assist_enabled = self.settings_state.ai_assist_enabled;
        let actions_enabled = ai_assist_enabled && has_selection && !actions.is_empty();
        let attachments = self
            .terminal_composer_attachments
            .get(session_id)
            .cloned()
            .unwrap_or_default();
        let has_attachments = !attachments.is_empty();
        let session_for_key = session_id.to_owned();
        let session_for_send = session_id.to_owned();
        let session_for_menu = session_id.to_owned();
        let session_for_text_menu = session_id.to_owned();
        let session_for_external_drop = session_id.to_owned();
        let session_for_explorer_drop = session_id.to_owned();
        let input_for_context_menu = input.clone();
        let menu_open = self.terminal_composer_menu_open.as_deref() == Some(session_id);
        let mut composer = div()
            .id("terminal-composer")
            .relative()
            .p_3()
            .rounded_xl()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_selected())
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .capture_action({
                let session_id = session_id.to_owned();
                cx.listener(move |this, action: &Paste, window, cx| {
                    this.on_terminal_composer_paste(&session_id, action, window, cx);
                })
            })
            .on_drop(cx.listener(move |this, paths: &ExternalPaths, _, cx| {
                this.add_terminal_composer_paths(
                    &session_for_external_drop,
                    paths
                        .paths()
                        .iter()
                        .map(|path| path.to_string_lossy().into_owned()),
                    cx,
                );
                cx.stop_propagation();
            }))
            .on_drop(cx.listener(move |this, drag: &ExplorerDragData, _, cx| {
                let path = this.absolute_explorer_path(&drag.relative_path);
                this.add_terminal_composer_paths(&session_for_explorer_drop, [path], cx);
                cx.stop_propagation();
            }))
            .capture_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                let key = event.keystroke.key.as_str();
                if key.eq_ignore_ascii_case("escape") {
                    this.close_terminal_composer(&session_for_key, window, cx);
                    cx.stop_propagation();
                } else if key.eq_ignore_ascii_case("enter") && !event.keystroke.modifiers.shift {
                    this.submit_terminal_composer(&session_for_key, window, cx);
                    cx.stop_propagation();
                }
            }))
            .when(has_attachments, |composer| {
                composer.child(self.render_terminal_composer_attachments(session_id, cx))
            })
            .child(
                Textarea::new(&input)
                    .aria_label("Terminal Prompt Composer")
                    .bordered(false)
                    .h(px(92.0))
                    .context_menu({
                        let actions = actions.clone();
                        move |menu, _window, cx| {
                            textarea_context_menu(
                                menu,
                                input_for_context_menu.clone(),
                                actions.clone(),
                                ai_assist_enabled,
                                cx,
                            )
                        }
                    }),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .mt_2()
                    .gap_2()
                    .child(
                        design_system::button(
                            "terminal-composer-text-actions",
                            "Text Actions",
                            ButtonKind::Text,
                            !actions_enabled,
                        )
                        .cursor(if actions_enabled {
                            CursorStyle::PointingHand
                        } else {
                            CursorStyle::Arrow
                        })
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if actions_enabled {
                                if this.terminal_composer_menu_open.as_deref()
                                    == Some(session_for_text_menu.as_str())
                                {
                                    this.terminal_composer_menu_open = None;
                                } else {
                                    this.terminal_composer_menu_open =
                                        Some(session_for_text_menu.clone());
                                }
                                cx.notify();
                            }
                        }))
                        .child(icon(AleraIcon::Composer, 14.0, theme::text_muted()))
                        .child("Text Actions")
                        .child(icon(
                            AleraIcon::ChevronDown,
                            14.0,
                            theme::text_faint(),
                        )),
                    )
                    .child(div().flex_1())
                    .child(
                        design_system::icon_button(
                            "terminal-composer-send",
                            "Send Prompt",
                            AleraIcon::Send,
                            !prompt_can_send(&input, has_attachments, cx),
                            32.0,
                            Some(theme::accent()),
                            None,
                        )
                        .on_click(cx.listener(
                            move |this, _, window, cx| {
                                this.submit_terminal_composer(&session_for_send, window, cx);
                            },
                        )),
                    ),
            );
        if menu_open {
            composer = composer.child(self.render_terminal_composer_actions(
                &session_for_menu,
                actions,
                actions_enabled,
                cx,
            ));
        }
        composer.into_any_element()
    }

    fn render_terminal_composer_attachments(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> gpui::AnyElement {
        let attachments = self
            .terminal_composer_attachments
            .get(session_id)
            .cloned()
            .unwrap_or_default();
        let session_id = session_id.to_owned();
        div()
            .id("terminal-composer-attachments")
            .flex()
            .items_center()
            .gap_1()
            .h(px(34.0))
            .mb_2()
            .overflow_x_scrollbar()
            .children(attachments.into_iter().map(|attachment| {
                let open_path = attachment.path.clone();
                let remove_id = attachment.id.clone();
                let session_for_remove = session_id.clone();
                let image = attachment.kind == TerminalComposerAttachmentKind::Image;
                div()
                    .id(gpui::SharedString::from(format!(
                        "terminal-composer-attachment-{}",
                        attachment.id
                    )))
                    .flex()
                    .items_center()
                    .gap_1()
                    .h(px(30.0))
                    .px_1()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .cursor(CursorStyle::PointingHand)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.open_terminal_composer_attachment(&open_path, cx);
                    }))
                    .child(icon(
                        if image {
                            AleraIcon::ImageOff
                        } else {
                            AleraIcon::File
                        },
                        15.0,
                        theme::text_muted(),
                    ))
                    .child(
                        div()
                            .max_w(px(180.0))
                            .text_ellipsis()
                            .child(attachment.display_name),
                    )
                    .child(
                        design_system::icon_button(
                            gpui::SharedString::from(format!(
                                "terminal-composer-remove-{}",
                                attachment.id
                            )),
                            if image { "Remove Image" } else { "Remove File" },
                            AleraIcon::Close,
                            true,
                            22.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.remove_terminal_composer_attachment(
                                &session_for_remove,
                                &remove_id,
                                cx,
                            );
                            cx.stop_propagation();
                        })),
                    )
            }))
            .into_any_element()
    }

    fn open_terminal_composer_attachment(&mut self, path: &str, cx: &mut Context<Self>) {
        let mut command = if cfg!(target_os = "macos") {
            alera_core::child_process::windowless_command("open")
        } else if cfg!(target_os = "windows") {
            alera_core::child_process::windowless_command("explorer.exe")
        } else {
            alera_core::child_process::windowless_command("xdg-open")
        };
        let _ = command.arg(path).spawn();
        self.local_message = Some("Opened Composer Attachment".into());
        cx.notify();
    }

    fn render_terminal_composer_actions(
        &self,
        session_id: &str,
        actions: Vec<TextActionSetting>,
        enabled: bool,
        cx: &mut Context<Self>,
    ) -> gpui::AnyElement {
        let session_id = session_id.to_owned();
        div()
            .id("terminal-composer-actions")
            .absolute()
            .left(px(12.0))
            .bottom(px(48.0))
            .min_w(px(220.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_1()
            .role(Role::Menu)
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .child(
                div()
                    .px_2()
                    .py_1()
                    .text_xs()
                    .text_color(theme::text_faint())
                    .child("Select Text Action"),
            )
            .children(actions.into_iter().map(|action| {
                let id = action.id.clone();
                let session_id = session_id.clone();
                div()
                    .id(gpui::SharedString::from(format!(
                        "terminal-composer-action-{}",
                        action.id
                    )))
                    .role(Role::MenuItem)
                    .cursor(if enabled {
                        CursorStyle::PointingHand
                    } else {
                        CursorStyle::Arrow
                    })
                    .px_2()
                    .py_2()
                    .rounded_md()
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if !enabled {
                            return;
                        }
                        let Some(input) = this.terminal_composer_inputs.get(&session_id).cloned()
                        else {
                            return;
                        };
                        let captured_text = input.read(cx).value().to_string();
                        let selected_range = input.read(cx).selected_range();
                        let Some(workspace_path) = this.selected_source_control_path() else {
                            return;
                        };
                        this.terminal_composer_menu_open = None;
                        this.start_text_action(
                            id.clone(),
                            TextActionTarget::TerminalComposer {
                                session_id: session_id.clone(),
                            },
                            captured_text,
                            selected_range,
                            workspace_path,
                            window,
                            cx,
                        );
                    }))
                    .child(action.name)
            }))
            .into_any_element()
    }
}

fn prompt_can_send(
    input: &Entity<TextareaState>,
    has_attachments: bool,
    cx: &Context<AleraApp>,
) -> bool {
    has_attachments || !input.read(cx).value().trim().is_empty()
}

fn terminal_composer_attachment_kind(path: &str) -> TerminalComposerAttachmentKind {
    match Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.to_ascii_lowercase())
        .as_deref()
    {
        Some("gif" | "jpeg" | "jpg" | "png" | "webp") => TerminalComposerAttachmentKind::Image,
        _ => TerminalComposerAttachmentKind::File,
    }
}

fn build_terminal_composer_submission(
    prompt: &str,
    attachments: &[TerminalComposerAttachment],
) -> String {
    let mut images = Vec::new();
    let mut files = Vec::new();
    for attachment in attachments {
        if attachment.path.trim().is_empty() {
            continue;
        }
        match attachment.kind {
            TerminalComposerAttachmentKind::Image => images.push(attachment.path.clone()),
            TerminalComposerAttachmentKind::File => files.push(attachment.path.clone()),
        }
    }
    let mut sections = Vec::new();
    if !images.is_empty() {
        sections.push("Attached Images:".to_owned());
        sections.extend(images);
    }
    if !files.is_empty() {
        sections.push("Attached Files:".to_owned());
        sections.extend(files);
    }
    if sections.is_empty() {
        return prompt.to_owned();
    }
    let attachments = sections.join("\n");
    if prompt.trim().is_empty() {
        attachments
    } else {
        format!("{prompt}\n\n{attachments}")
    }
}
