use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, InteractiveElement as _,
    IntoElement as _, ParentElement as _, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::Input;

use super::AleraApp;
use crate::theme;
use crate::workspace_service::SearchOptions;

impl AleraApp {
    fn current_search_options(&self, cx: &Context<Self>) -> Option<SearchOptions> {
        let workspace_path = self.selected_workspace_path()?;
        let query = self.search_input.read(cx).value().trim().to_string();
        if query.is_empty() {
            return None;
        }
        Some(SearchOptions {
            workspace_path,
            query,
            case_sensitive: false,
            whole_word: false,
            use_regex: false,
            include_pattern: None,
            exclude_pattern: None,
            include_ignored: false,
        })
    }

    fn search_workspace(&mut self, cx: &mut Context<Self>) {
        let Some(options) = self.current_search_options(cx) else {
            self.local_message = Some("Enter A Search Query".into());
            cx.notify();
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.replace_confirmation = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.search(options).await;
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
                        this.local_message =
                            Some(format!("{} Matches", results.total_matches).into());
                        this.search_results = results;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn request_replace_all(&mut self, cx: &mut Context<Self>) {
        let Some(options) = self.current_search_options(cx) else {
            self.local_message = Some("Enter A Search Query".into());
            cx.notify();
            return;
        };
        let replacement = self.replace_input.read(cx).value().to_string();
        let confirmation = (
            options.query.clone(),
            replacement.clone(),
            self.search_results.total_matches,
        );
        if self.replace_confirmation.as_ref() != Some(&confirmation) {
            self.replace_confirmation = Some(confirmation);
            self.local_message = Some(
                format!(
                    "Confirm Replacing {} Matches By Clicking Apply Replace",
                    self.search_results.total_matches
                )
                .into(),
            );
            cx.notify();
            return;
        }

        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.replace_all(options, replacement).await;
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
                        this.search_results = Default::default();
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_search_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let replace_armed = self.replace_confirmation.is_some();
        let result_rows = self
            .search_results
            .files
            .iter()
            .flat_map(|file| {
                let path = file.relative_path.clone();
                file.matches.iter().map(move |item| {
                    (
                        path.clone(),
                        item.line,
                        item.column,
                        item.line_content.clone(),
                        item.replacement_preview.clone(),
                    )
                })
            })
            .enumerate()
            .map(
                |(index, (path, line, column, content, replacement_preview))| {
                    let open_path = path.clone();
                    div()
                        .id(("search-result", index))
                        .flex()
                        .flex_col()
                        .px_3()
                        .py_2()
                        .border_b_1()
                        .border_color(theme::border())
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_selected()))
                        .on_click(cx.listener(move |this, _, window, cx| {
                            this.open_workspace_file(open_path.clone(), window, cx);
                            this.activity = crate::activity::Activity::Explorer;
                            cx.notify();
                        }))
                        .child(
                            div()
                                .text_sm()
                                .text_color(theme::accent())
                                .child(format!("{path}:{line}:{column}")),
                        )
                        .child(
                            div()
                                .font_family("JetBrains Mono")
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child(content),
                        )
                        .when_some(replacement_preview, |row, replacement| {
                            row.child(
                                div()
                                    .font_family("JetBrains Mono")
                                    .text_xs()
                                    .text_color(theme::success())
                                    .child(format!("Replace: {replacement}")),
                            )
                        })
                },
            )
            .collect::<Vec<_>>();

        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .p_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(div().flex_1().child(Input::new(&self.search_input)))
                    .child(div().flex_1().child(Input::new(&self.replace_input)))
                    .child(
                        div()
                            .id("run-search")
                            .px_3()
                            .py_2()
                            .rounded_md()
                            .bg(theme::surface_selected())
                            .text_color(theme::accent())
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.search_workspace(cx);
                            }))
                            .child("Search"),
                    )
                    .child(
                        div()
                            .id("replace-all")
                            .px_3()
                            .py_2()
                            .rounded_md()
                            .bg(if replace_armed {
                                theme::warning()
                            } else {
                                theme::surface_selected()
                            })
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.request_replace_all(cx);
                            }))
                            .child(if replace_armed {
                                "Apply Replace"
                            } else {
                                "Replace All"
                            }),
                    ),
            )
            .child(
                div()
                    .id("search-results")
                    .flex_1()
                    .overflow_y_scroll()
                    .when(self.search_results.truncated, |results| {
                        results.child(
                            div()
                                .p_3()
                                .text_color(theme::warning())
                                .child("Results Truncated By The Runtime Limit"),
                        )
                    })
                    .children(result_rows),
            )
            .into_any_element()
    }
}
