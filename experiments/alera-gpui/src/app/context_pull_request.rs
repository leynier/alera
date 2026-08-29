use std::collections::BTreeMap;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::{Input, Textarea};
use gpui_component::tooltip::Tooltip;

use super::context_pull_request_review_actions::PullRequestReviewAction;
use super::AleraApp;
use crate::forge_service::{ForgeAuthStatus, ForgeCheck, ForgeUnavailableReason};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_pull_request_panel(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if self.selected_source_control_scope().is_none() {
            return pull_request_message(
                AleraIcon::GitPullRequest,
                Some("Pull Request Unavailable"),
                "This workspace is not connected to a Git repository, so there are no Pull Requests to show.",
                None,
                cx,
            );
        }
        if self.forge_busy && self.forge_snapshot.auth_status == ForgeAuthStatus::Unknown {
            return div()
                .flex()
                .flex_1()
                .items_center()
                .justify_center()
                .child(loading_indicator(20.0, theme::text_muted()))
                .into_any_element();
        }
        if let Some(reason) = self.forge_snapshot.unavailable_reason {
            let (title, message) = match reason {
                ForgeUnavailableReason::NoRemote => (
                    "No Remote",
                    "This repository has no remote to detect a provider from.",
                ),
                ForgeUnavailableReason::ProviderNotDetected => (
                    "Provider Not Detected",
                    "Could not detect the git hosting provider. Set it in Project settings.",
                ),
                ForgeUnavailableReason::UnsupportedProvider => (
                    "Unsupported Provider",
                    "This hosting provider is not supported yet.",
                ),
            };
            return pull_request_message(AleraIcon::GitPullRequest, Some(title), message, None, cx);
        }
        match self.forge_snapshot.auth_status {
            ForgeAuthStatus::CliMissing => {
                return pull_request_message(
                    AleraIcon::Error,
                    Some("CLI Not Found"),
                    "Install `gh` and ensure it is on your PATH.",
                    None,
                    cx,
                );
            }
            ForgeAuthStatus::NotAuthenticated => {
                return pull_request_message(
                    AleraIcon::Error,
                    Some("Not Authenticated"),
                    "Run `gh auth login` to sign in, then refresh.",
                    Some("Refresh"),
                    cx,
                );
            }
            ForgeAuthStatus::Unknown | ForgeAuthStatus::Authenticated => {}
        }
        let Some(review) = self.forge_snapshot.review.as_ref() else {
            return self.render_pull_request_composer(cx);
        };
        let review_number = review.number;
        let reading_workspace_id = self.selected_workspace_id.clone().unwrap_or_default();
        let reading_key = super::reading_diff_pull_request::reading_diff_review_key(
            &reading_workspace_id,
            review_number,
        );
        let has_reading_diff = self.reading_diff_results.contains_key(&reading_key)
            || self.reading_diff_errors.contains_key(&reading_key);
        let reading_diff_visible = self.reading_diff_visible(&reading_key);
        let reading_request_number = review_number;
        let reading_toggle_key = reading_key.clone();
        let review_url = review.url.clone();
        let state_label = if review.draft {
            "Draft"
        } else if review.state.eq_ignore_ascii_case("open") {
            "Open"
        } else if review.state.eq_ignore_ascii_case("merged") {
            "Merged"
        } else {
            "Closed"
        };
        let state_color = match state_label {
            "Open" => theme::success(),
            "Merged" => theme::accent(),
            "Closed" => theme::danger(),
            _ => theme::text_muted(),
        };
        div()
            .id("pull-request-review")
            .relative()
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .overflow_hidden()
            .p_3()
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
                            .child("Pull Request"),
                    )
                    .child(
                        pr_icon_button(
                            "context-pr-refresh",
                            if self.forge_busy {
                                AleraIcon::Loading
                            } else {
                                AleraIcon::Refresh
                            },
                        )
                        .aria_label("Refresh")
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh")).into())
                        .when(!self.forge_busy, |button| {
                            button.on_click(cx.listener(|this, _, _, cx| this.refresh_forge(cx)))
                        }),
                    ),
            )
            .child(
                div()
                    .id("pull-request-review-header")
                    .mt_2()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(icon(AleraIcon::GitPullRequest, 16.0, theme::text_muted()))
                    .child(
                        div()
                            .text_sm()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(format!("#{review_number}")),
                    )
                    .child(state_chip(state_label, state_color))
                    .child(div().flex_1())
                    .when(!self.forge_review_editing, |header| {
                        header.child(
                            pr_icon_button("context-pr-edit", AleraIcon::Edit)
                                .aria_label("Edit Pull Request")
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Edit Pull Request")).into()
                                })
                                .on_click(cx.listener(|this, _, window, cx| {
                                    if !this.forge_busy {
                                        this.fill_review_fields(window, cx);
                                        this.forge_review_editing = true;
                                        cx.notify();
                                    }
                                })),
                        )
                    })
                    .child(
                        pr_icon_button("context-pr-read-ai", AleraIcon::Ai)
                            .aria_label("Read Diff With AI")
                            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Read Diff With AI")).into())
                            .when(
                                self.reading_diff_busy_key.as_deref() != Some(&reading_key),
                                |button| {
                                    button.on_click(cx.listener(move |this, _, _, cx| {
                                        this.request_pull_request_reading_diff(
                                            reading_request_number,
                                            false,
                                            cx,
                                        );
                                    }))
                                },
                            ),
                    )
                    .when(has_reading_diff, |header| {
                        header.child(
                            pr_icon_button(
                                "context-pr-toggle-reading",
                                if reading_diff_visible {
                                    AleraIcon::Diff
                                } else {
                                    AleraIcon::Ai
                                },
                            )
                            .aria_label(if reading_diff_visible {
                                "Show Pull Request Details"
                            } else {
                                "Show AI Reading Diff"
                            })
                            .on_click(cx.listener(
                                move |this, _, _, cx| {
                                    this.toggle_reading_diff_original(
                                        reading_toggle_key.clone(),
                                        cx,
                                    );
                                },
                            )),
                        )
                    })
                    .child(
                        pr_icon_button("context-pr-browser", AleraIcon::External)
                            .aria_label("Open In Browser")
                            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Open In Browser")).into())
                            .on_click(move |_, _, cx| cx.open_url(&review_url)),
                    ),
            )
            .when_some(self.forge_error.clone(), |panel, error| {
                panel.child(pull_request_error_banner(error))
            })
            .child(
                div()
                    .id("pull-request-review-scroll")
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .when(self.forge_review_editing, |content| {
                        content.child(self.render_pull_request_editor(cx))
                    })
                    .when(!self.forge_review_editing, |content| {
                        content.child(
                            div().mt_2().text_sm().child(review.title.clone()).child(
                                div()
                                    .mt_1()
                                    .text_xs()
                                    .text_color(theme::text_muted())
                                    .child(format!(
                                        "{} · {} → {}",
                                        review.author, review.head_branch, review.base_branch
                                    )),
                            ),
                        )
                    })
                    .child(self.render_pull_request_reading_diff(
                        &reading_workspace_id,
                        review_number,
                        cx,
                    ))
                    .child(self.render_pull_request_stack_section(cx))
                    .child(self.render_pull_request_checks(cx))
                    .child(self.render_pull_request_comments(window, cx)),
            )
            .child(self.render_pull_request_action_button(review_number, cx))
            .child(self.render_reading_diff_confirmation(&reading_key, cx))
            .into_any_element()
    }

    fn render_pull_request_editor(&self, cx: &mut Context<Self>) -> AnyElement {
        let options = self.forge_snapshot.base_branches.clone();
        let selected = self.forge_base_input.read(cx).value().to_string();
        div()
            .relative()
            .mt_3()
            .child(field_label("Title"))
            .child(Input::new(&self.forge_title_input).disabled(self.forge_busy))
            .child(div().h(px(12.0)))
            .child(field_label("Base Branch"))
            .child(
                div()
                    .id("context-pr-edit-base")
                    .focusable()
                    .tab_stop(!self.forge_busy)
                    .role(Role::ComboBox)
                    .aria_label("Base Branch")
                    .aria_expanded(self.forge_review_base_menu_open)
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .px_3()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border())
                    .cursor(if self.forge_busy {
                        CursorStyle::Arrow
                    } else {
                        CursorStyle::PointingHand
                    })
                    .when(!self.forge_busy, |field| {
                        field.on_click(cx.listener(|this, _, _, cx| {
                            this.forge_review_base_menu_open = !this.forge_review_base_menu_open;
                            cx.notify();
                        }))
                    })
                    .child(div().flex_1().text_sm().child(selected.clone()))
                    .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
            )
            .child(
                div()
                    .flex()
                    .gap_2()
                    .mt_3()
                    .child(
                        pr_button("context-pr-save", AleraIcon::Check, "Save", true).on_click(
                            cx.listener(|this, _, _, cx| {
                                if !this.forge_busy {
                                    this.forge_review_editing = false;
                                    this.update_review(cx);
                                }
                            }),
                        ),
                    )
                    .child(
                        pr_button("context-pr-cancel", AleraIcon::Close, "Cancel", false).on_click(
                            cx.listener(|this, _, _, cx| {
                                this.forge_review_editing = false;
                                this.forge_review_base_menu_open = false;
                                cx.notify();
                            }),
                        ),
                    ),
            )
            .when(self.forge_review_base_menu_open, |editor| {
                editor.child(
                    div()
                        .id("context-pr-edit-base-menu")
                        .role(Role::Menu)
                        .aria_label("Base Branch")
                        .absolute()
                        .top(px(84.0))
                        .left_0()
                        .right_0()
                        .occlude()
                        .rounded_md()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface_raised())
                        .shadow_lg()
                        .py_1()
                        .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                            this.forge_review_base_menu_open = false;
                            cx.notify();
                        }))
                        .children(options.into_iter().map(|branch| {
                            let value = branch.clone();
                            let checked = selected == branch;
                            div()
                                .id(gpui::SharedString::from(format!(
                                    "context-pr-edit-base-option-{branch}"
                                )))
                                .focusable()
                                .tab_stop(true)
                                .role(Role::MenuItem)
                                .aria_label(branch.clone())
                                .aria_selected(checked)
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_click(cx.listener(move |this, _, window, cx| {
                                    this.forge_review_base_menu_open = false;
                                    this.forge_base_input.update(cx, |input, cx| {
                                        input.set_value(value.clone(), window, cx);
                                    });
                                    cx.notify();
                                }))
                                .child(div().flex_1().child(branch))
                                .when(checked, |row| {
                                    row.child(icon(AleraIcon::Check, 13.0, theme::accent()))
                                })
                        })),
                )
            })
            .into_any_element()
    }

    fn render_pull_request_checks(&self, cx: &mut Context<Self>) -> AnyElement {
        let mut groups = BTreeMap::<&'static str, Vec<ForgeCheck>>::new();
        for check in self.forge_snapshot.checks.iter().cloned() {
            groups.entry(check_group(&check)).or_default().push(check);
        }
        for checks in groups.values_mut() {
            checks.sort_by_key(|check| check.name.to_ascii_lowercase());
        }
        div()
            .mt_4()
            .child(section_label("Checks", self.forge_snapshot.checks.len()))
            .child(div().h(px(8.0)))
            .when(self.forge_snapshot.checks.is_empty(), |section| {
                section.child(empty_label("No Checks Reported"))
            })
            .children(
                ["Failing", "In Progress", "Successful"]
                    .into_iter()
                    .filter_map(|group| {
                        let checks = groups.remove(group)?;
                        Some(self.render_check_group(group, checks, cx))
                    }),
            )
            .into_any_element()
    }

    fn render_check_group(
        &self,
        group: &'static str,
        checks: Vec<ForgeCheck>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let collapsed = self.forge_collapsed_check_groups.contains(group);
        let label = format!(
            "{} {} {}",
            checks.len(),
            group,
            if checks.len() == 1 { "Check" } else { "Checks" }
        );
        div()
            .child(
                div()
                    .id(SharedString::from(format!(
                        "context-pr-check-group-{group}"
                    )))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(label.clone())
                    .aria_expanded(!collapsed)
                    .flex()
                    .items_center()
                    .h(px(28.0))
                    .gap_1()
                    .rounded_sm()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if !this.forge_collapsed_check_groups.remove(group) {
                            this.forge_collapsed_check_groups.insert(group.to_string());
                        }
                        cx.notify();
                    }))
                    .child(icon(
                        if collapsed {
                            AleraIcon::ChevronRight
                        } else {
                            AleraIcon::ChevronDown
                        },
                        15.0,
                        theme::text_muted(),
                    ))
                    .child(div().text_xs().text_color(theme::text_muted()).child(label)),
            )
            .when(!collapsed, |section| {
                section.children(
                    checks
                        .into_iter()
                        .map(|check| self.render_check_row(check, cx)),
                )
            })
            .into_any_element()
    }

    fn render_check_row(&self, check: ForgeCheck, cx: &mut Context<Self>) -> AnyElement {
        let key = format!("{}|{}", check.name, check.link.as_deref().unwrap_or(""));
        let expanded = self.forge_expanded_checks.contains(&key);
        let toggle_key = key.clone();
        let link = check.link.clone();
        div()
            .ml_2()
            .child(
                div()
                    .id(gpui::SharedString::from(format!("context-pr-check-{key}")))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(check.name.clone())
                    .aria_expanded(expanded)
                    .flex()
                    .items_center()
                    .min_h(px(30.0))
                    .gap_2()
                    .rounded_sm()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if !this.forge_expanded_checks.remove(&toggle_key) {
                            this.forge_expanded_checks.insert(toggle_key.clone());
                        }
                        cx.notify();
                    }))
                    .child(check_status_icon(&check.bucket))
                    .child(
                        div()
                            .flex_1()
                            .text_sm()
                            .overflow_hidden()
                            .child(check.name.clone()),
                    )
                    .when_some(link, |row, url| {
                        row.child(
                            pr_icon_button_owned(
                                format!("context-pr-check-open-{key}"),
                                AleraIcon::External,
                            )
                            .aria_label("Open Check In Browser")
                            .on_click(move |_, _, cx| {
                                cx.stop_propagation();
                                cx.open_url(&url);
                            }),
                        )
                    })
                    .child(icon(
                        if expanded {
                            AleraIcon::ChevronUp
                        } else {
                            AleraIcon::ChevronDown
                        },
                        15.0,
                        theme::text_muted(),
                    )),
            )
            .when(expanded, |row| {
                let details = [
                    check.workflow.map(|value| ("Workflow", value)),
                    check.event.map(|value| ("Event", value)),
                    check.description.map(|value| ("Description", value)),
                    check
                        .started_at
                        .as_deref()
                        .and_then(format_check_timestamp)
                        .map(|value| ("Started", value)),
                    check
                        .completed_at
                        .as_deref()
                        .and_then(format_check_timestamp)
                        .map(|value| ("Completed", value)),
                ];
                let details = details.into_iter().flatten().collect::<Vec<_>>();
                row.child(
                    div()
                        .ml(px(32.0))
                        .mb_2()
                        .when(details.is_empty(), |body| {
                            body.child(empty_label("No Details Available"))
                        })
                        .children(details.into_iter().map(|(label, value)| {
                            div()
                                .flex()
                                .gap_2()
                                .text_xs()
                                .child(
                                    div()
                                        .w(px(72.0))
                                        .text_color(theme::text_muted())
                                        .child(label),
                                )
                                .child(value)
                        })),
                )
            })
            .into_any_element()
    }

    fn render_pull_request_comments(
        &self,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let review_open = self
            .forge_snapshot
            .review
            .as_ref()
            .is_some_and(|review| review.state.eq_ignore_ascii_case("open"));
        let composing = self.forge_comment_composing;
        div()
            .mt_4()
            .child(
                div()
                    .flex()
                    .items_center()
                    .child(section_label(
                        "Comments",
                        self.forge_snapshot.comments.len(),
                    ))
                    .child(div().flex_1())
                    .when(review_open && !composing, |header| {
                        header.child(
                            pr_icon_button("context-pr-comment-start", AleraIcon::Add)
                                .aria_label(if self.forge_snapshot.comments.is_empty() {
                                    "Start Conversation"
                                } else {
                                    "Add Comment"
                                })
                                .tooltip({
                                    let label = if self.forge_snapshot.comments.is_empty() {
                                        "Start Conversation"
                                    } else {
                                        "Add Comment"
                                    };
                                    move |_, cx| {
                                        let label = label.to_owned();
                                        cx.new(move |_| Tooltip::new(label)).into()
                                    }
                                })
                                .on_click(cx.listener(|this, _, window, cx| {
                                    if this.forge_busy {
                                        return;
                                    }
                                    this.forge_comment_composing = true;
                                    this.forge_comment_input.update(cx, |input, cx| {
                                        input.set_value("", window, cx);
                                        input.focus(window, cx);
                                    });
                                    cx.notify();
                                })),
                        )
                    }),
            )
            .when(composing, |section| {
                section
                    .child(
                        Textarea::new(&self.forge_comment_input)
                            .disabled(self.forge_busy)
                            .h(px(72.0)),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .items_center()
                            .gap_2()
                            .mt_2()
                            .child(
                                pr_button(
                                    "context-pr-comment-cancel",
                                    AleraIcon::Close,
                                    "Cancel",
                                    false,
                                )
                                .when(!self.forge_busy, |button| {
                                    button.on_click(cx.listener(|this, _, _, cx| {
                                        this.forge_comment_composing = false;
                                        cx.notify();
                                    }))
                                }),
                            )
                            .child(
                                pr_button(
                                    "context-pr-comment-post",
                                    if self.forge_busy {
                                        AleraIcon::Loading
                                    } else {
                                        AleraIcon::Send
                                    },
                                    "Post Comment",
                                    true,
                                )
                                .when(!self.forge_busy, |button| {
                                    button.on_click(cx.listener(|this, _, _, cx| {
                                        this.add_review_comment(cx);
                                    }))
                                }),
                            ),
                    )
                    .child(div().h(px(12.0)))
            })
            .when(self.forge_snapshot.comments.is_empty(), |section| {
                section.child(empty_label("No Comments Yet"))
            })
            .children(self.forge_snapshot.comments.iter().map(|comment| {
                let comment_id = if comment._id.trim().is_empty() {
                    format!(
                        "{}|{}|{}",
                        comment.author,
                        comment.created_at.as_deref().unwrap_or_default(),
                        comment.body
                    )
                } else {
                    comment._id.clone()
                };
                let url = comment.url.clone();
                let created_at = comment
                    .created_at
                    .as_deref()
                    .and_then(format_review_timestamp);
                let location = comment.path.as_ref().map(|path| {
                    comment
                        .line
                        .map(|line| format!("{path}:{line}"))
                        .unwrap_or_else(|| path.clone())
                });
                let resolved = comment.resolved;
                div()
                    .id(gpui::SharedString::from(format!(
                        "context-pr-comment-{comment_id}"
                    )))
                    .mt_2()
                    .p_3()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface_raised())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .child(
                                div()
                                    .flex_1()
                                    .text_xs()
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child(comment.author.clone()),
                            )
                            .when_some(created_at, |header, created_at| {
                                header.child(
                                    div()
                                        .text_xs()
                                        .text_color(theme::text_faint())
                                        .child(created_at),
                                )
                            })
                            .when_some(url, |header, url| {
                                header.child(
                                    pr_icon_button_owned(
                                        format!("context-pr-comment-open-{comment_id}"),
                                        AleraIcon::External,
                                    )
                                    .aria_label("Open Comment In Browser")
                                    .on_click(move |_, _, cx| cx.open_url(&url)),
                                )
                            }),
                    )
                    .when_some(location, |card, location| {
                        card.child(
                            div()
                                .mt_1()
                                .flex()
                                .items_center()
                                .gap_1()
                                .text_xs()
                                .text_color(theme::text_faint())
                                .child(icon(AleraIcon::Code, 13.0, theme::text_faint()))
                                .child(div().flex_1().child(location))
                                .when(resolved, |row| {
                                    row.child(div().text_color(theme::success()).child("Resolved"))
                                }),
                        )
                    })
                    .child(
                        div()
                            .mt_1()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(self.render_review_comment_body(
                                comment,
                                &comment_id,
                                review_open && !self.forge_busy,
                                cx,
                            )),
                    )
            }))
            .into_any_element()
    }

    fn render_pull_request_action_button(&self, number: u64, cx: &mut Context<Self>) -> AnyElement {
        let Some(action) = self.selected_pull_request_action() else {
            return div().into_any_element();
        };
        let available = self.available_pull_request_actions();
        let enabled = !(self.forge_busy
            || matches!(
                action,
                PullRequestReviewAction::Merge
                    | PullRequestReviewAction::Squash
                    | PullRequestReviewAction::Rebase
            ) && self
                .forge_snapshot
                .review
                .as_ref()
                .is_some_and(|review| review.mergeable.eq_ignore_ascii_case("conflicting")));
        let destructive = action == PullRequestReviewAction::Close;
        let foreground = if destructive {
            theme::on_danger()
        } else {
            theme::on_accent()
        };
        div()
            .relative()
            .flex()
            .mt_2()
            .h(px(34.0))
            .rounded_lg()
            .overflow_hidden()
            .bg(if destructive {
                theme::danger()
            } else {
                theme::accent()
            })
            .text_color(foreground)
            .child(
                div()
                    .id("context-pr-primary-action")
                    .focusable()
                    .tab_stop(enabled)
                    .role(Role::Button)
                    .aria_label(action.label())
                    .flex()
                    .flex_1()
                    .items_center()
                    .justify_center()
                    .gap_2()
                    .cursor(if enabled {
                        CursorStyle::PointingHand
                    } else {
                        CursorStyle::Arrow
                    })
                    .when(enabled, |button| {
                        button.hover(move |style| {
                            style.bg(if destructive {
                                theme::danger_hover()
                            } else {
                                theme::accent_hover()
                            })
                        })
                    })
                    .when(enabled, |button| {
                        button.on_click(cx.listener(move |this, _, _, cx| {
                            this.request_pull_request_action(action, number, cx);
                        }))
                    })
                    .child(icon(
                        if self.forge_busy {
                            AleraIcon::Loading
                        } else {
                            action_icon(action)
                        },
                        16.0,
                        foreground,
                    ))
                    .child(
                        div()
                            .text_sm()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(action.label()),
                    ),
            )
            .when(available.len() > 1, |button| {
                button
                    .child(div().w(px(1.0)).h(px(20.0)).bg(theme::overlay_scrim()))
                    .child(
                        div()
                            .id("context-pr-actions-menu-toggle")
                            .focusable()
                            .tab_stop(!self.forge_busy)
                            .role(Role::Button)
                            .aria_label("Pull Request Actions")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(34.0))
                            .h_full()
                            .cursor(if self.forge_busy {
                                CursorStyle::Arrow
                            } else {
                                CursorStyle::PointingHand
                            })
                            .when(!self.forge_busy, |toggle| {
                                toggle.hover(move |style| {
                                    style.bg(if destructive {
                                        theme::danger_hover()
                                    } else {
                                        theme::accent_hover()
                                    })
                                })
                            })
                            .when(!self.forge_busy, |toggle| {
                                toggle.on_click(cx.listener(|this, _, _, cx| {
                                    this.forge_review_action_menu_open =
                                        !this.forge_review_action_menu_open;
                                    cx.notify();
                                }))
                            })
                            .child(icon(AleraIcon::ChevronDown, 16.0, foreground)),
                    )
            })
            .when(self.forge_review_action_menu_open, |button| {
                button.child(
                    div()
                        .id("context-pr-actions-menu")
                        .role(Role::Menu)
                        .aria_label("Pull Request Actions")
                        .absolute()
                        .bottom(px(38.0))
                        .left_0()
                        .right_0()
                        .occlude()
                        .rounded_md()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface_raised())
                        .text_color(theme::text())
                        .shadow_lg()
                        .py_1()
                        .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                            this.forge_review_action_menu_open = false;
                            cx.notify();
                        }))
                        .children(available.into_iter().map(|option| {
                            div()
                                .id(gpui::SharedString::from(format!(
                                    "context-pr-action-option-{}",
                                    option.label()
                                )))
                                .focusable()
                                .tab_stop(true)
                                .role(Role::MenuItem)
                                .aria_label(option.label())
                                .aria_selected(option == action)
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .gap_2()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.forge_review_action = Some(option);
                                    this.forge_review_action_menu_open = false;
                                    cx.notify();
                                }))
                                .child(icon(
                                    action_icon(option),
                                    15.0,
                                    if option == PullRequestReviewAction::Close {
                                        theme::danger()
                                    } else {
                                        theme::text_muted()
                                    },
                                ))
                                .child(div().flex_1().child(option.label()))
                                .when(option == action, |row| {
                                    row.child(icon(AleraIcon::Check, 13.0, theme::accent()))
                                })
                        })),
                )
            })
            .into_any_element()
    }
}

