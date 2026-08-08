use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, MouseButton, MouseDownEvent, ParentElement as _, Pixels,
    Point, SharedString, Size, Styled as _, Window,
};

use super::{AleraApp, WorkbenchMenu};
use crate::model::WorkbenchSplitDirection;
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_new_tab_button(
        &self,
        group_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let group_id = group_id.to_string();
        div()
            .id(SharedString::from(format!("layout-new-tab-{group_id}")))
            .flex()
            .flex_shrink_0()
            .items_center()
            .justify_center()
            .w(px(28.0))
            .h(px(28.0))
            .rounded_md()
            .text_color(theme::text_muted())
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    this.workbench_menu = Some(WorkbenchMenu::NewTab {
                        group_id: group_id.clone(),
                        position: event.position,
                    });
                    cx.notify();
                }),
            )
            .child(icon(AleraIcon::Add, 16.0, theme::text_muted()))
            .into_any_element()
    }

    pub(super) fn render_pane_menu_button(
        &self,
        group_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let group_id = group_id.to_string();
        div()
            .id(SharedString::from(format!("pane-actions-{group_id}")))
            .flex()
            .flex_shrink_0()
            .items_center()
            .justify_center()
            .w(px(28.0))
            .h(px(28.0))
            .rounded_md()
            .text_color(theme::text_muted())
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    this.workbench_menu = Some(WorkbenchMenu::Pane {
                        group_id: group_id.clone(),
                        position: event.position,
                    });
                    cx.notify();
                }),
            )
            .child(icon(AleraIcon::More, 16.0, theme::text_muted()))
            .into_any_element()
    }

    pub(super) fn open_tab_context_menu(
        &mut self,
        group_id: String,
        tab_id: String,
        position: Point<Pixels>,
        cx: &mut Context<Self>,
    ) {
        self.workbench_menu = Some(WorkbenchMenu::Tab {
            group_id,
            tab_id,
            position,
        });
        cx.notify();
    }

    pub(super) fn render_workbench_menu(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let menu = match self.workbench_menu.clone() {
            Some(WorkbenchMenu::NewTab { group_id, position }) => {
                self.render_new_tab_menu(group_id, position, window.viewport_size(), cx)
            }
            Some(WorkbenchMenu::Pane { group_id, position }) => {
                self.render_pane_actions_menu(group_id, position, window.viewport_size(), cx)
            }
            Some(WorkbenchMenu::Tab {
                group_id,
                tab_id,
                position,
            }) => {
                self.render_tab_context_menu(group_id, tab_id, position, window.viewport_size(), cx)
            }
            None => div().into_any_element(),
        };
        div()
            .id("workbench-menu-overlay")
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.dismiss_workbench_menu(cx);
                }),
            )
            .child(menu)
    }

    fn dismiss_workbench_menu(&mut self, cx: &mut Context<Self>) {
        self.workbench_menu = None;
        cx.notify();
    }

    fn render_new_tab_menu(
        &self,
        group_id: String,
        position: Point<Pixels>,
        viewport: Size<Pixels>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        menu_shell("new-tab-menu", position, viewport, px(220.0), px(68.0))
            .child(
                menu_button(
                    "new-tab-terminal",
                    "New Terminal",
                    icon(AleraIcon::Terminal, 16.0, theme::text_muted()),
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        if let Some(layout) = this.snapshot.layout.as_mut() {
                            layout.active_group_id = group_id.clone();
                        }
                        this.workbench_menu = None;
                        this.create_terminal_tab(cx);
                    }),
                ),
            )
            .child(menu_button(
                "new-tab-mobile-emulator",
                "New Mobile Emulator",
                icon(AleraIcon::MobileDevice, 16.0, theme::text_faint()),
                false,
            ))
            .into_any_element()
    }

    fn render_pane_actions_menu(
        &self,
        group_id: String,
        position: Point<Pixels>,
        viewport: Size<Pixels>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let can_merge = self
            .snapshot
            .layout
            .as_ref()
            .is_some_and(|layout| layout.groups.len() > 1);
        let height = if can_merge { px(168.0) } else { px(132.0) };
        let mut menu = menu_shell("pane-actions-menu", position, viewport, px(190.0), height);
        for (label, direction) in [
            ("Split Right", WorkbenchSplitDirection::Right),
            ("Split Down", WorkbenchSplitDirection::Down),
            ("Split Left", WorkbenchSplitDirection::Left),
            ("Split Up", WorkbenchSplitDirection::Up),
        ] {
            let target_group_id = group_id.clone();
            menu = menu.child(
                menu_button(
                    SharedString::from(format!("pane-{label}")),
                    label,
                    split_direction_glyph(direction),
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        this.workbench_menu = None;
                        this.split_pane_with_terminal(target_group_id.clone(), direction, cx);
                    }),
                ),
            );
        }
        if can_merge {
            let target_group_id = group_id;
            menu = menu.child(menu_divider()).child(
                menu_button(
                    "pane-close-split",
                    "Close Split",
                    div().w(px(16.0)).into_any_element(),
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        this.workbench_menu = None;
                        this.merge_pane_group(target_group_id.clone(), cx);
                    }),
                ),
            );
        }
        menu.into_any_element()
    }

    fn render_tab_context_menu(
        &self,
        group_id: String,
        tab_id: String,
        position: Point<Pixels>,
        viewport: Size<Pixels>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let group_tab_ids = self
            .snapshot
            .layout
            .as_ref()
            .and_then(|layout| layout.groups.get(&group_id))
            .map(|group| group.tab_ids.clone())
            .unwrap_or_else(|| {
                // The legacy flat tab bar has no persisted layout yet. Treat
                // all workspace tabs as one pane so its context menu exposes
                // the same actions as the split-aware tab strip.
                self.snapshot
                    .tabs
                    .iter()
                    .map(|tab| tab.id.clone())
                    .collect()
            });
        let tab_index = group_tab_ids
            .iter()
            .position(|candidate| candidate == &tab_id);
        let close_others = group_tab_ids
            .iter()
            .filter(|candidate| *candidate != &tab_id)
            .cloned()
            .collect::<Vec<_>>();
        let close_right: Vec<String> = tab_index
            .map(|index| group_tab_ids.iter().skip(index + 1).cloned().collect())
            .unwrap_or_default();
        let mut menu = menu_shell("tab-context-menu", position, viewport, px(238.0), px(276.0));
        for (label, direction) in [
            ("Split Up", WorkbenchSplitDirection::Up),
            ("Split Down", WorkbenchSplitDirection::Down),
            ("Split Left", WorkbenchSplitDirection::Left),
            ("Split Right", WorkbenchSplitDirection::Right),
        ] {
            let target_group_id = group_id.clone();
            menu = menu.child(
                menu_button(
                    SharedString::from(format!("tab-{label}")),
                    label,
                    split_direction_glyph(direction),
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        this.workbench_menu = None;
                        this.split_pane_with_terminal(target_group_id.clone(), direction, cx);
                    }),
                ),
            );
        }
        let close_id = tab_id.clone();
        let close_other_ids = close_others.clone();
        let close_right_ids = close_right.clone();
        let rename_id = tab_id;
        menu.child(menu_divider())
            .child(
                menu_button(
                    "tab-close",
                    "Close",
                    icon(AleraIcon::Close, 16.0, theme::text_muted()),
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        this.workbench_menu = None;
                        this.request_close_tab(close_id.clone(), cx);
                    }),
                ),
            )
            .child(
                menu_button(
                    "tab-close-others",
                    "Close Others",
                    icon(
                        AleraIcon::AppWindow,
                        16.0,
                        if close_others.is_empty() {
                            theme::text_faint()
                        } else {
                            theme::text_muted()
                        },
                    ),
                    !close_others.is_empty(),
                )
                .when(!close_others.is_empty(), |row| {
                    row.on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.workbench_menu = None;
                            this.request_close_tabs(close_other_ids.clone(), cx);
                        }),
                    )
                }),
            )
            .child(
                menu_button(
                    "tab-close-right",
                    "Close Tabs to the Right",
                    icon(
                        AleraIcon::ArrowRightToLine,
                        16.0,
                        if close_right.is_empty() {
                            theme::text_faint()
                        } else {
                            theme::text_muted()
                        },
                    ),
                    !close_right.is_empty(),
                )
                .when(!close_right.is_empty(), |row| {
                    row.on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.workbench_menu = None;
                            this.request_close_tabs(close_right_ids.clone(), cx);
                        }),
                    )
                }),
            )
            .child(menu_divider())
            .child(
                menu_button(
                    "tab-change-title",
                    "Change Title",
                    icon(AleraIcon::Edit, 16.0, theme::text_muted()),
                    true,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _, window, cx| {
                        cx.stop_propagation();
                        this.workbench_menu = None;
                        this.open_tab_rename_dialog(rename_id.clone(), window, cx);
                    }),
                ),
            )
            .into_any_element()
    }
}

