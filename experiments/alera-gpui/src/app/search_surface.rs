use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Toggled, Window,
};
use std::{collections::BTreeSet, time::Duration};

use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;
use crate::workspace_service::{ReplaceSummary, SearchOptions};
use gpui_component::tooltip::Tooltip;

impl AleraApp {
    pub(super) fn schedule_workspace_search(&mut self, cx: &mut Context<Self>) {
        self.cancel_active_workspace_search(cx);
        self.search_input_generation += 1;
        self.search_generation += 1;
        if self.current_search_options(cx).is_none() {
            self.search_busy = false;
            self.search_replacing = false;
            self.search_results = Default::default();
            self.search_error = None;
            self.search_error_is_query_failure = false;
            self.search_collapsed_result_paths.clear();
            cx.notify();
            return;
        }
        // Flutter enters loading as soon as the input changes, including the
        // 250 ms debounce window, and removes results from the previous query.
        self.search_busy = true;
        self.search_replacing = false;
        self.search_results = Default::default();
        self.search_error = None;
        self.search_error_is_query_failure = false;
        self.search_collapsed_result_paths.clear();
        cx.notify();
        let generation = self.search_input_generation;
        cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(Duration::from_millis(250))
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation == this.search_input_generation {
                    this.search_workspace(cx);
                }
            });
        })
        .detach();
    }

    pub(super) fn cancel_active_workspace_search(&mut self, cx: &mut Context<Self>) {
        let Some(request_id) = self.search_active_request_id.take() else {
            return;
        };
        let service = self.workspace_service.clone();
        cx.spawn(async move |_, _| {
            // Older hosts do not expose the additive cancel verb. Stale
            // generations are still ignored, so cancellation stays best effort.
            let _ = service.cancel_search(request_id).await;
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
        self.cancel_active_workspace_search(cx);
        let Some(options) = self.current_search_options(cx) else {
            self.search_generation += 1;
            self.search_busy = false;
            self.search_replacing = false;
            self.search_results = Default::default();
            self.search_error = None;
            self.search_error_is_query_failure = false;
            self.local_message = None;
            cx.notify();
            return;
        };
        self.search_generation += 1;
        let generation = self.search_generation;
        let request_id = format!(
            "gpui:{}:{generation}:{}",
            std::process::id(),
            options.workspace_path
        );
        self.search_active_request_id = Some(request_id.clone());
        self.search_busy = true;
        self.search_replacing = false;
        self.search_error = None;
        self.search_error_is_query_failure = false;
        let service = self.workspace_service.clone();
        let replacement = self.replace_input.read(cx).value().to_string();
        let preserve_case = self.search_preserve_case;
        cx.spawn(async move |this, cx| {
            let result = if replacement.is_empty() {
                service.search(options, request_id.clone()).await
            } else {
                service
                    .preview_replace(options, replacement, preserve_case, request_id.clone())
                    .await
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.search_generation {
                    return;
                }
                if this.search_active_request_id.as_deref() == Some(request_id.as_str()) {
                    this.search_active_request_id = None;
                }
                this.search_busy = false;
                this.search_replacing = false;
                match result {
                    Ok(results) => {
                        this.search_collapsed_result_paths.clear();
                        this.search_results = results;
                        this.search_error = None;
                        this.search_error_is_query_failure = false;
                    }
                    Err(error) => {
                        // Flutter discards stale/partial matches when the search request fails.
                        this.search_results = Default::default();
                        this.search_collapsed_result_paths.clear();
                        this.search_error = Some(error.into());
                        this.search_error_is_query_failure = true;
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn request_replace(&mut self, match_ids: Vec<String>, cx: &mut Context<Self>) {
        if self.search_replacing || self.snapshot.selected_workspace_id != self.selected_workspace_id { return; }
        let Some(workspace_id) = self.selected_workspace_id.clone() else { return; };
        let Some(options) = self.current_search_options(cx) else {
            self.search_error = Some("Enter A Search Query".into());
            self.search_error_is_query_failure = false;
            cx.notify();
            return;
        };
        if match_ids.is_empty() && self.search_results.truncated {
            self.search_error =
                Some("Replace All Is Unavailable While Results Are Truncated".into());
            self.search_error_is_query_failure = false;
            cx.notify();
            return;
        }
        let replacement = self.replace_input.read(cx).value().to_string();
        let replace_all = match_ids.is_empty();

        let affected_paths = self.search_results.files.iter()
            .filter(|file| replace_all || file.matches.iter().any(|item| match_ids.contains(&item.id)))
            .map(|file| file.relative_path.clone()).collect::<BTreeSet<_>>();
        if let Some(message) = self.replacement_blocker(&workspace_id, &affected_paths, cx) {
            let message: SharedString = message.into();
            self.local_message = Some(message.clone());
            self.search_error = Some(message);
            self.search_error_is_query_failure = false;
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
        let match_ids = if replace_all {
            self.search_results
                .files
                .iter()
                .flat_map(|file| file.matches.iter().map(|item| item.id.clone()))
                .collect()
        } else {
            match_ids
        };
        self.search_generation += 1;
        let generation = self.search_generation;
        self.search_busy = true;
        self.search_replacing = true;
        let service = self.workspace_service.clone();
        let preserve_case = self.search_preserve_case;
        let workspace_path = options.workspace_path.clone();
        cx.spawn(async move |this, cx| {
            // Use the exact matches and content tokens from the visible preview.
            // Recomputing the preview here would hide edits made before confirmation.
            let result = service
                .replace_matches(
                    options,
                    replacement,
                    preserve_case,
                    match_ids,
                    expected_files,
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                // Disk mutation completion belongs to its documents even if
                // the user changed the query or workspace while it ran.
                if result.is_ok() {
                    this.reload_replaced_editors(&workspace_id, &workspace_path, &affected_paths, cx);
                }
                if generation != this.search_generation {
                    return;
                }
                this.search_busy = false;
                this.search_replacing = false;
                match result {
                    Ok(summary) => {
                        this.local_message = Some(replace_feedback(&summary).into());
                        this.search_workspace(cx);
                    }
                    Err(error) => {
                        this.search_error = Some(error.into());
                        this.search_error_is_query_failure = false;
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn clear_search(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.cancel_active_workspace_search(cx);
        self.search_generation += 1;
        for input in [
            &self.search_input,
            &self.replace_input,
            &self.search_include_input,
            &self.search_exclude_input,
        ] {
            input.update(cx, |input, cx| input.set_value("", window, cx));
        }
        self.search_results = Default::default();
        self.search_busy = false;
        self.search_replacing = false;
        self.search_error = None;
        self.search_error_is_query_failure = false;
        self.search_collapsed_result_paths.clear();
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
        let Some(workspace) = self.selected_workspace_id.clone() else { return; };
        self.pending_editor_cursor = Some(super::editor_reveal::EditorReveal {
            key: super::editor_requests::EditorKey { workspace, path: path.clone() },
            line: line.saturating_sub(1) as usize,
            column: column.saturating_sub(1) as usize,
            length: match_length as usize,
            invoking_focus: window.focused(cx),
        });
        self.open_search_result_tab(path.clone(), cx);
        if self.editor_documents.contains_key(&path) {
            self.apply_pending_editor_reveal(window, cx);
        } else if self.editor_loading_path.as_deref() != Some(path.as_str()) {
            self.load_workspace_file(path, window, cx);
        }
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
            || self.search_busy;
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
            .when(has_query || self.search_busy || has_results, |panel| {
                panel.child(
                    div()
                        .flex()
                        .flex_shrink_0()
                        .items_center()
                        .px_2()
                        .pt_2()
                        .pb_2()
                        .text_size(px(12.0))
                        .text_color(theme::text_muted())
                        .child(if self.search_busy {
                            if self.search_replacing {
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
                            } else {
                                SharedString::from("Searching...")
                            }
                        } else if self.search_error_is_query_failure {
                            // Flutter keeps the summary row neutral when the query cannot be
                            // parsed, instead of exposing a misleading zero-match count.
                            SharedString::from("No results")
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
                        })
                        .when(self.search_replacing, |row| {
                            row.child(div().flex_1())
                                .child(loading_indicator(16.0, theme::text_muted()))
                        }),
                )
            })
            .child(div().flex_shrink_0().h(px(1.0)).bg(theme::border_subtle()))
            .when_some(self.search_error.clone(), |panel, error| {
                panel.child(
                    div()
                        .flex_shrink_0()
                        .px_2()
                        .pb_2()
                        .text_size(px(12.0))
                        .text_color(theme::danger())
                        .child(error),
                )
            })
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
                    "Clear search results",
                    AleraIcon::Close,
                    can_clear,
                    30.0,
                    None,
                    None,
                )
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Clear search results")).into())
                .when(can_clear, |button| {
                    button
                        .on_click(cx.listener(|this, _, window, cx| this.clear_search(window, cx)))
                }),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "toggle-search-ignored",
                    if self.search_include_ignored {
                        "Ignore ignored files"
                    } else {
                        "Search ignored files"
                    },
                    if self.search_include_ignored {
                        AleraIcon::Visible
                    } else {
                        AleraIcon::Hidden
                    },
                    true,
                    30.0,
                    self.search_include_ignored
                        .then_some(theme::surface_raised()),
                    self.search_include_ignored.then_some(theme::border()),
                )
                .tooltip({
                    let label = if self.search_include_ignored {
                        "Ignore ignored files"
                    } else {
                        "Search ignored files"
                    };
                    move |_, cx| {
                        let label = label.to_owned();
                        cx.new(move |_| Tooltip::new(label)).into()
                    }
                })
                .on_click(cx.listener(|this, _, _, cx| {
                    this.search_include_ignored = !this.search_include_ignored;
                    if !this.search_input.read(cx).value().trim().is_empty() {
                        this.search_workspace(cx);
                    } else {
                        cx.notify();
                    }
                })),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "toggle-search-tree",
                    if self.search_view_as_tree {
                        "View as list"
                    } else {
                        "View as tree"
                    },
                    if self.search_view_as_tree {
                        AleraIcon::List
                    } else {
                        AleraIcon::GitGraph
                    },
                    true,
                    30.0,
                    None,
                    None,
                )
                .tooltip({
                    let label = if self.search_view_as_tree {
                        "View as list"
                    } else {
                        "View as tree"
                    };
                    move |_, cx| {
                        let label = label.to_owned();
                        cx.new(move |_| Tooltip::new(label)).into()
                    }
                })
                .on_click(cx.listener(|this, _, _, cx| {
                    this.search_view_as_tree = !this.search_view_as_tree;
                    this.search_collapsed_result_paths.clear();
                    cx.notify();
                })),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "toggle-all-search-results",
                    if all_collapsed {
                        "Expand All"
                    } else {
                        "Collapse All"
                    },
                    if all_collapsed {
                        AleraIcon::ExpandAll
                    } else {
                        AleraIcon::CollapseAll
                    },
                    has_results,
                    30.0,
                    None,
                    None,
                )
                .tooltip({
                    let label = if all_collapsed {
                        "Expand All"
                    } else {
                        "Collapse All"
                    };
                    move |_, cx| {
                        let label = label.to_owned();
                        cx.new(move |_| Tooltip::new(label)).into()
                    }
                })
                .when(has_results, |button| {
                    button.on_click(cx.listener(move |this, _, _, cx| {
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
                    }))
                }),
            )
            .child(toolbar_gap())
            .child(
                design_system::icon_button(
                    "refresh-search",
                    "Refresh",
                    if self.search_busy {
                        AleraIcon::Loading
                    } else {
                        AleraIcon::Refresh
                    },
                    has_query && !self.search_busy,
                    30.0,
                    None,
                    None,
                )
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh")).into())
                .when(has_query && !self.search_busy, |button| {
                    button.on_click(cx.listener(|this, _, _, cx| this.search_workspace(cx)))
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
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label(if self.search_replace_expanded {
                                "Hide replace"
                            } else {
                                "Show replace"
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(16.0))
                            .h(px(16.0))
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.search_replace_expanded = !this.search_replace_expanded;
                                cx.notify();
                            }))
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
                                            "Match case",
                                        )
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            this.search_case_sensitive =
                                                !this.search_case_sensitive;
                                            this.search_workspace(cx);
                                        }))
                                        .into_any_element(),
                                        search_toggle(
                                            "search-word",
                                            "ab",
                                            self.search_whole_word,
                                            true,
                                            "Match whole word",
                                        )
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            this.search_whole_word = !this.search_whole_word;
                                            this.search_workspace(cx);
                                        }))
                                        .into_any_element(),
                                        search_toggle(
                                            "search-regex",
                                            ".*",
                                            self.search_use_regex,
                                            true,
                                            "Use regular expression",
                                        )
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            this.search_use_regex = !this.search_use_regex;
                                            this.search_workspace(cx);
                                        }))
                                        .into_any_element(),
                                    ]),
                                ),
                            )
                            .when(self.search_replace_expanded, |inputs| {
                                let can_replace = self.search_results.total_matches > 0
                                    && !self.search_busy
                                    && !self.search_results.truncated;
                                inputs.child(div().h(px(4.0))).child(
                                    design_system::dense_text_field(&self.replace_input, None)
                                        .suffix(search_input_actions(vec![
                                            search_toggle(
                                                "search-preserve-case",
                                                "AB",
                                                self.search_preserve_case,
                                                true,
                                                "Preserve case",
                                            )
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.search_preserve_case =
                                                    !this.search_preserve_case;
                                                this.search_workspace(cx);
                                            }))
                                            .into_any_element(),
                                            search_icon_button(
                                                "replace-all-search-results",
                                                AleraIcon::CheckCheck,
                                                can_replace,
                                                false,
                                                "Replace all",
                                            )
                                            .when(can_replace, |button| {
                                                button.on_click(cx.listener(|this, _, _, cx| {
                                                    this.request_replace(Vec::new(), cx);
                                                }))
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
                        if details_active {
                            "Hide details"
                        } else {
                            "Show details"
                        },
                    )
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.search_details_expanded = !this.search_details_expanded;
                        cx.notify();
                    })),
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
                                "Files to include",
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
                                "Files to exclude",
                            )
                            .into_any_element()]),
                        ),
                    )
            })
            .into_any_element()
    }
}

