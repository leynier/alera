use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};
use std::path::Path;

use gpui::{
    div, img, prelude::FluentBuilder as _, px, rems, AnyElement, AppContext as _, ClipboardItem,
    Context, CursorStyle, InteractiveElement as _, IntoElement as _, MouseButton, MouseDownEvent,
    MouseMoveEvent, ParentElement as _, Role, ScrollWheelEvent, SharedString,
    StatefulInteractiveElement as _, StyleRefinement, Styled as _, StyledText, Window,
};
use gpui_component::input::Editor;
use gpui_component::text::{TextView, TextViewStyle};
use gpui_component::tooltip::Tooltip;
use gpui_component::ActiveTheme as _;
use serde_json::Value;

use super::markdown_preview_images::with_markdown_images;
use super::state_types::PreviewDragState;
use super::text_actions_execution::editor_context_menu;
use super::workspace_surface::PreviewAsset;
use super::AleraApp;
use crate::model::WorkspaceTab;
use crate::{
    file_icons::file_icon,
    icons::{icon, loading_indicator, AleraIcon},
    theme,
    workspace_service::EditorDocument,
};

impl AleraApp {
    pub(super) fn render_editor(&self, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        let Some(tab) = self
            .selected_tab_id
            .as_deref()
            .and_then(|id| self.snapshot.tabs.iter().find(|tab| tab.id == id))
        else {
            return self.render_active_editor(window, true, cx);
        };
        self.render_editor_for_tab(tab, true, window, cx)
    }

    pub(super) fn render_editor_for_tab(
        &self,
        tab: &WorkspaceTab,
        active: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if active && self.selected_tab_id.as_deref() == Some(tab.id.as_str()) {
            return self.render_active_editor(window, active, cx);
        }
        self.render_inactive_editor(tab, window, cx)
    }