fn pull_request_message(
    message_icon: AleraIcon,
    title: Option<&'static str>,
    message: &'static str,
    action: Option<&'static str>,
    cx: &mut Context<AleraApp>,
) -> AnyElement {
    div()
        .flex()
        .flex_col()
        .flex_1()
        .items_center()
        .justify_center()
        .p_4()
        .gap_3()
        .text_center()
        .child(icon(message_icon, 28.0, theme::text_muted()))
        .when_some(title, |body, title| {
            body.child(
                div()
                    .text_sm()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(title),
            )
        })
        .child(
            div()
                .max_w(px(280.0))
                .text_sm()
                .text_color(theme::text_muted())
                .child(message),
        )
        .when_some(action, |body, label| {
            body.child(
                pr_button(
                    "context-pr-message-action",
                    AleraIcon::Refresh,
                    label,
                    false,
                )
                .on_click(cx.listener(|this, _, _, cx| this.refresh_forge(cx))),
            )
        })
        .into_any_element()
}

pub(super) fn pull_request_error_banner(error: SharedString) -> gpui::Div {
    div()
        .w_full()
        .px_3()
        .py_2()
        .bg(gpui::Rgba {
            a: 0.12,
            ..theme::danger()
        })
        .text_sm()
        .text_color(theme::danger())
        .child(error)
}

