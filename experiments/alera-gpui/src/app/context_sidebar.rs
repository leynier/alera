use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::tooltip::Tooltip;

use super::AleraApp;
use crate::activity::ContextPanel;
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_context_sidebar(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if self.context_sidebar_collapsed {
            return div()
                .flex()
                .flex_col()
                .items_center()
                .flex_shrink_0()
                .w(px(52.0))
                .h_full()
                .border_l_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected())
                .pt_2()
                .gap(px(6.0))
                .children(
                    ContextPanel::ALL
                        .into_iter()
                        .enumerate()
                        .map(|(index, panel)| self.context_panel_button(index, panel, true, cx)),
                )
                .child(div().flex_1())
                .child(
                    div()
                        .id("expand-context-sidebar")
                        .focusable()
                        .tab_stop(true)
                        .role(Role::Button)
                        .aria_label("Expand panel")
                        .flex()
                        .items_center()
                        .justify_center()
                        .w(px(30.0))
                        .h(px(30.0))
                        .mb_2()
                        .rounded_md()
                        .cursor(CursorStyle::PointingHand)
                        .text_color(theme::text_muted())
                        .hover(|style| style.bg(theme::surface_raised()))
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Expand panel")).into())
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.context_sidebar_collapsed = false;
                            this.persist_sidebar_view_prefs(cx);
                            cx.notify();
                        }))
                        .child(icon(AleraIcon::ChevronsLeft, 16.0, theme::text_muted())),
                )
                .into_any_element();
        }

        let body = match self.context_panel {
            ContextPanel::Explorer => self.render_explorer_panel(window, cx),
            ContextPanel::Search => self.render_search_panel(window, cx),
            ContextPanel::SourceControl => self.render_source_control_panel(cx),
            ContextPanel::PullRequest => self.render_pull_request_panel(window, cx),
            ContextPanel::AgentCanvas => self.render_agent_canvas_panel(window, cx),
        };
        div()
            .relative()
            .flex()
            .flex_col()
            .flex_shrink_0()
            .w(px(self.context_sidebar_width))
            .h_full()
            .border_l_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(theme::header_height())
                    .px_2()
                    .gap(px(6.0))
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .children(
                    ContextPanel::ALL
                        .into_iter()
                        .enumerate()
                        .map(|(index, panel)| {
                                self.context_panel_button(index, panel, false, cx)
                            }),
                    )
                    .child(div().flex_1())
                    .child(
                        div()
                            .id("collapse-context-sidebar")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Collapse panel")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(30.0))
                            .h(px(30.0))
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .text_color(theme::text_muted())
                            .hover(|style| style.bg(theme::surface_raised()))
                            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Collapse panel")).into())
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.context_sidebar_collapsed = true;
                                this.persist_sidebar_view_prefs(cx);
                                cx.notify();
                            }))
                            .child(icon(AleraIcon::ChevronsRight, 16.0, theme::text_muted())),
                    ),
            )
            .when(self.context_panel == ContextPanel::Explorer, |sidebar| {
                sidebar.child(self.render_explorer_toolbar(cx))
            })
            .child(body)
            .into_any_element()
    }

    fn context_panel_button(
        &self,
        index: usize,
        panel: ContextPanel,
        _vertical: bool,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let selected = self.context_panel == panel;
        // Keep every panel selectable across workspaces. Source Control and
        // Pull Request render an explanatory empty state when the active
        // workspace has no Git scope, matching Flutter's persistent tabs.
        let enabled = true;
        div()
            .id(("context-panel", index))
            .focusable()
            .tab_stop(enabled)
            .role(Role::Button)
            .aria_label(panel.label())
            .flex()
            .items_center()
            .justify_center()
            .w(px(30.0))
            .h(px(30.0))
            .rounded_md()
            .border_1()
            .border_color(if selected {
                theme::border()
            } else {
                theme::border_subtle()
            })
            .cursor(if enabled {
                CursorStyle::PointingHand
            } else {
                CursorStyle::Arrow
            })
            .text_color(if selected {
                theme::text()
            } else {
                theme::text_muted()
            })
            .hover(|style| style.bg(theme::surface_raised()))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.context_sidebar_collapsed = false;
                this.select_context_panel(panel, cx);
            }))
            .when(selected, |button| button.bg(theme::surface_raised()))
            .tooltip(move |_, cx| cx.new(|_| Tooltip::new(panel.label())).into())
            .child(icon(
                panel.icon(),
                16.0,
                if selected {
                    theme::text()
                } else {
                    theme::text_muted()
                },
            ))
    }

    fn render_explorer_toolbar(&self, cx: &mut Context<Self>) -> AnyElement {
        let title = self
            .selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id))
            .map_or("Explorer", |workspace| workspace.name.as_str());
        div()
            .flex()
            .items_center()
            .h(theme::header_height())
            .px_2()
            .border_b_1()
            .border_color(theme::border_subtle())
            .child(
                div()
                    .flex_1()
                    .overflow_hidden()
                    .text_ellipsis()
                    .text_sm()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(title.to_owned()),
            )
            .child(
                panel_toolbar_button("explorer-new-file", AleraIcon::NewFile, "New file").on_click(
                    cx.listener(|this, _, window, cx| {
                        this.begin_create_explorer_entry(false, window, cx);
                    }),
                ),
            )
            .child(
                panel_toolbar_button("explorer-new-folder", AleraIcon::NewFolder, "New folder")
                    .on_click(cx.listener(|this, _, window, cx| {
                        this.begin_create_explorer_entry(true, window, cx);
                    })),
            )
            .child(
                panel_toolbar_button("explorer-save-all", AleraIcon::Save, "Save all files")
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.save_editor(false, cx);
                    })),
            )
            .child(
                panel_toolbar_button(
                    "explorer-toggle-ignored",
                    if self.explorer_hide_ignored {
                        AleraIcon::Hidden
                    } else {
                        AleraIcon::Visible
                    },
                    if self.explorer_hide_ignored {
                        "Show ignored files"
                    } else {
                        "Hide ignored files"
                    },
                )
                .on_click(cx.listener(|this, _, _, cx| {
                    this.toggle_explorer_ignored_files(cx);
                })),
            )
            .child(
                panel_toolbar_button(
                    "explorer-collapse-all",
                    AleraIcon::CollapseAll,
                    "Collapse All",
                )
                .on_click(cx.listener(|this, _, _, cx| {
                    this.collapse_all_explorer_directories(cx);
                })),
            )
            .child(
                panel_toolbar_button(
                    "explorer-refresh",
                    if self.explorer_busy {
                        AleraIcon::Loading
                    } else {
                        AleraIcon::Refresh
                    },
                    "Refresh",
                )
                .when(!self.explorer_busy, |button| {
                    button.on_click(cx.listener(|this, _, _, cx| {
                        this.refresh_local_activity(cx);
                    }))
                }),
            )
            .into_any_element()
    }
}

fn panel_toolbar_button(
    id: &'static str,
    kind: AleraIcon,
    tooltip: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(tooltip)
        .flex()
        .flex_shrink_0()
        .items_center()
        .justify_center()
        .w(px(30.0))
        .h(px(30.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .tooltip(move |_, cx| cx.new(|_| Tooltip::new(tooltip)).into())
        .child(icon(kind, 16.0, theme::text_muted()))
}
