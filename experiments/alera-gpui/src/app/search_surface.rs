use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, MouseButton, ParentElement as _, SharedString,
    Styled as _, Window,
};
use std::time::Duration;

use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;
use crate::workspace_service::SearchOptions;

impl AleraApp {
    pub(super) fn schedule_workspace_search(&mut self, cx: &mut Context<Self>) {
        self.search_input_generation += 1;
        let generation = self.search_input_generation;
        cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(Duration::from_millis(250))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation == this.search_input_generation {
                    this.search_workspace(cx);
                }
            });
        })
        .detach();
    }

    fn current_search_options(&self, cx: &Context<Self>) -> Option<SearchOptions> {
        let workspace_path = self.selected_workspace_path()?;
        let query = self.search_input.read(cx).value().trim().to_string();
        if query.is_empty() {
            return None;
        }
        Some(SearchOptions {
            workspace_path,
            query,
            case_sensitive: self.search_case_sensitive,
            whole_word: self.search_whole_word,
            use_regex: self.search_use_regex,
            include_pattern: optional_search_value(&self.search_include_input, cx),
            exclude_pattern: optional_search_value(&self.search_exclude_input, cx),
            include_ignored: self.search_include_ignored,
        })
    }

    pub(super) fn search_workspace(&mut self, cx: &mut Context<Self>) {
        let Some(options) = self.current_search_options(cx) else {
            self.search_results = Default::default();
            self.local_message = None;
            cx.notify();
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.replace_confirmation = None;
        let service = self.workspace_service.clone();
        let replacement = self.replace_input.read(cx).value().to_string();
        let preserve_case = self.search_preserve_case;
        cx.spawn(async move |this, cx| {
            let result = if replacement.is_empty() {
                service.search(options).await
            } else {
                service
                    .preview_replace(options, replacement, preserve_case)
                    .await
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(results) => {
                        this.search_collapsed_result_paths.clear();
                        this.search_results = results;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn request_replace(&mut self, match_ids: Vec<String>, cx: &mut Context<Self>) {
        let Some(options) = self.current_search_options(cx) else {
            self.local_message = Some("Enter A Search Query".into());
            cx.notify();
            return;
        };
        if match_ids.is_empty() && self.search_results.truncated {
            self.local_message =
                Some("Replace All Is Unavailable While Results Are Truncated".into());
            cx.notify();
            return;
        }
        let replacement = self.replace_input.read(cx).value().to_string();
        let replace_all = match_ids.is_empty();
        let confirmation = (
            options.query.clone(),
            replacement.clone(),
            self.search_results.total_matches,
        );
        if replace_all && self.replace_confirmation.as_ref() != Some(&confirmation) {
            self.replace_confirmation = Some(confirmation);
            self.local_message = Some(
                format!(
                    "Confirm Replacing {} Matches By Clicking Replace All Again",
                    self.search_results.total_matches
                )
                .into(),
            );
            cx.notify();
            return;
        }

        let expected_files = self
            .search_results
            .files
            .iter()
            .filter(|file| {
                replace_all || file.matches.iter().any(|item| match_ids.contains(&item.id))
            })
            .map(|file| (file.relative_path.clone(), file.content_token.clone()))
            .collect::<Vec<_>>();
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        let preserve_case = self.search_preserve_case;
        cx.spawn(async move |this, cx| {
            let result = if replace_all {
                service
                    .replace_all(options, replacement, preserve_case)
                    .await
            } else {
                service
                    .replace_matches(
                        options,
                        replacement,
                        preserve_case,
                        match_ids,
                        expected_files,
                    )
                    .await
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                this.replace_confirmation = None;
                match result {
                    Ok(summary) => {
                        this.local_message = Some(
                            format!(
                                "Replaced {} Matches In {} Files{}",
                                summary.matches_replaced,
                                summary.files_changed,
                                if summary.conflicts.is_empty() {
                                    String::new()
                                } else {
                                    format!(", {} Conflicts", summary.conflicts.len())
                                }
                            )
                            .into(),
                        );
                        this.search_workspace(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn clear_search(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        for input in [
            &self.search_input,
            &self.replace_input,
            &self.search_include_input,
            &self.search_exclude_input,
        ] {
            input.update(cx, |input, cx| input.set_value("", window, cx));
        }
        self.search_results = Default::default();
        self.search_collapsed_result_paths.clear();
        self.replace_confirmation = None;
        self.local_message = None;
        cx.notify();
    }

    pub(super) fn open_search_match(
        &mut self,
        path: String,
        line: u32,
        column: u32,
        match_length: u32,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.pending_editor_cursor = Some((
            path.clone(),
            line.saturating_sub(1) as usize,
            column.saturating_sub(1) as usize,
            match_length as usize,
        ));
        self.open_workspace_file(path, window, cx);
    }

    pub(super) fn render_search_panel(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let has_query = !self.search_input.read(cx).value().trim().is_empty();
        let has_results = !self.search_results.files.is_empty();
        let can_clear = has_query
            || !self.replace_input.read(cx).value().is_empty()
            || !self.search_include_input.read(cx).value().is_empty()
            || !self.search_exclude_input.read(cx).value().is_empty()
            || has_results
            || self.local_busy;
        let collapsible_keys = super::search_surface_rows::search_collapsible_keys(
            &self.search_results.files,
            self.search_view_as_tree,
        );
        let all_collapsed = !collapsible_keys.is_empty()
            && collapsible_keys
                .iter()
                .all(|key| self.search_collapsed_result_paths.contains(key));

        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .min_h_0()
            .child(self.render_search_toolbar(
                can_clear,
                has_query,
                has_results,
                all_collapsed,
                window,
                cx,
            ))
            .child(self.render_search_inputs(cx))
            .when(has_query || self.local_busy || has_results, |panel| {
                panel.child(div().flex_shrink_0().h(px(16.0))).child(
                    div()
                        .flex()
                        .flex_shrink_0()
                        .items_center()
                        .px_2()
                        .pt_2()
                        .pb_2()
                        .text_size(px(12.0))
                        .text_color(theme::text_muted())
                        .when(self.local_busy, |row| {
                            row.child(loading_indicator(13.0, theme::text_muted()))
                        })
                        .child(if self.local_busy {
                            SharedString::from("Searching...")
                        } else {
                            let match_word = if self.search_results.total_matches == 1 {
                                "match"
                            } else {
                                "matches"
                            };
                            let file_word = if self.search_results.files.len() == 1 {
                                "file"
                            } else {
                                "files"
                            };
                            SharedString::from(format!(
                                "{} {} in {} {}{}",
                                self.search_results.total_matches,
                                match_word,
                                self.search_results.files.len(),
                                file_word,
                                if self.search_results.truncated {
                                    " shown"
                                } else {
                                    ""
                                }
                            ))
                        }),
                )
            })
            .child(div().flex_shrink_0().h(px(1.0)).bg(theme::border_subtle()))
            .child(self.render_search_results(cx))
            .into_any_element()
    }

    fn render_search_toolbar(
        &self,
        can_clear: bool,
        has_query: bool,
        has_results: bool,
        all_collapsed: bool,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .flex()
            .flex_shrink_0()
            .items_center()
            .h(px(44.0))
            .px_2()
            .child(
                div()
                    .text_size(px(13.0))
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Search"),
            )
            .child(div().flex_1())
            .child(
                design_system::icon_button(
                    "clear-search-results",
                    AleraIcon::Close,
                    can_clear,
                    24.0,
                    None,
                    None,
                )
                .when(can_clear, |button| {
                    button.on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| this.clear_search(window, cx)),
                    )
                }),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "toggle-search-ignored",
                    if self.search_include_ignored {
                        AleraIcon::Visible
                    } else {
                        AleraIcon::Hidden
                    },
                    true,
                    24.0,
                    self.search_include_ignored
                        .then_some(theme::surface_raised()),
                    self.search_include_ignored.then_some(theme::border()),
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(|this, _, _, cx| {
                        this.search_include_ignored = !this.search_include_ignored;
                        if !this.search_input.read(cx).value().trim().is_empty() {
                            this.search_workspace(cx);
                        } else {
                            cx.notify();
                        }
                    }),
                ),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "toggle-search-tree",
                    if self.search_view_as_tree {
                        AleraIcon::List
                    } else {
                        AleraIcon::GitGraph
                    },
                    true,
                    24.0,
                    None,
                    None,
                )
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(|this, _, _, cx| {
                        this.search_view_as_tree = !this.search_view_as_tree;
                        this.search_collapsed_result_paths.clear();
                        cx.notify();
                    }),
                ),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "toggle-all-search-results",
                    if all_collapsed {
                        AleraIcon::ExpandAll
                    } else {
                        AleraIcon::CollapseAll
                    },
                    has_results,
                    24.0,
                    None,
                    None,
                )
                .when(has_results, |button| {
                    button.on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            this.search_collapsed_result_paths.clear();
                            if !all_collapsed {
                                this.search_collapsed_result_paths.extend(
                                    super::search_surface_rows::search_collapsible_keys(
                                        &this.search_results.files,
                                        this.search_view_as_tree,
                                    ),
                                );
                            }
                            cx.notify();
                        }),
                    )
                }),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "refresh-search",
                    if self.local_busy {
                        AleraIcon::Loading
                    } else {
                        AleraIcon::Refresh
                    },
                    has_query && !self.local_busy,
                    24.0,
                    None,
                    None,
                )
                .when(has_query && !self.local_busy, |button| {
                    button.on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.search_workspace(cx)),
                    )
                }),
            )
            .into_any_element()
    }

    fn render_search_inputs(&self, cx: &mut Context<Self>) -> AnyElement {
        let details_active = self.search_details_expanded
            || !self.search_include_input.read(cx).value().is_empty()
            || !self.search_exclude_input.read(cx).value().is_empty();
        div()
            .flex()
            .flex_col()
            .flex_shrink_0()
            .pt_2()
            .pr_2()
            .pb_2()
            .pl(px(4.0))
            .child(
                div()
                    .flex()
                    .items_center()
                    .child(
                        div()
                            .id("toggle-search-replace")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(16.0))
                            .h(px(16.0))
                            .cursor(CursorStyle::PointingHand)
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.search_replace_expanded = !this.search_replace_expanded;
                                    this.replace_confirmation = None;
                                    cx.notify();
                                }),
                            )
                            .child(icon(
                                if self.search_replace_expanded {
                                    AleraIcon::ChevronDown
                                } else {
                                    AleraIcon::ChevronRight
                                },
                                16.0,
                                theme::text_muted(),
                            )),
                    )
                    .child(div().w(px(2.0)))
                    .child(
                        div()
                            .flex_1()
                            .flex()
                            .flex_col()
                            .child(
                                design_system::dense_text_field(&self.search_input, None).suffix(
                                    search_input_actions(vec![
                                        search_toggle(
                                            "search-case",
                                            "Aa",
                                            self.search_case_sensitive,
                                            true,
                                        )
                                        .on_mouse_down(
                                            MouseButton::Left,
                                            cx.listener(|this, _, _, cx| {
                                                this.search_case_sensitive =
                                                    !this.search_case_sensitive;
                                                this.search_workspace(cx);
                                            }),
                                        )
                                        .into_any_element(),
                                        search_toggle(
                                            "search-word",
                                            "ab",
                                            self.search_whole_word,
                                            true,
                                        )
                                        .on_mouse_down(
                                            MouseButton::Left,
                                            cx.listener(|this, _, _, cx| {
                                                this.search_whole_word = !this.search_whole_word;
                                                this.search_workspace(cx);
                                            }),
                                        )
                                        .into_any_element(),
                                        search_toggle(
                                            "search-regex",
                                            ".*",
                                            self.search_use_regex,
                                            true,
                                        )
                                        .on_mouse_down(
                                            MouseButton::Left,
                                            cx.listener(|this, _, _, cx| {
                                                this.search_use_regex = !this.search_use_regex;
                                                this.search_workspace(cx);
                                            }),
                                        )
                                        .into_any_element(),
                                    ]),
                                ),
                            )
                            .when(self.search_replace_expanded, |inputs| {
                                let can_replace = self.search_results.total_matches > 0
                                    && !self.local_busy
                                    && !self.search_results.truncated;
                                inputs.child(div().h(px(4.0))).child(
                                    design_system::dense_text_field(&self.replace_input, None)
                                        .suffix(search_input_actions(vec![
                                            search_toggle(
                                                "search-preserve-case",
                                                "AB",
                                                self.search_preserve_case,
                                                true,
                                            )
                                            .on_mouse_down(
                                                MouseButton::Left,
                                                cx.listener(|this, _, _, cx| {
                                                    this.search_preserve_case =
                                                        !this.search_preserve_case;
                                                    this.replace_confirmation = None;
                                                    this.search_workspace(cx);
                                                }),
                                            )
                                            .into_any_element(),
                                            search_icon_button(
                                                "replace-all-search-results",
                                                AleraIcon::CheckCheck,
                                                can_replace,
                                                false,
                                            )
                                            .when(can_replace, |button| {
                                                button.on_mouse_down(
                                                    MouseButton::Left,
                                                    cx.listener(|this, _, _, cx| {
                                                        this.request_replace(Vec::new(), cx);
                                                    }),
                                                )
                                            })
                                            .into_any_element(),
                                        ])),
                                )
                            }),
                    ),
            )
            .child(
                div().flex().justify_end().child(
                    search_icon_button(
                        "toggle-search-details",
                        AleraIcon::More,
                        true,
                        details_active,
                    )
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, _, cx| {
                            this.search_details_expanded = !this.search_details_expanded;
                            cx.notify();
                        }),
                    ),
                ),
            )
            .when(self.search_details_expanded, |inputs| {
                inputs
                    .child(
                        design_system::dense_text_field(&self.search_include_input, None).suffix(
                            search_input_actions(vec![search_icon_button(
                                "search-include-hint",
                                AleraIcon::LayoutGrid,
                                false,
                                false,
                            )
                            .into_any_element()]),
                        ),
                    )
                    .child(div().h(px(6.0)))
                    .child(
                        design_system::dense_text_field(&self.search_exclude_input, None).suffix(
                            search_input_actions(vec![search_icon_button(
                                "search-exclude-hint",
                                AleraIcon::TextSearch,
                                false,
                                false,
                            )
                            .into_any_element()]),
                        ),
                    )
            })
            .into_any_element()
    }
}