fn state_chip(label: &'static str, color: gpui::Rgba) -> gpui::Div {
    div()
        .px_2()
        .py(px(2.0))
        .rounded_sm()
        .bg(gpui::Rgba { a: 0.15, ..color })
        .text_xs()
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .text_color(color)
        .child(label)
}

fn section_label(title: &'static str, count: usize) -> gpui::Div {
    div()
        .text_xs()
        .text_color(theme::text_muted())
        .child(if count == 0 {
            title.to_string()
        } else {
            format!("{title} ({count})")
        })
}

fn empty_label(label: &'static str) -> gpui::Div {
    div()
        .py_2()
        .text_xs()
        .text_color(theme::text_muted())
        .child(label)
}

fn field_label(label: &'static str) -> gpui::Div {
    div()
        .mb_1()
        .text_xs()
        .text_color(theme::text_muted())
        .child(label)
}

fn check_group(check: &ForgeCheck) -> &'static str {
    match check.bucket.to_ascii_lowercase().as_str() {
        "fail" | "failure" | "cancel" | "cancelled" | "timed_out" | "timedout"
        | "action_required" | "manual" => "Failing",
        "pass" | "success" | "skipped" | "skipping" | "neutral" => "Successful",
        _ => "In Progress",
    }
}

fn check_status_icon(bucket: &str) -> AnyElement {
    let kind = check_status_icon_kind(bucket);
    let color = match kind {
        AleraIcon::Success => theme::success(),
        AleraIcon::Cancel => theme::danger(),
        AleraIcon::Circle => theme::text_muted(),
        _ => theme::warning(),
    };
    icon(kind, 15.0, color)
}