fn menu_shell(
    id: &'static str,
    position: Point<Pixels>,
    viewport: Size<Pixels>,
    width: Pixels,
    height: Pixels,
) -> gpui::Stateful<gpui::Div> {
    let left = position
        .x
        .clamp(px(8.0), (viewport.width - width - px(8.0)).max(px(8.0)));
    let top =
        (position.y + px(4.0)).clamp(px(8.0), (viewport.height - height - px(8.0)).max(px(8.0)));
    div()
        .id(id)
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

fn menu_button(
    id: impl Into<gpui::ElementId>,
    label: &'static str,
    leading: AnyElement,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .h(px(30.0))
        .px_2()
        .gap_2()
        .rounded_md()
        .text_sm()
        .text_color(if enabled {
            theme::text()
        } else {
            theme::text_faint()
        })
        .cursor(if enabled {
            CursorStyle::PointingHand
        } else {
            CursorStyle::Arrow
        })
        .when(enabled, |row| row.hover(|style| style.bg(theme::surface())))
        .child(div().w(px(16.0)).child(leading))
        .child(label)
}

fn menu_divider() -> gpui::Div {
    div().h(px(1.0)).my_1().bg(theme::border_subtle())
}

fn split_direction_glyph(direction: WorkbenchSplitDirection) -> AnyElement {
    div()
        .relative()
        .w(px(14.0))
        .h(px(14.0))
        .rounded_sm()
        .border_1()
        .border_color(theme::text_muted())
        .overflow_hidden()
        .child(
            div()
                .absolute()
                .bg(theme::text())
                .when(matches!(direction, WorkbenchSplitDirection::Left), |fill| {
                    fill.left_0().top_0().bottom_0().w(px(7.0))
                })
                .when(
                    matches!(direction, WorkbenchSplitDirection::Right),
                    |fill| fill.right_0().top_0().bottom_0().w(px(7.0)),
                )
                .when(matches!(direction, WorkbenchSplitDirection::Up), |fill| {
                    fill.left_0().right_0().top_0().h(px(7.0))
                })
                .when(matches!(direction, WorkbenchSplitDirection::Down), |fill| {
                    fill.left_0().right_0().bottom_0().h(px(7.0))
                }),
        )
        .into_any_element()
}