fn optional_search_value(
    input: &gpui::Entity<gpui_component::input::InputState>,
    cx: &Context<AleraApp>,
) -> Option<String> {
    let value = input.read(cx).value().trim().to_string();
    (!value.is_empty()).then_some(value)
}

fn toolbar_gap() -> gpui::Div {
    div().w(px(2.0))
}

fn search_input_actions(children: Vec<AnyElement>) -> AnyElement {
    div()
        .flex()
        .items_center()
        .gap(px(2.0))
        .pr_1()
        .children(children)
        .into_any_element()
}

pub(super) fn search_toggle(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
    selected: bool,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(px(24.0))
        .h(px(24.0))
        .rounded(px(4.0))
        .text_size(px(11.0))
        .font_weight(if selected {
            gpui::FontWeight::BOLD
        } else {
            gpui::FontWeight::SEMIBOLD
        })
        .text_color(if enabled {
            if selected {
                theme::text()
            } else {
                theme::text_muted()
            }
        } else {
            theme::text_faint()
        })
        .when(selected, |button| {
            button
                .bg(theme::surface_raised())
                .border_1()
                .border_color(theme::border())
        })
        .when(enabled, |button| {
            button
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_selected()))
        })
        .child(label.into())
}

pub(super) fn search_icon_button(
    id: impl Into<gpui::ElementId>,
    icon_kind: AleraIcon,
    enabled: bool,
    selected: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .w(px(24.0))
        .h(px(24.0))
        .rounded(px(4.0))
        .when(selected, |button| {
            button
                .bg(theme::surface_raised())
                .border_1()
                .border_color(theme::border())
        })
        .when(enabled, |button| {
            button
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_selected()))
        })
        .child(icon(
            icon_kind,
            14.0,
            if enabled {
                if selected {
                    theme::text()
                } else {
                    theme::text_muted()
                }
            } else {
                theme::text_faint()
            },
        ))
}