fn check_status_icon_kind(bucket: &str) -> AleraIcon {
    match bucket.to_ascii_lowercase().as_str() {
        "pass" | "success" => AleraIcon::Success,
        "fail" | "failure" | "cancel" | "cancelled" | "timed_out" | "timedout"
        | "action_required" | "manual" => AleraIcon::Cancel,
        "skipped" | "skipping" | "neutral" | "not_applicable" => AleraIcon::Circle,
        _ => AleraIcon::Loading,
    }
}

fn format_review_timestamp(value: &str) -> Option<String> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|timestamp| {
            timestamp
                .with_timezone(&chrono::Local)
                .format("%a, %b %-d · %-I:%M %p")
                .to_string()
        })
}

fn format_check_timestamp(value: &str) -> Option<String> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|timestamp| {
            timestamp
                .with_timezone(&chrono::Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
}

pub(super) fn normalize_review_comment_markdown(body: &str) -> String {
    if !body.starts_with("[vc]:") {
        return body.to_string();
    }
    let Some(table_start) = body.find("| Project |") else {
        return body.to_string();
    };
    format!(".\n\n{}", &body[table_start..])
}

fn action_icon(action: PullRequestReviewAction) -> AleraIcon {
    match action {
        PullRequestReviewAction::Merge
        | PullRequestReviewAction::Squash
        | PullRequestReviewAction::Rebase => AleraIcon::GitMerge,
        PullRequestReviewAction::MarkReady => AleraIcon::Success,
        PullRequestReviewAction::ConvertToDraft => AleraIcon::Edit,
        PullRequestReviewAction::Close => AleraIcon::GitPullRequestClosed,
        PullRequestReviewAction::Unlink => AleraIcon::Unlink,
    }
}

fn pr_button(
    id: &'static str,
    kind: AleraIcon,
    label: &'static str,
    filled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(SharedString::from(id))
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .min_h(px(30.0))
        .px_3()
        .gap_2()
        .rounded_md()
        .bg(if filled {
            theme::accent()
        } else {
            theme::surface_raised()
        })
        .text_color(if filled {
            theme::on_accent()
        } else {
            theme::text()
        })
        .text_sm()
        .cursor(CursorStyle::PointingHand)
        .hover(move |style| {
            style.bg(if filled {
                theme::accent_hover()
            } else {
                theme::surface_selected()
            })
        })
        .child(icon(
            kind,
            14.0,
            if filled {
                theme::on_accent()
            } else {
                theme::text_muted()
            },
        ))
        .child(label)
}

fn pr_icon_button(id: &'static str, kind: AleraIcon) -> gpui::Stateful<gpui::Div> {
    pr_icon_button_owned(id.to_string(), kind)
}

fn pr_icon_button_owned(id: String, kind: AleraIcon) -> gpui::Stateful<gpui::Div> {
    div()
        .id(SharedString::from(id))
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .flex()
        .items_center()
        .justify_center()
        .w(px(30.0))
        .h(px(30.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_selected()))
        .child(icon(kind, 16.0, theme::text_muted()))
}

#[cfg(test)]
mod tests {
    use super::{action_icon, check_group, check_status_icon_kind};
    use crate::app::context_pull_request_review_actions::PullRequestReviewAction;
    use crate::forge_api::ForgeCheck;
    use crate::icons::AleraIcon;

    fn check(bucket: &str) -> ForgeCheck {
        ForgeCheck {
            name: "check".to_owned(),
            _state: String::new(),
            bucket: bucket.to_owned(),
            link: None,
            description: None,
            workflow: None,
            event: None,
            started_at: None,
            completed_at: None,
        }
    }

    #[test]
    fn check_status_icons_match_flutter_conclusions() {
        assert_eq!(check_status_icon_kind("pass"), AleraIcon::Success);
        assert_eq!(check_status_icon_kind("timed_out"), AleraIcon::Cancel);
        assert_eq!(check_status_icon_kind("action_required"), AleraIcon::Cancel);
        assert_eq!(check_status_icon_kind("skipping"), AleraIcon::Circle);
        assert_eq!(check_status_icon_kind("neutral"), AleraIcon::Circle);
        assert_eq!(check_status_icon_kind("pending"), AleraIcon::Loading);
    }

    #[test]
    fn check_groups_match_flutter_conclusion_buckets() {
        assert_eq!(check_group(&check("timed_out")), "Failing");
        assert_eq!(check_group(&check("action_required")), "Failing");
        assert_eq!(check_group(&check("skipping")), "Successful");
        assert_eq!(check_group(&check("pending")), "In Progress");
    }

    #[test]
    fn review_action_icons_match_flutter() {
        assert_eq!(
            action_icon(PullRequestReviewAction::Rebase),
            AleraIcon::GitMerge
        );
        assert_eq!(
            action_icon(PullRequestReviewAction::MarkReady),
            AleraIcon::Success
        );
        assert_eq!(
            action_icon(PullRequestReviewAction::Close),
            AleraIcon::GitPullRequestClosed
        );
        assert_eq!(
            action_icon(PullRequestReviewAction::Unlink),
            AleraIcon::Unlink
        );
    }
}