    fn render_inactive_editor(
        &self,
        tab: &WorkspaceTab,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let path = tab
            .payload
            .get("filePath")
            .and_then(Value::as_str)
            .unwrap_or(tab.title.as_str())
            .to_owned();
        let dirty = self.editor_dirty_paths.contains(&path);
        let title_color = if dirty {
            theme::text()
        } else {
            theme::text_muted()
        };
        let tab_id = tab.id.clone();
        let header_tab_id = tab_id.clone();
        let source_available = self.editor_documents.contains_key(&path);
        let preview_available = self.editor_preview_assets.contains_key(&path);
        let is_markdown_viewer = tab.kind == "markdownViewer";
        let is_merman_viewer = tab.kind == "editor"
            && tab.payload.get("fileRole").and_then(Value::as_str) == Some("mermanPreview");
        let source_editor = !is_markdown_viewer && !is_merman_viewer && source_available;
        let toolbar = div()
            .flex()
            .items_center()
            .gap_2()
            .when(source_editor, |toolbar| {
                let diff_tab_id = tab_id.clone();
                let save_tab_id = tab_id.clone();
                let discard_tab_id = tab_id.clone();
                let preview_tab_id = tab_id.clone();
                toolbar
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("editor-view-diff-{tab_id}")),
                            "View Diff",
                            AleraIcon::Diff,
                            true,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("View Diff")).into())
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _, _, cx| {
                                cx.stop_propagation();
                                this.activate_workspace_tab(diff_tab_id.clone(), cx);
                                this.open_editor_diff(cx);
                            }),
                        ),
                    )
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("save-editor-{tab_id}")),
                            "Save File",
                            AleraIcon::Save,
                            dirty && !self.editor_busy,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Save File")).into())
                        .when(dirty && !self.editor_busy, |button| {
                            button.on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.activate_workspace_tab(save_tab_id.clone(), cx);
                                    if this.editor_dirty && !this.editor_busy {
                                        this.save_editor(false, cx);
                                    }
                                }),
                            )
                        }),
                    )
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("discard-editor-{tab_id}")),
                            "Discard Changes",
                            AleraIcon::Restore,
                            dirty && !self.editor_busy,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Discard Changes")).into())
                        .when(dirty && !self.editor_busy, |button| {
                            button.on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _, window, cx| {
                                    cx.stop_propagation();
                                    this.activate_workspace_tab(discard_tab_id.clone(), cx);
                                    if this.editor_dirty && !this.editor_busy {
                                        this.discard_editor_changes(window, cx);
                                    }
                                }),
                            )
                        }),
                    )
                    .when(preview_available, |toolbar| {
                        toolbar.child(
                            inactive_editor_toolbar_button(
                                SharedString::from(format!("open-editor-preview-{tab_id}")),
                                "Open Preview",
                                AleraIcon::Preview,
                                true,
                            )
                            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Open Preview")).into())
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.activate_workspace_tab(preview_tab_id.clone(), cx);
                                    this.open_editor_preview(cx);
                                }),
                            ),
                        )
                    })
            })
            .when(is_markdown_viewer, |toolbar| {
                let refresh_tab_id = tab_id.clone();
                let refresh_path = path.clone();
                let source_path = path.clone();
                toolbar
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("refresh-markdown-preview-{tab_id}")),
                            "Refresh Preview",
                            AleraIcon::Refresh,
                            !self.editor_busy,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh Preview")).into())
                        .when(!self.editor_busy, |button| {
                            button.on_click(cx.listener(move |this, _, window, cx| {
                                cx.stop_propagation();
                                this.activate_workspace_tab(refresh_tab_id.clone(), cx);
                                this.load_workspace_file(refresh_path.clone(), window, cx);
                            }))
                        }),
                    )
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("open-markdown-source-{tab_id}")),
                            "Open Source File",
                            AleraIcon::Code,
                            true,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Open Source File")).into())
                        .on_click(cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.open_editor_tab(source_path.clone(), cx);
                        })),
                    )
            })
            .when(is_merman_viewer, |toolbar| {
                let source_path = path.clone();
                let refresh_tab_id = tab_id.clone();
                let refresh_path = path.clone();
                toolbar
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("open-merman-source-{tab_id}")),
                            "Open Editor",
                            AleraIcon::Edit,
                            true,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Open Editor")).into())
                        .on_click(cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.open_editor_tab(source_path.clone(), cx);
                        })),
                    )
                    .child(
                        inactive_editor_toolbar_button(
                            SharedString::from(format!("refresh-merman-preview-{tab_id}")),
                            "Refresh Preview",
                            AleraIcon::Refresh,
                            !self.editor_busy,
                        )
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh Preview")).into())
                        .when(!self.editor_busy, |button| {
                            button.on_click(cx.listener(move |this, _, window, cx| {
                                cx.stop_propagation();
                                this.activate_workspace_tab(refresh_tab_id.clone(), cx);
                                this.load_workspace_file(refresh_path.clone(), window, cx);
                            }))
                        }),
                    )
            });
        let header = div()
            .flex()
            .items_center()
            .justify_between()
            .h(theme::header_height())
            .px_3()
            .border_b_1()
            .border_color(theme::border())
            .cursor(CursorStyle::PointingHand)
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.activate_workspace_tab(header_tab_id.clone(), cx);
                }),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .flex_1()
                    .min_w_0()
                    .child(file_icon(&path, false, false, false, 16.0, title_color))
                    .child(
                        div()
                            .ml_2()
                            .flex_1()
                            .min_w_0()
                            .overflow_hidden()
                            .whitespace_nowrap()
                            .text_ellipsis()
                            .font_family("JetBrains Mono")
                            .text_size(px(12.0))
                            .text_color(title_color)
                            .child(path.clone()),
                    ),
            )
            .child(toolbar);
        let live_editor = tab.kind == "editor" && self.editor_documents.contains_key(&path);
        let loading = self.editor_loading_path.as_deref() == Some(path.as_str());
        let error = self.editor_error_messages.get(&path).cloned();
        let body = if loading {
            div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .child(loading_indicator(36.0, theme::text_muted()))
                .into_any_element()
        } else if let Some(message) = error {
            div()
                .id(SharedString::from(format!("editor-load-error-{path}")))
                .role(Role::Alert)
                .aria_label(message.clone())
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .font_family("Inter")
                .text_size(px(13.0))
                .text_color(theme::text_muted())
                .child(message)
                .into_any_element()
        } else {
            match self.editor_preview_assets.get(&path) {
                Some(PreviewAsset::Image(image)) => div()
                    .flex_1()
                    .flex()
                    .items_center()
                    .justify_center()
                    .overflow_hidden()
                    .child(img(image.clone()))
                    .into_any_element(),
                Some(PreviewAsset::Mermaid(image)) if is_merman_viewer => div()
                    .flex_1()
                    .flex()
                    .items_center()
                    .justify_center()
                    .overflow_hidden()
                    .child(img(image.clone()))
                    .into_any_element(),
                Some(PreviewAsset::Markdown) if is_markdown_viewer => self
                    .editor_documents
                    .get(&path)
                    .map(|document| {
                        let markdown = self
                            .markdown_preview_content
                            .get(&path)
                            .unwrap_or(&document.display_content);
                        div()
                            .flex_1()
                            .overflow_hidden()
                            .py_6()
                            .px(px(27.0))
                            .child(
                                with_markdown_images(TextView::markdown(
                                    SharedString::from(format!("inactive-markdown-{path}")),
                                    normalize_nested_fenced_code_blocks(markdown),
                                ))
                                .into_any_element(),
                            )
                            .into_any_element()
                    })
                    .unwrap_or_else(|| {
                        inactive_editor_text(
                            self.editor_documents.get(&path),
                            self.editor_buffer_text.get(&path),
                        )
                    }),
                _ if tab.kind == "editor" && self.editor_documents.contains_key(&path) => {
                    self.render_inactive_editor_input(&path, tab.id.clone(), cx)
                }
                _ => inactive_editor_text(
                    self.editor_documents.get(&path),
                    self.editor_buffer_text.get(&path),
                ),
            }
        };
        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .when(!live_editor, |pane| {
                pane.on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        this.activate_workspace_tab(tab_id.clone(), cx);
                    }),
                )
            })
            .child(header)
            .child(body)
            .into_any_element()
    }

    fn render_inactive_editor_input(
        &self,
        path: &str,
        tab_id: String,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let input = self.editor_input_for_path(path);
        let text_actions = self.settings_state.text_actions.clone();
        let ai_text_enabled = self.settings_state.ai_text_enabled;
        let editor_background = cx
            .theme()
            .highlight_theme
            .style
            .editor_background
            .unwrap_or_else(|| cx.theme().background);
        div()
            .flex_1()
            .relative()
            .overflow_hidden()
            .bg(editor_background)
            .font_family("JetBrains Mono")
            .child(
                Editor::new(&input)
                    .h_full()
                    .p_0()
                    .bordered(false)
                    .text_size(px(13.0))
                    .line_height(px(17.55))
                    .context_menu(move |menu, window, cx| {
                        editor_context_menu(
                            menu,
                            input.clone(),
                            text_actions.clone(),
                            ai_text_enabled,
                            window,
                            cx,
                        )
                    }),
            )
            // Keep the inactive pane's scrollbar rail transparent just like
            // the active Flutter editor surface.
            .child(
                div()
                    .absolute()
                    .top_0()
                    .right_0()
                    .bottom_0()
                    .w(px(10.0))
                    .bg(editor_background),
            )
            // The pane container promotes this tab on mouse-down. Let the same
            // event continue into its route-owned EditorState so caret,
            // selection and typing behave like Flutter's per-tab editor
            // sessions instead of requiring a second click through a read-only
            // activation shield.
            .id(SharedString::from(format!(
                "inactive-editor-input-{tab_id}"
            )))
            .into_any_element()
    }

    /// Keep an editor document visible and editable after its pane becomes
    /// inactive. Its route-owned state promotes the pane when it receives focus.
    fn render_active_editor(
        &self,
        window: &mut Window,
        active: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let selected_file_path = self
            .selected_tab_id
            .as_deref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| tab.id == selected))
            .and_then(|tab| tab.payload.get("filePath"))
            .and_then(Value::as_str)
            .map(str::to_owned);
        let opened_path = selected_file_path
            .as_ref()
            .or(self.opened_file_path.as_ref());
        let Some(opened_path) = opened_path else {
            return div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child("This editor tab has no file.")
                .into_any_element();
        };
        let editor_input = self.editor_input_for_path(opened_path);
        let text_actions = self.settings_state.text_actions.clone();
        let ai_text_enabled = self.settings_state.ai_text_enabled;
        let editor_background = cx
            .theme()
            .highlight_theme
            .style
            .editor_background
            .unwrap_or_else(|| cx.theme().background);
        let editor_error = selected_file_path
            .as_ref()
            .and_then(|path| self.editor_error_messages.get(path))
            .cloned();
        let preview_available = self.preview_asset.is_some();
        let source_available = self.editor_document.is_some();
        let save_tooltip = if self.editor_busy {
            "Saving File"
        } else {
            "Save File"
        };
        let is_markdown_viewer = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected))
            .is_some_and(|tab| tab.kind == "markdownViewer");
        let is_merman_viewer = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected))
            .is_some_and(|tab| {
                tab.kind == "editor"
                    && tab.payload.get("fileRole").and_then(Value::as_str) == Some("mermanPreview")
            });
        let is_markdown_editor = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected))
            .is_some_and(|tab| {
                tab.kind == "editor"
                    && tab
                        .payload
                        .get("filePath")
                        .and_then(Value::as_str)
                        .is_some_and(|path| {
                            matches!(
                                Path::new(path)
                                    .extension()
                                    .and_then(|extension| extension.to_str()),
                                Some("md" | "mdx")
                            )
                        })
            });
        let file_color = if self.editor_dirty {
            theme::text()
        } else {
            theme::text_muted()
        };
        let content = if let Some(message) = editor_error {
            div()
                .id("active-editor-load-error")
                .role(Role::Alert)
                .aria_label(message.clone())
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .font_family("Inter")
                .text_size(px(13.0))
                .text_color(theme::text_muted())
                .child(message)
                .into_any_element()
        } else if self.editor_loading_path.as_deref() == Some(opened_path.as_str())
            && self.editor_busy
        {
            div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .child(loading_indicator(36.0, theme::text_muted()))
                .into_any_element()
        } else if self.editor_loading_path.as_deref() == Some(opened_path.as_str())
            && !self.editor_busy
        {
            div()
                .flex_1()
                .flex()
                .flex_col()
                .items_center()
                .justify_center()
                .font_family("Inter")
                .text_size(px(13.0))
                .text_color(theme::text_muted())
                .child(
                    self.local_message
                        .clone()
                        .unwrap_or_else(|| "File operation failed".into()),
                )
                .into_any_element()
        } else if (self.show_preview && !is_markdown_editor)
            || is_markdown_viewer
            || is_merman_viewer
        {
            self.render_preview(window, cx)
        } else {
            div()
                .flex_1()
                .relative()
                .overflow_hidden()
                .bg(editor_background)
                .font_family("JetBrains Mono")
                .child(
                    Editor::new(&editor_input)
                        .h_full()
                        .p_0()
                        .bordered(false)
                        // Match Flutter's bodyMedium (13 px) and 1.35 line
                        // height instead of gpui-component's compact input
                        // defaults (11.375 px / 1.25).
                        .text_size(px(13.0))
                        .line_height(px(17.55))
                        .disabled(!active)
                        .context_menu(move |menu, window, cx| {
                            editor_context_menu(
                                menu,
                                editor_input.clone(),
                                text_actions.clone(),
                                ai_text_enabled,
                                window,
                                cx,
                            )
                        }),
                )
                // Flutter's CodeForge config keeps the editor scrollbar
                // transparent. gpui-component's Input does not expose a
                // per-instance scrollbar decoration, so cover only its
                // trailing rail instead of changing the global theme used by
                // Settings, Explorer, and terminal surfaces.
                .child(
                    div()
                        .absolute()
                        .top_0()
                        .right_0()
                        .bottom_0()
                        .w(px(10.0))
                        .bg(editor_background),
                )
                .into_any_element()
        };
        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(theme::header_height())
                    .px_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .min_w_0()
                            .flex_1()
                            .child(file_icon(
                                opened_path,
                                false,
                                false,
                                false,
                                16.0,
                                file_color,
                            ))
                            .child(
                                div()
                                    .ml_2()
                                    .flex_1()
                                    .min_w_0()
                                    .overflow_hidden()
                                    .whitespace_nowrap()
                                    .text_ellipsis()
                                    .font_family("JetBrains Mono")
                                    .text_size(px(12.0))
                                    .text_color(file_color)
                                    .child(opened_path.clone()),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .when(
                                !is_markdown_viewer && !is_merman_viewer && source_available,
                                |toolbar| {
                                    toolbar
                                        .child(
                                            editor_toolbar_button(
                                                "editor-view-diff",
                                                "View Diff",
                                                AleraIcon::Diff,
                                                active,
                                            )
                                            .tooltip(|_, cx| {
                                                cx.new(|_| Tooltip::new("View Diff")).into()
                                            })
                                            .when(
                                                active,
                                                |button| {
                                                    button.on_mouse_down(
                                                        gpui::MouseButton::Left,
                                                        cx.listener(|this, _, _, cx| {
                                                            this.open_editor_diff(cx)
                                                        }),
                                                    )
                                                },
                                            ),
                                        )
                                        .child(
                                            editor_toolbar_button(
                                                "save-editor",
                                                save_tooltip,
                                                if self.editor_busy {
                                                    AleraIcon::Loading
                                                } else {
                                                    AleraIcon::Save
                                                },
                                                active && !self.editor_busy && self.editor_dirty,
                                            )
                                            .tooltip(move |_, cx| {
                                                cx.new(|_| Tooltip::new(save_tooltip)).into()
                                            })
                                            .when(active, |button| {
                                                button.on_mouse_down(
                                                    gpui::MouseButton::Left,
                                                    cx.listener(|this, _, _, cx| {
                                                        if this.editor_dirty && !this.editor_busy {
                                                            this.save_editor(false, cx);
                                                        }
                                                    }),
                                                )
                                            })
                                            .when(
                                                self.editor_busy,
                                                |button| {
                                                    button.child(loading_indicator(
                                                        14.0,
                                                        theme::text_muted(),
                                                    ))
                                                },
                                            ),
                                        )
                                        .child(
                                            editor_toolbar_button(
                                                "discard-editor",
                                                "Discard Changes",
                                                AleraIcon::Restore,
                                                active && !self.editor_busy && self.editor_dirty,
                                            )
                                            .tooltip(|_, cx| {
                                                cx.new(|_| Tooltip::new("Discard Changes")).into()
                                            })
                                            .when(
                                                active,
                                                |button| {
                                                    button.on_mouse_down(
                                                        gpui::MouseButton::Left,
                                                        cx.listener(|this, _, window, cx| {
                                                            if this.editor_dirty
                                                                && !this.editor_busy
                                                            {
                                                                this.discard_editor_changes(
                                                                    window, cx,
                                                                );
                                                            }
                                                        }),
                                                    )
                                                },
                                            ),
                                        )
                                        .when(preview_available, |toolbar| {
                                            toolbar.child(
                                                editor_toolbar_button(
                                                    "open-editor-preview",
                                                    "Open Preview",
                                                    AleraIcon::Preview,
                                                    active,
                                                )
                                                .tooltip(|_, cx| {
                                                    cx.new(|_| Tooltip::new("Open Preview")).into()
                                                })
                                                .when(active, |button| {
                                                    button.on_mouse_down(
                                                        gpui::MouseButton::Left,
                                                        cx.listener(|this, _, _, cx| {
                                                            this.open_editor_preview(cx)
                                                        }),
                                                    )
                                                }),
                                            )
                                        })
                                },
                            )
                            .when(is_markdown_viewer, |toolbar| {
                                let refresh_enabled = active && !self.editor_busy;
                                let refresh_button = editor_toolbar_button(
                                    "refresh-markdown-preview",
                                    if refresh_enabled {
                                        "Refresh Preview"
                                    } else {
                                        "Refreshing Preview"
                                    },
                                    if refresh_enabled {
                                        AleraIcon::Refresh
                                    } else {
                                        AleraIcon::Loading
                                    },
                                    refresh_enabled,
                                )
                                .tooltip(move |_, cx| {
                                    cx.new(|_| {
                                        Tooltip::new(if refresh_enabled {
                                            "Refresh Preview"
                                        } else {
                                            "Refreshing Preview"
                                        })
                                    })
                                    .into()
                                })
                                .when(self.editor_busy, |button| {
                                    button.child(loading_indicator(14.0, theme::text_muted()))
                                })
                                .when(active, |button| {
                                    button.on_click(cx.listener(|this, _, window, cx| {
                                        if let Some(path) = this.opened_file_path.clone() {
                                            this.load_workspace_file(path, window, cx);
                                        }
                                    }))
                                });
                                let open_source_button = editor_toolbar_button(
                                    "open-markdown-source",
                                    "Open Source File",
                                    AleraIcon::Code,
                                    active,
                                )
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Open Source File")).into()
                                })
                                .when(active, |button| {
                                    button.on_click(cx.listener(|this, _, _, cx| {
                                        if let Some(path) = this.opened_file_path.clone() {
                                            this.open_editor_tab(path, cx);
                                        }
                                    }))
                                });
                                toolbar.child(refresh_button).child(open_source_button)
                            })
                            .when(is_merman_viewer, |toolbar| {
                                let refresh_enabled = active && !self.editor_busy;
                                let refresh_button = editor_toolbar_button(
                                    "refresh-merman-preview",
                                    if refresh_enabled {
                                        "Refresh Preview"
                                    } else {
                                        "Refreshing Preview"
                                    },
                                    if refresh_enabled {
                                        AleraIcon::Refresh
                                    } else {
                                        AleraIcon::Loading
                                    },
                                    refresh_enabled,
                                )
                                .tooltip(move |_, cx| {
                                    cx.new(|_| {
                                        Tooltip::new(if refresh_enabled {
                                            "Refresh Preview"
                                        } else {
                                            "Refreshing Preview"
                                        })
                                    })
                                    .into()
                                })
                                .when(self.editor_busy, |button| {
                                    button.child(loading_indicator(14.0, theme::text_muted()))
                                })
                                .when(active, |button| {
                                    button.on_click(cx.listener(|this, _, window, cx| {
                                        if let Some(path) = this.opened_file_path.clone() {
                                            this.load_workspace_file(path, window, cx);
                                        }
                                    }))
                                });
                                let open_source_button = editor_toolbar_button(
                                    "open-merman-source",
                                    "Open Editor",
                                    AleraIcon::Edit,
                                    active,
                                )
                                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Open Editor")).into())
                                .when(active, |button| {
                                    button.on_click(cx.listener(|this, _, _, cx| {
                                        if let Some(path) = this.opened_file_path.clone() {
                                            this.open_editor_tab(path, cx);
                                        }
                                    }))
                                });
                                toolbar.child(open_source_button).child(refresh_button)
                            }),
                    ),
            )
            .child(content)
            .into_any_element()
    }

    fn render_preview(&self, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        match (&self.preview_asset, &self.editor_document) {
            (Some(PreviewAsset::Markdown), Some(document)) => {
                // TextView's code-action host is absolutely positioned. Give
                // the action row the active pane width so it can reproduce
                // Flutter's full-width language/copy header instead of
                // collapsing to the intrinsic width of its children.
                let code_action_width = self
                    .selected_tab_id
                    .as_deref()
                    .and_then(|selected| {
                        self.snapshot
                            .layout
                            .as_ref()?
                            .groups
                            .values()
                            .find(|group| group.tab_ids.iter().any(|tab_id| tab_id == selected))
                    })
                    .and_then(|group| self.pane_bounds.get(&group.id))
                    .map(|bounds| (bounds.size.width.as_f32() - 64.0).max(120.0))
                    .unwrap_or(640.0);
                let markdown = self
                    .markdown_preview_content
                    .get(&document.relative_path)
                    .unwrap_or(&document.display_content);
                div()
                    .id("markdown-preview")
                    .flex_1()
                    .overflow_hidden()
                    .py_6()
                    .px(px(27.0))
                    .child(
                        with_markdown_images(TextView::markdown(
                            "markdown-preview-content",
                            normalize_nested_fenced_code_blocks(markdown),
                        ))
                        .style({
                            TextViewStyle {
                                is_dark: true,
                                paragraph_gap: rems(1.35),
                                highlight_theme: cx.theme().highlight_theme.clone(),
                                heading_font_size: Some(std::sync::Arc::new(|level, _base| {
                                    match level {
                                        1 => px(34.0),
                                        2 => px(29.0),
                                        3 => px(24.0),
                                        4 => px(21.0),
                                        5 => px(18.0),
                                        _ => px(16.0),
                                    }
                                })),
                                // Flutter's markdown renderer inherits the body
                                // text rhythm for fenced code blocks (13 px with
                                // a 1.45 line height). TextView's compact mono
                                // defaults make the same document visibly shorter.
                                code_block: StyleRefinement::default()
                                    // Flutter's CodeField uses the inverse surface
                                    // role, which is intentionally darker than the
                                    // elevated GPUI muted surface.
                                    .bg(gpui::rgb(0x121212))
                                    .rounded(px(8.0))
                                    // TextView renders its optional actions in an
                                    // absolute top-right layer. Reserve the same
                                    // top row that Flutter's CodeField uses so the
                                    // language label and Copy code action never
                                    // overlap the first source line.
                                    .pt(px(52.0))
                                    .pr(px(16.0))
                                    .pb(px(28.0))
                                    .pl(px(16.0))
                                    .text_size(px(13.0))
                                    .line_height(px(18.85)),
                                ..Default::default()
                            }
                        })
                        .code_block_actions(move |code_block, _, _cx| {
                            let code = code_block.code();
                            let mut code_hasher = DefaultHasher::new();
                            code.hash(&mut code_hasher);
                            let copy_id = SharedString::from(format!(
                                "markdown-copy-code-{:016x}",
                                code_hasher.finish()
                            ));
                            let language = code_block
                                .lang()
                                .filter(|language| !language.is_empty())
                                .unwrap_or_else(|| "text".into());
                            div()
                                .flex()
                                .items_center()
                                .justify_between()
                                .w(px(code_action_width))
                                .bg(gpui::rgb(0x121212))
                                .px_3()
                                .pt(px(4.0))
                                .pb(px(8.0))
                                .border_b_1()
                                .border_color(theme::border_subtle())
                                .text_size(px(11.0))
                                .text_color(theme::text_muted())
                                .child(language)
                                .child(
                                    div()
                                        .id(copy_id)
                                        .focusable()
                                        .tab_stop(true)
                                        .role(Role::Button)
                                        .aria_label("Copy code")
                                        .flex()
                                        .items_center()
                                        .gap_1()
                                        .cursor(CursorStyle::PointingHand)
                                        .on_click(move |_, _, cx| {
                                            cx.write_to_clipboard(ClipboardItem::new_string(
                                                code.to_string(),
                                            ));
                                        })
                                        .child(icon(AleraIcon::Copy, 13.0, theme::text_muted()))
                                        .child("Copy code"),
                                )
                        })
                        .selectable(true)
                        .scrollable(true),
                    )
                    .into_any_element()
            }
            (Some(PreviewAsset::Mermaid(image)), _) => {
                self.render_zoomable_preview(image, "merman-preview", window, cx)
            }
            (Some(PreviewAsset::Image(image)), _) => {
                self.render_zoomable_preview(image, "image-preview", window, cx)
            }
            _ => div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child("Preview Unavailable")
                .into_any_element(),
        }
    }

    fn render_zoomable_preview(
        &self,
        image: &std::sync::Arc<gpui::Image>,
        id: &'static str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let transform_key = self
            .selected_tab_id
            .clone()
            .unwrap_or_else(|| id.to_owned());
        let transform = self
            .preview_transforms
            .get(&transform_key)
            .copied()
            .unwrap_or_default();
        let (viewport_width, viewport_height) = self.preview_viewport_size();
        let render_image = image.clone().get_render_image(window, cx);
        let intrinsic_scale = if id == "merman-preview" {
            window.scale_factor().max(1.0)
        } else {
            1.0
        };
        let (intrinsic_width, intrinsic_height) = render_image
            .as_ref()
            .map(|image| {
                let size = image.size(0);
                (
                    size.width.0 as f32 / intrinsic_scale,
                    size.height.0 as f32 / intrinsic_scale,
                )
            })
            .filter(|(width, height)| *width > 0.0 && *height > 0.0)
            .unwrap_or((viewport_width, viewport_height));
        let available_width = (viewport_width - 48.0).max(1.0);
        // `pane_bounds` includes the file bar. Flutter's InteractiveViewer
        // receives only the remaining content height, then applies its 24 px
        // padding on both sides before BoxFit.contain resolves the image.
        let available_height = (viewport_height - theme::header_height().as_f32() - 48.0).max(1.0);
        let fit_scale = (available_width / intrinsic_width)
            .min(available_height / intrinsic_height)
            .min(1.0);
        let display_scale = fit_scale * transform.scale;
        let display_width = intrinsic_width * display_scale;
        let display_height = intrinsic_height * display_scale;
        let max_offset_x = ((display_width - available_width) / 2.0).max(0.0) + 48.0;
        let max_offset_y = ((display_height - available_height) / 2.0).max(0.0) + 48.0;
        let offset_x = transform
            .offset
            .x
            .as_f32()
            .clamp(-max_offset_x, max_offset_x);
        let offset_y = transform
            .offset
            .y
            .as_f32()
            .clamp(-max_offset_y, max_offset_y);

        let image_element = if let Some(render_image) = render_image {
            div()
                .relative()
                .w(px(display_width.max(1.0)))
                .h(px(display_height.max(1.0)))
                .left(px(offset_x))
                .top(px(offset_y))
                .child(img(render_image).size_full())
                .into_any_element()
        } else {
            div()
                .relative()
                .w(px(display_width.max(1.0)))
                .h(px(display_height.max(1.0)))
                .left(px(offset_x))
                .top(px(offset_y))
                .child(img(image.clone()).size_full())
                .into_any_element()
        };
        let pointer_key = transform_key.clone();
        let move_key = transform_key.clone();
        let release_key = transform_key.clone();
        let release_out_key = transform_key.clone();
        let scroll_key = transform_key.clone();
        div()
            .id(SharedString::from(format!("{id}-{transform_key}")))
            .flex_1()
            .relative()
            .overflow_hidden()
            .flex()
            .items_center()
            .justify_center()
            .p_6()
            // Flutter's image/Mermaid InteractiveViewer exposes the click
            // cursor before a gesture; keep the initial pointer affordance
            // consistent instead of showing an open-hand grab cursor.
            .cursor(CursorStyle::PointingHand)
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    let initial_offset = this
                        .preview_transforms
                        .get(&pointer_key)
                        .copied()
                        .unwrap_or_default()
                        .offset;
                    this.preview_drag = Some(PreviewDragState {
                        tab_id: pointer_key.clone(),
                        start: event.position,
                        initial_offset,
                    });
                    cx.stop_propagation();
                }),
            )
            .on_mouse_move(cx.listener(move |this, event: &MouseMoveEvent, _, cx| {
                if event.pressed_button == Some(MouseButton::Left) {
                    if let Some(drag) = this
                        .preview_drag
                        .as_ref()
                        .filter(|drag| drag.tab_id == move_key)
                        .cloned()
                    {
                        let transform =
                            this.preview_transforms.entry(move_key.clone()).or_default();
                        transform.offset = gpui::point(
                            drag.initial_offset.x + (event.position.x - drag.start.x),
                            drag.initial_offset.y + (event.position.y - drag.start.y),
                        );
                        cx.notify();
                    }
                }
            }))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(move |this, _, _, _| {
                    if this
                        .preview_drag
                        .as_ref()
                        .is_some_and(|drag| drag.tab_id == release_key)
                    {
                        this.preview_drag = None;
                    }
                }),
            )
            .on_mouse_up_out(
                MouseButton::Left,
                cx.listener(move |this, _, _, _| {
                    if this
                        .preview_drag
                        .as_ref()
                        .is_some_and(|drag| drag.tab_id == release_out_key)
                    {
                        this.preview_drag = None;
                    }
                }),
            )
            .on_scroll_wheel(cx.listener(move |this, event, window, cx| {
                this.handle_preview_scroll(&scroll_key, event, window, cx);
            }))
            .child(image_element)
            .into_any_element()
    }

    fn preview_viewport_size(&self) -> (f32, f32) {
        let bounds = self
            .selected_tab_id
            .as_deref()
            .and_then(|selected| {
                self.snapshot
                    .layout
                    .as_ref()?
                    .groups
                    .values()
                    .find(|group| group.tab_ids.iter().any(|tab_id| tab_id == selected))
            })
            .and_then(|group| self.pane_bounds.get(&group.id));
        bounds
            .map(|bounds| (bounds.size.width.as_f32(), bounds.size.height.as_f32()))
            .unwrap_or((640.0, 480.0))
    }

    fn handle_preview_scroll(
        &mut self,
        tab_id: &str,
        event: &ScrollWheelEvent,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let delta = event.delta.pixel_delta(px(16.0));
        let transform = self
            .preview_transforms
            .entry(tab_id.to_owned())
            .or_default();
        if event.modifiers.platform || event.modifiers.control {
            let factor = (1.0_f32 - delta.y.as_f32() * 0.002).clamp(0.8, 1.25);
            transform.scale = (transform.scale * factor).clamp(0.25, 8.0);
        } else {
            transform.offset =
                gpui::point(transform.offset.x - delta.x, transform.offset.y - delta.y);
        }
        cx.stop_propagation();
        cx.notify();
    }
}

