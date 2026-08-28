use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, ClickEvent, Context,
    CursorStyle, InteractiveElement as _, IntoElement, KeyDownEvent, MouseButton,
    ParentElement as _, Pixels, Point, Role, SharedString, Size, StatefulInteractiveElement as _,
    Styled as _, Window,
};
use gpui_component::tooltip::Tooltip;

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
        active_tab_id: Option<&str>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let group_id = group_id.to_string();
        let active_tab_id = active_tab_id.map(str::to_owned);
        div()
            .id(SharedString::from(format!("layout-new-tab-{group_id}")))
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label("New Tab")
            .flex()
            .flex_shrink_0()
            .items_center()
            .justify_center()
            .w(px(28.0))
            .h(px(28.0))
            .rounded_md()
            .text_color(theme::text_muted())
            .cursor(CursorStyle::PointingHand)
            .tooltip(|_, cx| cx.new(|_| Tooltip::new("New Tab")).into())
            .hover(|style| style.bg(theme::surface_raised()))
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                if let Some(active_tab_id) = active_tab_id.clone() {
                    this.selected_tab_id = Some(active_tab_id.clone());
                    if let Some(layout) = this.snapshot.layout.as_mut() {
                        layout.active_group_id = group_id.clone();
                        if let Some(group) = layout.groups.get_mut(&group_id) {
                            group.active_tab_id = Some(active_tab_id);
                        }
                    }
                }
                this.workbench_menu = Some(WorkbenchMenu::NewTab {
                    group_id: group_id.clone(),
                    position: event.position(),
                });
                this.begin_workbench_menu(window, cx);
                cx.notify();
            }))
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
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label("Pane actions")
            .flex()
            .flex_shrink_0()
            .items_center()
            .justify_center()
            .w(px(28.0))
            .h(px(28.0))
            .rounded_md()
            .text_color(theme::text_muted())
            .cursor(CursorStyle::PointingHand)
            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Pane actions")).into())
            .hover(|style| style.bg(theme::surface_raised()))
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                this.workbench_menu = Some(WorkbenchMenu::Pane {
                    group_id: group_id.clone(),
                    position: event.position(),
                });
                this.begin_workbench_menu(window, cx);
                cx.notify();
            }))
            .child(icon(AleraIcon::More, 16.0, theme::text_muted()))
            .into_any_element()
    }

    pub(super) fn open_tab_context_menu(
        &mut self,
        group_id: String,
        tab_id: String,
        position: Point<Pixels>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.workbench_menu = Some(WorkbenchMenu::Tab {
            group_id,
            tab_id,
            position,
        });
        self.begin_workbench_menu(window, cx);
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
            .track_focus(&self.workbench_menu_focus)
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, window, cx| {
                    this.dismiss_workbench_menu(window, cx);
                }),
            )
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                this.handle_workbench_menu_key(event, window, cx);
            }))
            .child(menu)
    }

    fn begin_workbench_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.workbench_menu_previous_focus = window.focused(cx);
        self.workbench_menu_highlighted = self
            .workbench_menu_enabled_indices()
            .first()
            .copied()
            .unwrap_or(0);
        self.workbench_menu_focus.focus(window, cx);
    }

    pub(super) fn dismiss_workbench_menu(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.workbench_menu = None;
        if let Some(focus) = self.workbench_menu_previous_focus.take() {
            focus.focus(window, cx);
        }
        cx.notify();
    }

    fn workbench_menu_enabled_indices(&self) -> Vec<usize> {
        match self.workbench_menu.as_ref() {
            Some(WorkbenchMenu::NewTab { .. }) => vec![0],
            Some(WorkbenchMenu::Pane { .. }) => {
                let mut indices = vec![0, 1, 2, 3];
                if self
                    .snapshot
                    .layout
                    .as_ref()
                    .is_some_and(|layout| layout.groups.len() > 1)
                {
                    indices.push(4);
                }
                indices
            }
            Some(WorkbenchMenu::Tab {
                group_id, tab_id, ..
            }) => {
                let group_tab_ids = self
                    .snapshot
                    .layout
                    .as_ref()
                    .and_then(|layout| layout.groups.get(group_id))
                    .map(|group| group.tab_ids.clone())
                    .unwrap_or_else(|| {
                        self.snapshot
                            .tabs
                            .iter()
                            .map(|tab| tab.id.clone())
                            .collect()
                    });
                let mut indices = vec![0, 1, 2, 3, 4, 7];
                if group_tab_ids.iter().any(|candidate| candidate != tab_id) {
                    indices.push(5);
                }
                if group_tab_ids
                    .iter()
                    .position(|candidate| candidate == tab_id)
                    .is_some_and(|index| index + 1 < group_tab_ids.len())
                {
                    indices.push(6);
                }
                indices.sort_unstable();
                indices
            }
            None => Vec::new(),
        }
    }

    fn handle_workbench_menu_key(
        &mut self,
        event: &KeyDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let key = event.keystroke.key.as_str();
        if key == "escape" {
            self.dismiss_workbench_menu(window, cx);
            cx.stop_propagation();
            return;
        }
        let enabled = self.workbench_menu_enabled_indices();
        if enabled.is_empty() {
            return;
        }
        if matches!(key, "enter" | "space") {
            self.activate_workbench_menu_item(self.workbench_menu_highlighted, window, cx);
            cx.stop_propagation();
            return;
        }
        let current = enabled
            .iter()
            .position(|index| *index == self.workbench_menu_highlighted)
            .unwrap_or(0);
        let next = match key {
            "down" => (current + 1) % enabled.len(),
            "up" => (current + enabled.len() - 1) % enabled.len(),
            "home" => 0,
            "end" => enabled.len() - 1,
            _ => return,
        };
        self.workbench_menu_highlighted = enabled[next];
        cx.notify();
        cx.stop_propagation();
    }

    fn activate_workbench_menu_item(
        &mut self,
        index: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(menu) = self.workbench_menu.clone() else {
            return;
        };
        match menu {
            WorkbenchMenu::NewTab { group_id, .. } if index == 0 => {
                self.dismiss_workbench_menu(window, cx);
                if let Some(layout) = self.snapshot.layout.as_mut() {
                    layout.active_group_id = group_id;
                }
                self.create_terminal_tab(cx);
            }
            WorkbenchMenu::Pane { group_id, .. } => {
                if let Some(direction) = [
                    WorkbenchSplitDirection::Right,
                    WorkbenchSplitDirection::Down,
                    WorkbenchSplitDirection::Left,
                    WorkbenchSplitDirection::Up,
                ]
                .get(index)
                .copied()
                {
                    self.dismiss_workbench_menu(window, cx);
                    self.split_pane_with_terminal(group_id, direction, cx);
                } else if index == 4
                    && self
                        .snapshot
                        .layout
                        .as_ref()
                        .is_some_and(|layout| layout.groups.len() > 1)
                {
                    self.dismiss_workbench_menu(window, cx);
                    self.merge_pane_group(group_id, cx);
                }
            }
            WorkbenchMenu::Tab {
                group_id, tab_id, ..
            } => {
                if let Some(direction) = [
                    WorkbenchSplitDirection::Up,
                    WorkbenchSplitDirection::Down,
                    WorkbenchSplitDirection::Left,
                    WorkbenchSplitDirection::Right,
                ]
                .get(index)
                .copied()
                {
                    self.dismiss_workbench_menu(window, cx);
                    self.split_pane_with_terminal(group_id, direction, cx);
                    return;
                }
                let group_tab_ids = self
                    .snapshot
                    .layout
                    .as_ref()
                    .and_then(|layout| layout.groups.get(&group_id))
                    .map(|group| group.tab_ids.clone())
                    .unwrap_or_else(|| {
                        self.snapshot
                            .tabs
                            .iter()
                            .map(|tab| tab.id.clone())
                            .collect()
                    });
                let tab_position = group_tab_ids
                    .iter()
                    .position(|candidate| candidate == &tab_id);
                let tab_ids = match index {
                    4 => vec![tab_id.clone()],
                    5 => group_tab_ids
                        .iter()
                        .filter(|candidate| *candidate != &tab_id)
                        .cloned()
                        .collect(),
                    6 => tab_position.map_or_else(Vec::new, |position| {
                        group_tab_ids.iter().skip(position + 1).cloned().collect()
                    }),
                    _ => Vec::new(),
                };
                if !tab_ids.is_empty() {
                    self.dismiss_workbench_menu(window, cx);
                    self.request_close_tabs(tab_ids, cx);
                } else if index == 7 {
                    self.dismiss_workbench_menu(window, cx);
                    self.open_tab_rename_dialog(tab_id, window, cx);
                }
            }
            _ => {}
        }
    }

    fn render_new_tab_menu(
        &self,
        group_id: String,
        position: Point<Pixels>,
        viewport: Size<Pixels>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        menu_shell(
            "new-tab-menu",
            "New Tab",
            position,
            viewport,
            px(220.0),
            px(68.0),
        )
        .child(
            menu_button(
                "new-tab-terminal",
                "New Terminal",
                icon(AleraIcon::Terminal, 16.0, theme::text_muted()),
                true,
                self.workbench_menu_highlighted == 0,
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                cx.stop_propagation();
                this.dismiss_workbench_menu(window, cx);
                if let Some(layout) = this.snapshot.layout.as_mut() {
                    layout.active_group_id = group_id.clone();
                }
                this.create_terminal_tab(cx);
            })),
        )
        .child(menu_button(
            "new-tab-mobile-emulator",
            "New Mobile Emulator",
            icon(AleraIcon::MobileDevice, 16.0, theme::text_faint()),
            false,
            self.workbench_menu_highlighted == 1,
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
        let mut menu = menu_shell(
            "pane-actions-menu",
            "Pane actions",
            position,
            viewport,
            px(190.0),
            height,
        );
        for (index, (label, direction)) in [
            ("Split Right", WorkbenchSplitDirection::Right),
            ("Split Down", WorkbenchSplitDirection::Down),
            ("Split Left", WorkbenchSplitDirection::Left),
            ("Split Up", WorkbenchSplitDirection::Up),
        ]
        .into_iter()
        .enumerate()
        {
            let target_group_id = group_id.clone();
            menu = menu.child(
                menu_button(
                    SharedString::from(format!("pane-{label}")),
                    label,
                    split_direction_glyph(direction),
                    true,
                    self.workbench_menu_highlighted == index,
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.dismiss_workbench_menu(window, cx);
                    this.split_pane_with_terminal(target_group_id.clone(), direction, cx);
                })),
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
                    self.workbench_menu_highlighted == 4,
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.dismiss_workbench_menu(window, cx);
                    this.merge_pane_group(target_group_id.clone(), cx);
                })),
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
        let mut menu = menu_shell(
            "tab-context-menu",
            "Tab actions",
            position,
            viewport,
            px(238.0),
            px(276.0),
        );
        for (index, (label, direction)) in [
            ("Split Up", WorkbenchSplitDirection::Up),
            ("Split Down", WorkbenchSplitDirection::Down),
            ("Split Left", WorkbenchSplitDirection::Left),
            ("Split Right", WorkbenchSplitDirection::Right),
        ]
        .into_iter()
        .enumerate()
        {
            let target_group_id = group_id.clone();
            menu = menu.child(
                menu_button(
                    SharedString::from(format!("tab-{label}")),
                    label,
                    split_direction_glyph(direction),
                    true,
                    self.workbench_menu_highlighted == index,
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.dismiss_workbench_menu(window, cx);
                    this.split_pane_with_terminal(target_group_id.clone(), direction, cx);
                })),
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
                    self.workbench_menu_highlighted == 4,
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.dismiss_workbench_menu(window, cx);
                    this.request_close_tab(close_id.clone(), cx);
                })),
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
                    self.workbench_menu_highlighted == 5,
                )
                .when(!close_others.is_empty(), |row| {
                    row.on_click(cx.listener(move |this, _, window, cx| {
                        cx.stop_propagation();
                        this.dismiss_workbench_menu(window, cx);
                        this.request_close_tabs(close_other_ids.clone(), cx);
                    }))
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
                    self.workbench_menu_highlighted == 6,
                )
                .when(!close_right.is_empty(), |row| {
                    row.on_click(cx.listener(move |this, _, window, cx| {
                        cx.stop_propagation();
                        this.dismiss_workbench_menu(window, cx);
                        this.request_close_tabs(close_right_ids.clone(), cx);
                    }))
                }),
            )
            .child(menu_divider())
            .child(
                menu_button(
                    "tab-change-title",
                    "Change Title",
                    icon(AleraIcon::Edit, 16.0, theme::text_muted()),
                    true,
                    self.workbench_menu_highlighted == 7,
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.dismiss_workbench_menu(window, cx);
                    this.open_tab_rename_dialog(rename_id.clone(), window, cx);
                })),
            )
            .into_any_element()
    }
}

fn menu_shell(
    id: &'static str,
    label: &'static str,
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
        .role(Role::Menu)
        .aria_label(label)
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
    highlighted: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::MenuItem)
        .aria_label(label)
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
        .when(highlighted && enabled, |row| row.bg(theme::surface()))
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
