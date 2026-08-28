use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, KeyDownEvent, ParentElement as _, Pixels, Point, Role,
    StatefulInteractiveElement as _, Styled as _, Window,
};

use super::{AleraApp, ExplorerMenuTarget};
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_explorer_menu(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let menu = match self.explorer_menu.clone() {
            Some(ExplorerMenuTarget::Background) => {
                self.render_explorer_background_menu(window, cx)
            }
            Some(ExplorerMenuTarget::Entry(path)) => {
                self.render_explorer_entry_menu(path, window, cx)
            }
            None => div().into_any_element(),
        };
        div()
            .id("explorer-menu-overlay")
            .track_focus(&self.explorer_menu_focus)
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, window, cx| {
                    this.dismiss_explorer_menu(window, cx);
                }),
            )
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key.as_str() == "escape" {
                    this.dismiss_explorer_menu(window, cx);
                    cx.stop_propagation();
                }
            }))
            .child(menu)
    }

    fn render_explorer_background_menu(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        explorer_menu_shell(
            "explorer-background-menu",
            self.explorer_menu_position,
            window.viewport_size(),
            px(70.0),
        )
        .child(
            explorer_menu_button(
                "explorer-background-new-file",
                AleraIcon::NewFile,
                "New file",
            )
            .on_click(cx.listener(|this, _, window, cx| {
                cx.stop_propagation();
                this.begin_create_explorer_entry(false, window, cx);
            })),
        )
        .child(
            explorer_menu_button(
                "explorer-background-new-folder",
                AleraIcon::NewFolder,
                "New folder",
            )
            .on_click(cx.listener(|this, _, window, cx| {
                cx.stop_propagation();
                this.begin_create_explorer_entry(true, window, cx);
            })),
        )
        .into_any_element()
    }

    fn render_explorer_entry_menu(
        &self,
        relative_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let target_directory = self.explorer_target_directory(Some(&relative_path));
        let create_file_parent = target_directory.clone();
        let create_folder_parent = target_directory;
        let copy_path = relative_path.clone();
        let cut_path = relative_path.clone();
        let paste_path = relative_path.clone();
        let absolute_path = relative_path.clone();
        let relative_copy_path = relative_path.clone();
        let duplicate_path = relative_path.clone();
        let reveal_path = relative_path.clone();
        let rename_path = relative_path.clone();
        let source_root_path = relative_path.clone();
        let collapse_path = relative_path.clone();
        let delete_path = relative_path;
        let can_paste = self.explorer_clipboard.is_some();
        let can_set_source_root = self.can_focus_source_control_folders()
            && self
                .explorer_rows
                .iter()
                .find(|row| row.entry.relative_path == source_root_path)
                .is_some_and(|row| row.entry.is_directory);
        let is_source_root = self.is_focused_source_control_root(&source_root_path);
        let menu_height = if can_set_source_root {
            px(486.0)
        } else {
            px(444.0)
        };

        explorer_menu_shell(
            "explorer-entry-menu",
            self.explorer_menu_position,
            window.viewport_size(),
            menu_height,
        )
        .child(
            explorer_menu_button("explorer-entry-new-file", AleraIcon::NewFile, "New file")
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.begin_create_explorer_entry_at(
                        create_file_parent.clone(),
                        false,
                        window,
                        cx,
                    );
                })),
        )
        .child(
            explorer_menu_button(
                "explorer-entry-new-folder",
                AleraIcon::NewFolder,
                "New folder",
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                cx.stop_propagation();
                this.begin_create_explorer_entry_at(create_folder_parent.clone(), true, window, cx);
            })),
        )
        .child(
            explorer_menu_button("explorer-entry-copy", AleraIcon::Copy, "Copy").on_click(
                cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.copy_explorer_entry(copy_path.clone(), false, cx);
                }),
            ),
        )
        .child(
            explorer_menu_button("explorer-entry-cut", AleraIcon::Cut, "Cut").on_click(
                cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.copy_explorer_entry(cut_path.clone(), true, cx);
                }),
            ),
        )
        .child(
            explorer_menu_button("explorer-entry-paste", AleraIcon::Paste, "Paste")
                .when(!can_paste, |button| {
                    button
                        .tab_stop(false)
                        .text_color(theme::text_faint())
                        .cursor(CursorStyle::Arrow)
                })
                .when(can_paste, |button| {
                    button.on_click(cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        this.paste_explorer_entry(Some(paste_path.clone()), cx);
                    }))
                }),
        )
        .child(
            explorer_menu_button("explorer-entry-copy-path", AleraIcon::Copy, "Copy path")
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.copy_explorer_path(absolute_path.clone(), true, cx);
                })),
        )
        .child(
            explorer_menu_button(
                "explorer-entry-copy-relative",
                AleraIcon::Copy,
                "Copy relative path",
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.copy_explorer_path(relative_copy_path.clone(), false, cx);
            })),
        )
        .child(
            explorer_menu_button(
                "explorer-entry-duplicate",
                AleraIcon::Duplicate,
                "Duplicate",
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.duplicate_explorer_entry(duplicate_path.clone(), cx);
            })),
        )
        .child(
            explorer_menu_button(
                "explorer-entry-reveal",
                AleraIcon::External,
                "Reveal in Finder",
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.reveal_explorer_entry(reveal_path.clone(), cx);
            })),
        )
        .child(explorer_menu_divider())
        .child(
            explorer_menu_button("explorer-entry-rename", AleraIcon::Edit, "Rename").on_click(
                cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.begin_rename_explorer_entry(rename_path.clone(), window, cx);
                }),
            ),
        )
        .when(can_set_source_root, |menu| {
            menu.child(explorer_menu_divider()).child(
                explorer_menu_button(
                    "explorer-entry-source-root",
                    if is_source_root {
                        AleraIcon::Close
                    } else {
                        AleraIcon::GitBranch
                    },
                    if is_source_root {
                        "Clear Source Control Root"
                    } else {
                        "Use As Source Control Root"
                    },
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    if is_source_root {
                        this.clear_source_control_root(cx);
                    } else {
                        this.focus_source_control_root(source_root_path.clone(), cx);
                    }
                })),
            )
        })
        .child(explorer_menu_divider())
        .child(
            explorer_menu_button(
                "explorer-entry-collapse",
                AleraIcon::ChevronRight,
                "Collapse folder",
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.collapse_explorer_entry(collapse_path.clone(), cx);
            })),
        )
        .child(
            explorer_menu_button("explorer-entry-refresh", AleraIcon::Refresh, "Refresh").on_click(
                cx.listener(|this, _, _, cx| {
                    cx.stop_propagation();
                    this.refresh_explorer_entry(cx);
                }),
            ),
        )
        .child(explorer_menu_divider())
        .child(
            explorer_menu_button("explorer-entry-delete", AleraIcon::Delete, "Delete")
                .text_color(theme::danger())
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.begin_delete_explorer_entry(delete_path.clone(), cx);
                })),
        )
        .into_any_element()
    }
}

fn explorer_menu_shell(
    id: &'static str,
    position: Point<Pixels>,
    viewport: gpui::Size<Pixels>,
    height: Pixels,
) -> gpui::Stateful<gpui::Div> {
    let width = px(228.0);
    let left = position.x.clamp(px(8.0), viewport.width - width - px(8.0));
    let top = position
        .y
        .clamp(px(8.0), viewport.height - height - px(8.0));
    div()
        .id(id)
        .role(Role::Menu)
        .aria_label("Explorer Actions")
        .absolute()
        .top(top)
        .left(left)
        .w(width)
        .rounded_lg()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_raised())
        .shadow_lg()
        .p_1()
}

fn explorer_menu_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::MenuItem)
        .aria_label(label)
        .flex()
        .items_center()
        .h(px(30.0))
        .px_2()
        .gap_2()
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface()))
        .child(icon(icon_kind, 16.0, theme::text_muted()))
        .child(label)
}

fn explorer_menu_divider() -> gpui::Div {
    div().h(px(1.0)).my_1().bg(theme::border_subtle())
}
