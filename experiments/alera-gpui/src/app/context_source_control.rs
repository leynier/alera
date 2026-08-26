use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, StatefulInteractiveElement as _,
    Styled as _,
};
use gpui_component::input::Input;
use gpui_component::tooltip::Tooltip;

use super::context_source_control_actions::{
    source_action_icon, source_action_label, source_icon_button_with_enabled, source_summary,
    SourceControlAction,
};
use super::AleraApp;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_source_control_panel(&self, cx: &mut Context<Self>) -> AnyElement {
        let primary = self.source_control_primary_action(cx);
        let filter = self
            .source_control_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let filtered_changes = self
            .git_snapshot
            .changes
            .iter()
            .filter(|change| filter.is_empty() || change.path.to_lowercase().contains(&filter))
            .collect::<Vec<_>>();
        let empty_message = if filtered_changes.is_empty() && filter.is_empty() {
            "No Changes"
        } else if filtered_changes.is_empty() {
            "No Files Match The Current Filter"
        } else {
            ""
        };
        let all_collapsed = ["staged", "unstaged", "untracked"]
            .into_iter()
            .all(|area| self.source_control_collapsed_sections.contains(area));
        let source_busy = self.local_busy || self.git_snapshot_loading;
        let primary_enabled = !source_busy && self.git_snapshot_error.is_none();

        div()
            .relative()
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .overflow_hidden()
            .child(
                div()
                    .p_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .h(px(26.0))
                            .child(
                                div()
                                    .flex_1()
                                    .text_sm()
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child("Source Control"),
                            )
                            .when(self.selected_source_control_root().is_some(), |toolbar| {
                                toolbar.child(self.source_toolbar_button(
                                    "source-clear-root",
                                    AleraIcon::Close,
                                    false,
                                    cx,
                                ))
                            })
                            .when(
                                self.settings_state.ai_text_enabled || self.source_commit_ai_busy,
                                |toolbar| {
                                    toolbar.child(self.source_toolbar_button(
                                        "source-ai-message",
                                        if self.source_commit_ai_busy {
                                            if self.source_commit_ai_hovered {
                                                AleraIcon::Stop
                                            } else {
                                                AleraIcon::Loading
                                            }
                                        } else {
                                            AleraIcon::Ai
                                        },
                                        false,
                                        cx,
                                    ))
                                },
                            )
                            .child(self.source_toolbar_button(
                                "source-open-all",
                                AleraIcon::Diff,
                                false,
                                cx,
                            ))
                            .child(self.source_toolbar_button(
                                "source-view-mode",
                                if self.source_control_tree_mode {
                                    AleraIcon::List
                                } else {
                                    AleraIcon::GitBranch
                                },
                                false,
                                cx,
                            ))
                            .child(self.source_toolbar_button(
                                "source-filter",
                                AleraIcon::Search,
                                self.source_control_filter_visible,
                                cx,
                            ))
                            .child(self.source_toolbar_button(
                                "source-collapse",
                                if all_collapsed {
                                    AleraIcon::Files
                                } else {
                                    AleraIcon::CollapseAll
                                },
                                false,
                                cx,
                            ))
                            .child(self.source_toolbar_button(
                                "source-refresh",
                                if self.local_busy {
                                    AleraIcon::Loading
                                } else {
                                    AleraIcon::GitRefresh
                                },
                                false,
                                cx,
                            )),
                    )
                    .child(
                        div()
                            .relative()
                            .mt_2()
                            .h(px(64.0))
                            .rounded(px(8.0))
                            .border_1()
                            .border_color(theme::border())
                            .bg(theme::surface())
                            .child(
                                Input::new(&self.commit_input)
                                    .disabled(self.source_commit_ai_busy)
                                    .h_full(),
                            )
                            .when(self.source_commit_ai_busy, |field| {
                                field.child(
                                    div()
                                        .absolute()
                                        .inset_0()
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .rounded(px(8.0))
                                        .bg(theme::overlay_scrim())
                                        .child(
                                            div()
                                                .flex()
                                                .items_center()
                                                .gap_2()
                                                .px_3()
                                                .py_2()
                                                .rounded_md()
                                                .border_1()
                                                .border_color(theme::border())
                                                .bg(theme::surface_raised())
                                                .text_size(px(12.0))
                                                .text_color(theme::text_muted())
                                                .child(icon(
                                                    AleraIcon::Loading,
                                                    14.0,
                                                    theme::text_muted(),
                                                ))
                                                .child("Generating With AI"),
                                        ),
                                )
                            }),
                    )
                    .child(
                        div()
                            .relative()
                            .flex()
                            .items_center()
                            .mt(px(12.0))
                            .h(px(28.0))
                            .rounded(px(8.0))
                            .overflow_hidden()
                            .bg(theme::accent())
                            .text_color(theme::on_accent())
                            .child(
                                div()
                                    .id("source-primary-action")
                                    .flex()
                                    .flex_1()
                                    .items_center()
                                    .justify_center()
                                    .gap(px(6.0))
                                    .cursor(if primary_enabled {
                                        CursorStyle::PointingHand
                                    } else {
                                        CursorStyle::Arrow
                                    })
                                    .when(primary_enabled, |button| {
                                        button
                                            .hover(|style| style.bg(theme::accent_hover()))
                                            .on_mouse_down(
                                                gpui::MouseButton::Left,
                                                cx.listener(move |this, _, window, cx| {
                                                    this.run_source_control_action(
                                                        primary, window, cx,
                                                    );
                                                }),
                                            )
                                    })
                                    .child(icon(
                                        source_action_icon(primary),
                                        13.0,
                                        theme::on_accent(),
                                    ))
                                    .child(source_action_label(primary)),
                            )
                            .child(div().w(px(0.5)).h(px(18.0)).bg(theme::on_accent_divider()))
                            .child(
                                div()
                                    .id("source-primary-menu")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(34.0))
                                    .h_full()
                                    .cursor(if source_busy {
                                        CursorStyle::Arrow
                                    } else {
                                        CursorStyle::PointingHand
                                    })
                                    .when(!source_busy, |button| {
                                        button.hover(|style| style.bg(theme::accent_hover()))
                                    })
                                    .when(!self.source_control_menu_open, |button| {
                                        button.tooltip(|_, cx| {
                                            cx.new(|_| Tooltip::new("Source Control Actions")).into()
                                        })
                                    })
                                    .when(!source_busy, |button| {
                                        button.on_mouse_down(
                                            gpui::MouseButton::Left,
                                            cx.listener(|this, _, _, cx| {
                                                this.source_control_menu_open =
                                                    !this.source_control_menu_open;
                                                cx.notify();
                                            }),
                                        )
                                    })
                                    .child(icon(AleraIcon::ChevronDown, 12.0, theme::on_accent())),
                            ),
                    )
                    .child(
                        div()
                            .mt(px(14.0))
                            .text_size(px(10.0))
                            .text_color(theme::text_faint())
                            .child(source_summary(self)),
                    )
                    .when(self.source_control_filter_visible, |toolbar| {
                        toolbar.child(
                            div()
                                .mt_2()
                                .h(px(32.0))
                                .rounded_md()
                                .border_1()
                                .border_color(theme::border())
                                .child(Input::new(&self.source_control_filter_input).h_full()),
                        )
                    }),
            )
            .child(
                div()
                    .id("source-changes")
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .when(self.git_snapshot_loading, |content| {
                        content
                            .items_center()
                            .justify_center()
                            .gap_2()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(loading_indicator(20.0, theme::text_muted()))
                    })
                    .when(
                        !self.git_snapshot_loading && self.git_snapshot_error.is_some(),
                        |content| {
                            content
                                .items_center()
                                .justify_center()
                                .gap_2()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child(icon(AleraIcon::Error, 15.0, theme::text_muted()))
                                .child(
                                    self.git_snapshot_error
                                        .as_ref()
                                        .cloned()
                                        .unwrap_or_else(|| "Git operation failed.".into()),
                                )
                        },
                    )
                    .when(
                        !self.git_snapshot_loading
                            && self.git_snapshot_error.is_none()
                            && filtered_changes.is_empty(),
                        |content| {
                            content
                                .items_center()
                                .justify_center()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child(empty_message)
                        },
                    )
                    .when(
                        !self.git_snapshot_loading
                            && self.git_snapshot_error.is_none()
                            && !filtered_changes.is_empty(),
                        |content| {
                            content.children(
                                ["staged", "unstaged", "untracked"]
                                    .into_iter()
                                    .enumerate()
                                    .filter_map(|(index, area)| {
                                        self.source_change_group(index, area, &filtered_changes, cx)
                                    }),
                            )
                        },
                    ),
            )
            .when(self.git_history_expanded, |panel| {
                panel.child(self.source_history_resize_handle(cx))
            })
            .child(self.source_history_footer(cx))
            .when(self.git_history_expanded, |panel| {
                panel.child(self.source_history_panel(cx))
            })
            .when(self.source_control_menu_open, |panel| {
                panel.child(self.source_control_menu(cx))
            })
            .when(self.source_history_action_menu.is_some(), |panel| {
                panel.child(self.source_history_action_menu(cx))
            })
            .into_any_element()
    }

    fn source_control_primary_action(&self, cx: &Context<Self>) -> SourceControlAction {
        if self.git_snapshot_loading || self.git_snapshot_error.is_some() {
            return SourceControlAction::Fetch;
        }
        let has_staged = self
            .git_snapshot
            .changes
            .iter()
            .any(|change| change.area.eq_ignore_ascii_case("staged"));
        let has_stageable = self.git_snapshot.changes.iter().any(|change| {
            change.area.eq_ignore_ascii_case("unstaged")
                || change.area.eq_ignore_ascii_case("untracked")
        });
        let has_message = !self.commit_input.read(cx).value().trim().is_empty();
        if has_staged && has_message {
            SourceControlAction::Commit
        } else if self.git_snapshot.has_conflicts {
            SourceControlAction::Fetch
        } else if self.git_snapshot.upstream.is_none() && self.git_snapshot.branch != "HEAD" {
            SourceControlAction::PublishBranch
        } else if self.git_snapshot.ahead > 0 && self.git_snapshot.behind > 0 {
            SourceControlAction::Sync
        } else if self.git_snapshot.behind > 0 {
            SourceControlAction::Pull
        } else if self.git_snapshot.ahead > 0 {
            SourceControlAction::Push
        } else if has_stageable {
            SourceControlAction::StageAll
        } else {
            SourceControlAction::Fetch
        }
    }

    fn source_toolbar_button(
        &self,
        id: &'static str,
        kind: AleraIcon,
        selected: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let enabled = self.source_toolbar_button_enabled(id);
        let button = source_icon_button_with_enabled(id, kind, selected, enabled);
        let ai_busy = self.source_commit_ai_busy;
        let tooltip = source_toolbar_tooltip(id, ai_busy);
        let button = button.when(!self.source_control_menu_open, |button| {
            button.tooltip(move |_, cx| cx.new(|_| Tooltip::new(tooltip)).into())
        });
        match id {
            "source-view-mode" => button
                .when(enabled, |button| {
                    button.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| {
                            this.source_control_tree_mode = !this.source_control_tree_mode;
                            cx.notify();
                        }),
                    )
                })
                .into_any_element(),
            "source-filter" => button
                .when(enabled, |button| {
                    button.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| {
                            this.source_control_filter_visible =
                                !this.source_control_filter_visible;
                            cx.notify();
                        }),
                    )
                })
                .into_any_element(),
            "source-collapse" => button
                .when(enabled, |button| {
                    button.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| {
                            let all_collapsed = ["staged", "unstaged", "untracked"]
                                .into_iter()
                                .all(|area| this.source_control_collapsed_sections.contains(area));
                            if all_collapsed {
                                this.source_control_collapsed_sections.clear();
                            } else {
                                this.source_control_collapsed_sections =
                                    ["staged", "unstaged", "untracked"]
                                        .into_iter()
                                        .map(str::to_owned)
                                        .collect();
                            }
                            cx.notify();
                        }),
                    )
                })
                .into_any_element(),
            "source-refresh" => button
                .when(enabled, |button| {
                    button.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.refresh_git_with_feedback(cx)),
                    )
                })
                .into_any_element(),
            "source-open-all" => button
                .when(enabled, |button| {
                    button.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.open_git_diff_tab(None, None, cx)),
                    )
                })
                .into_any_element(),
            "source-ai-message" => button
                .when(enabled, |button| {
                    button
                        .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                            if this.source_commit_ai_hovered != *hovered {
                                this.source_commit_ai_hovered = *hovered;
                                cx.notify();
                            }
                        }))
                        .on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(|this, _, window, cx| {
                                if this.source_commit_ai_busy {
                                    this.cancel_commit_message_generation(cx);
                                } else {
                                    this.generate_commit_message(window, cx);
                                }
                            }),
                        )
                })
                .into_any_element(),
            "source-clear-root" => button
                .when(enabled, |button| {
                    button.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.clear_source_control_root(cx)),
                    )
                })
                .into_any_element(),
            _ => button.into_any_element(),
        }
    }

    fn source_toolbar_button_enabled(&self, id: &str) -> bool {
        if id == "source-ai-message" {
            if self.source_commit_ai_busy {
                return true;
            }
            let has_staged_changes = self
                .git_snapshot
                .changes
                .iter()
                .any(|change| change.area.eq_ignore_ascii_case("staged"));
            return self.settings_state.ai_text_enabled
                && !self.local_busy
                && !self.git_snapshot_loading
                && self.git_snapshot_error.is_none()
                && !self.git_snapshot.has_conflicts
                && has_staged_changes;
        }
        !(self.local_busy || self.git_snapshot_loading)
    }
}

fn source_toolbar_tooltip(id: &str, ai_busy: bool) -> &'static str {
    match id {
        "source-clear-root" => "Clear Source Control Root",
        "source-ai-message" if ai_busy => "Stop Generating Commit Message",
        "source-ai-message" => "Generate Commit Message With AI",
        "source-open-all" => "Open All Changes",
        "source-view-mode" => "Toggle Tree/List View",
        "source-filter" => "Filter Changes",
        "source-collapse" => "Collapse All",
        "source-refresh" => "Refresh",
        _ => "Source Control",
    }
}

#[cfg(test)]
mod tests {
    use super::source_toolbar_tooltip;

    #[test]
    fn ai_toolbar_tooltip_has_one_stateful_owner() {
        assert_eq!(
            source_toolbar_tooltip("source-ai-message", false),
            "Generate Commit Message With AI"
        );
        assert_eq!(
            source_toolbar_tooltip("source-ai-message", true),
            "Stop Generating Commit Message"
        );
    }
}