fn replace_feedback(summary: &ReplaceSummary) -> String {
    if summary.conflicts.is_empty() {
        let match_word = if summary.matches_replaced == 1 {
            "match"
        } else {
            "matches"
        };
        return format!("Replaced {} {match_word}.", summary.matches_replaced);
    }

    let skipped = summary
        .conflicts
        .iter()
        .map(|conflict| conflict.relative_path.as_str())
        .collect::<BTreeSet<_>>()
        .len();
    let skipped_files = if skipped == 1 {
        "1 file".to_string()
    } else {
        format!("{skipped} files")
    };
    let first = &summary.conflicts[0];
    let first_reason = format!("{}: {}", first.relative_path, first.reason);
    if summary.matches_replaced > 0 {
        let match_word = if summary.matches_replaced == 1 {
            "match"
        } else {
            "matches"
        };
        format!(
            "Replaced {} {match_word}. {skipped_files} skipped. {first_reason}",
            summary.matches_replaced
        )
    } else {
        format!("Replace skipped {skipped_files}. {first_reason}")
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
    tooltip: impl Into<SharedString>,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    let tooltip = tooltip.into();
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label(tooltip.clone())
        .aria_toggled(if selected {
            Toggled::True
        } else {
            Toggled::False
        })
        .flex()
        .items_center()
        .justify_center()
        .w(px(24.0))
        .h(px(24.0))
        .flex_shrink_0()
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
        .tooltip({
            move |_, cx| {
                let tooltip = tooltip.clone();
                cx.new(move |_| Tooltip::new(tooltip)).into()
            }
        })
        .child(label)
}

pub(super) fn search_icon_button(
    id: impl Into<gpui::ElementId>,
    icon_kind: AleraIcon,
    enabled: bool,
    selected: bool,
    tooltip: impl Into<SharedString>,
) -> gpui::Stateful<gpui::Div> {
    let tooltip = tooltip.into();
    div()
        .id(id)
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label(tooltip.clone())
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
        .tooltip({
            move |_, cx| {
                let tooltip = tooltip.clone();
                cx.new(move |_| Tooltip::new(tooltip)).into()
            }
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

#[cfg(test)]
mod replace_feedback_tests {
    use super::*;
    use crate::workspace_service::ReplaceConflict;

    #[test]
    fn feedback_matches_flutter_for_success_and_conflicts() {
        assert_eq!(
            replace_feedback(&ReplaceSummary {
                matches_replaced: 1,
                conflicts: Vec::new(),
            }),
            "Replaced 1 match."
        );
        assert_eq!(
            replace_feedback(&ReplaceSummary {
                matches_replaced: 0,
                conflicts: vec![ReplaceConflict {
                    relative_path: "note.txt".to_string(),
                    reason: "File changed on disk".to_string(),
                }],
            }),
            "Replace skipped 1 file. note.txt: File changed on disk"
        );
    }
}