fn inactive_editor_text(document: Option<&EditorDocument>, buffer: Option<&String>) -> AnyElement {
    let content = document
        .map(|document| {
            buffer
                .cloned()
                .unwrap_or_else(|| document.display_content.clone())
        })
        .unwrap_or_else(|| "This editor tab has no file.".to_owned());
    div()
        .flex_1()
        .overflow_hidden()
        .p_3()
        .font_family("JetBrains Mono")
        .text_size(px(13.0))
        .line_height(px(17.55))
        .child(StyledText::new(SharedString::from(content)))
        .into_any_element()
}

fn editor_toolbar_button(
    id: &'static str,
    label: &'static str,
    kind: AleraIcon,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .w(px(28.0))
        .h(px(28.0))
        .rounded_md()
        .cursor(if enabled {
            CursorStyle::PointingHand
        } else {
            CursorStyle::Arrow
        })
        .when(enabled, |button| {
            button.hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(
            kind,
            15.0,
            if enabled {
                theme::text_muted()
            } else {
                theme::text_faint()
            },
        ))
}

fn inactive_editor_toolbar_button(
    id: SharedString,
    label: &'static str,
    kind: AleraIcon,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .w(px(28.0))
        .h(px(28.0))
        .rounded_md()
        .cursor(if enabled {
            CursorStyle::PointingHand
        } else {
            CursorStyle::Arrow
        })
        .when(enabled, |button| {
            button.hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(
            kind,
            15.0,
            if enabled {
                theme::text_muted()
            } else {
                theme::text_faint()
            },
        ))
}

/// The Flutter renderer accepts fenced code blocks nested inside ordered-list
/// items. The GPUI markdown parser only recognizes fences at the document
/// indentation level, so normalize that common Markdown form before parsing.
fn normalize_nested_fenced_code_blocks(markdown: &str) -> String {
    let mut normalized = String::with_capacity(markdown.len());
    let mut nested_fence = false;
    let mut after_nested_fence = false;
    for line in markdown.lines() {
        let leading_spaces = line.bytes().take_while(|byte| *byte == b' ').count();
        let trimmed = line.trim_start();
        if !nested_fence && leading_spaces >= 4 && trimmed.starts_with("```") {
            normalized.push_str(trimmed);
            normalized.push('\n');
            nested_fence = true;
            continue;
        }
        if nested_fence {
            if trimmed.starts_with("```") {
                normalized.push_str(trimmed);
                normalized.push('\n');
                nested_fence = false;
                after_nested_fence = true;
            } else if leading_spaces >= 4 {
                normalized.push_str(&line[4..]);
                normalized.push('\n');
            } else {
                normalized.push_str(line);
                normalized.push('\n');
                nested_fence = false;
            }
            continue;
        }
        if after_nested_fence {
            if trimmed.is_empty() {
                normalized.push('\n');
                continue;
            }
            if let Some((number, rest)) = trimmed.split_once(". ") {
                if !number.is_empty() && number.bytes().all(|byte| byte.is_ascii_digit()) {
                    normalized.push_str(number);
                    normalized.push_str("\\. ");
                    normalized.push_str(rest);
                    normalized.push('\n');
                    after_nested_fence = false;
                    continue;
                }
            }
            after_nested_fence = false;
        }
        normalized.push_str(line);
        normalized.push('\n');
    }
    if !markdown.ends_with('\n') {
        normalized.pop();
    }
    normalized
}

#[cfg(test)]
mod tests {
    use super::normalize_nested_fenced_code_blocks;

    #[test]
    fn normalizes_fenced_code_nested_in_ordered_lists() {
        let markdown = "1. Clone:\n\n    ```bash\n    git clone repo\n    ```\n\n2. Install";
        assert_eq!(
            normalize_nested_fenced_code_blocks(markdown),
            "1. Clone:\n\n```bash\ngit clone repo\n```\n\n2\\. Install"
        );
    }
}
