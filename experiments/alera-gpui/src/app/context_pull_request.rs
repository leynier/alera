use std::collections::BTreeMap;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::Input;
use gpui_component::text::TextView;

use super::context_pull_request_review_actions::PullRequestReviewAction;
use super::AleraApp;
use crate::forge_service::{ForgeAuthStatus, ForgeCheck, ForgeUnavailableReason};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_pull_request_panel(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        if self.forge_busy && self.forge_snapshot.auth_status == ForgeAuthStatus::Unknown {
            return pull_request_message(
                AleraIcon::Loading,
                None,
                "Loading Pull Request",
                None,
                cx,
            );
        }
        if let Some(reason) = self.forge_snapshot.unavailable_reason {
            let (title, message) = match reason {
                ForgeUnavailableReason::NoRemote => (
                    "No Remote",
                    "This Repository Has No Remote To Detect A Provider From.",
                ),
                ForgeUnavailableReason::ProviderNotDetected => (
                    "Provider Not Detected",
                    "Could Not Detect The Git Hosting Provider. Set It In Project Settings.",
                ),
                ForgeUnavailableReason::UnsupportedProvider => (
                    "Unsupported Provider",
                    "This Hosting Provider Is Not Supported Yet.",
                ),
            };
            return pull_request_message(AleraIcon::GitPullRequest, Some(title), message, None, cx);
        }
        match self.forge_snapshot.auth_status {
            ForgeAuthStatus::CliMissing => {
                return pull_request_message(
                    AleraIcon::Error,
                    Some("CLI Not Found"),
                    "Install `gh` And Ensure It Is On Your PATH.",
                    None,
                    cx,
                );
            }
            ForgeAuthStatus::NotAuthenticated => {
                return pull_request_message(
                    AleraIcon::Error,
                    Some("Not Authenticated"),
                    "Run `gh auth login` To Sign In, Then Refresh.",
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
                        .when(!self.forge_busy, |button| {
                            button.on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, _, cx| this.refresh_forge(cx)),
                            )
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
                            pr_icon_button("context-pr-edit", AleraIcon::Edit).on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(|this, _, window, cx| {
                                    if !this.forge_busy {
                                        this.fill_review_fields(window, cx);
                                        this.forge_review_editing = true;
                                        cx.notify();
                                    }
                                }),
                            ),
                        )
                    })
                    .child(
                        pr_icon_button("context-pr-browser", AleraIcon::External)
                            .on_mouse_down(gpui::MouseButton::Left, move |_, _, cx| {
                                cx.open_url(&review_url)
                            }),
                    ),
            )
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
                    .child(self.render_pull_request_checks(cx))
                    .child(self.render_pull_request_comments(window, cx)),
            )
            .child(self.render_pull_request_action_button(review_number, cx))
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
                        field.on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                this.forge_review_base_menu_open =
                                    !this.forge_review_base_menu_open;
                                cx.notify();
                            }),
                        )
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
                        pr_button("context-pr-save", AleraIcon::Check, "Save", true).on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(|this, _, _, cx| {
                                if !this.forge_busy {
                                    this.forge_review_editing = false;
                                    this.update_review(cx);
                                }
                            }),
                        ),
                    )
                    .child(
                        pr_button("context-pr-cancel", AleraIcon::Close, "Cancel", false)
                            .on_mouse_down(
                                gpui::MouseButton::Left,
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
                        .children(options.into_iter().enumerate().map(|(index, branch)| {
                            let value = branch.clone();
                            let checked = selected == branch;
                            div()
                                .id(("context-pr-edit-base-option", index))
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(move |this, _, window, cx| {
                                        this.forge_review_base_menu_open = false;
                                        this.forge_base_input.update(cx, |input, cx| {
                                            input.set_value(value.clone(), window, cx);
                                        });
                                        cx.notify();
                                    }),
                                )
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
                    .flex()
                    .items_center()
                    .h(px(28.0))
                    .gap_1()
                    .rounded_sm()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            if !this.forge_collapsed_check_groups.remove(group) {
                                this.forge_collapsed_check_groups.insert(group.to_string());
                            }
                            cx.notify();
                        }),
                    )
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
                        .enumerate()
                        .map(|(index, check)| self.render_check_row(index, check, cx)),
                )
            })
            .into_any_element()
    }

    fn render_check_row(
        &self,
        index: usize,
        check: ForgeCheck,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let key = format!("{}|{}", check.name, check.link.as_deref().unwrap_or(""));
        let expanded = self.forge_expanded_checks.contains(&key);
        let toggle_key = key.clone();
        let link = check.link.clone();
        div()
            .ml_2()
            .child(
                div()
                    .id(("context-pr-check", index))
                    .flex()
                    .items_center()
                    .min_h(px(30.0))
                    .gap_2()
                    .rounded_sm()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            if !this.forge_expanded_checks.remove(&toggle_key) {
                                this.forge_expanded_checks.insert(toggle_key.clone());
                            }
                            cx.notify();
                        }),
                    )
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
                                format!("context-pr-check-open-{index}"),
                                AleraIcon::External,
                            )
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                move |_, _, cx| {
                                    cx.stop_propagation();
                                    cx.open_url(&url);
                                },
                            ),
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
                    check.description.map(|value| ("Description", value)),
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
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let review_open = self
            .forge_snapshot
            .review
            .as_ref()
            .is_some_and(|review| review.state.eq_ignore_ascii_case("open"));
        div()
            .mt_4()
            .child(section_label(
                "Comments",
                self.forge_snapshot.comments.len(),
            ))
            .when(self.forge_snapshot.comments.is_empty(), |section| {
                section.child(empty_label("No Comments Yet"))
            })
            .children(
                self.forge_snapshot
                    .comments
                    .iter()
                    .cloned()
                    .enumerate()
                    .map(|(index, comment)| {
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
                            .id(("context-pr-comment", index))
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
                                            .child(comment.author),
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
                                                format!("context-pr-comment-open-{index}"),
                                                AleraIcon::External,
                                            )
                                            .on_mouse_down(
                                                gpui::MouseButton::Left,
                                                move |_, _, cx| cx.open_url(&url),
                                            ),
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
                                            row.child(
                                                div()
                                                    .text_color(theme::success())
                                                    .child("Resolved"),
                                            )
                                        }),
                                )
                            })
                            .child(
                                div()
                                    .mt_1()
                                    .text_sm()
                                    .text_color(theme::text_muted())
                                    .child(
                                        TextView::markdown(
                                            ("context-pr-comment-body", index),
                                            normalize_review_comment_markdown(&comment.body),
                                            window,
                                            cx,
                                        )
                                        .selectable(true),
                                    ),
                            )
                    }),
            )
            .when(review_open, |section| {
                section.child(
                    div()
                        .mt_3()
                        .child(Input::new(&self.forge_comment_input).disabled(self.forge_busy))
                        .child(
                            pr_button(
                                "context-pr-comment-add",
                                if self.forge_busy {
                                    AleraIcon::Loading
                                } else {
                                    AleraIcon::Add
                                },
                                "Add Comment",
                                true,
                            )
                            .mt_2()
                            .when(!self.forge_busy, |button| {
                                button.on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| this.add_review_comment(cx)),
                                )
                            }),
                        ),
                )
            })
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
                        button.on_mouse_down(
                            gpui::MouseButton::Left,
                            cx.listener(move |this, _, _, cx| {
                                this.request_pull_request_action(action, number, cx);
                            }),
                        )
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
                                toggle.on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.forge_review_action_menu_open =
                                            !this.forge_review_action_menu_open;
                                        cx.notify();
                                    }),
                                )
                            })
                            .child(icon(AleraIcon::ChevronDown, 16.0, foreground)),
                    )
            })
            .when(self.forge_review_action_menu_open, |button| {
                button.child(
                    div()
                        .id("context-pr-actions-menu")
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
                        .children(available.into_iter().enumerate().map(|(index, option)| {
                            div()
                                .id(("context-pr-action-option", index))
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .gap_2()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(move |this, _, _, cx| {
                                        this.forge_review_action = Some(option);
                                        this.forge_review_action_menu_open = false;
                                        cx.notify();
                                    }),
                                )
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
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(|this, _, _, cx| this.refresh_forge(cx)),
                ),
            )
        })
        .into_any_element()
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
        "fail" | "failure" | "cancel" | "cancelled" | "timed_out" => "Failing",
        "pass" | "success" | "skipped" | "neutral" => "Successful",
        _ => "In Progress",
    }
}

fn check_status_icon(bucket: &str) -> AnyElement {
    let (kind, color) = match bucket.to_ascii_lowercase().as_str() {
        "pass" | "success" => (AleraIcon::Success, theme::success()),
        "fail" | "failure" | "cancel" | "cancelled" => (AleraIcon::Cancel, theme::danger()),
        _ => (AleraIcon::Loading, theme::warning()),
    };
    icon(kind, 15.0, color)
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

fn normalize_review_comment_markdown(body: &str) -> String {
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
        | PullRequestReviewAction::Rebase => AleraIcon::GitSync,
        PullRequestReviewAction::MarkReady => AleraIcon::Check,
        PullRequestReviewAction::ConvertToDraft => AleraIcon::Edit,
        PullRequestReviewAction::Close => AleraIcon::Close,
        PullRequestReviewAction::Unlink => AleraIcon::Link,
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
        .flex()
        .items_center()
        .justify_center()
        .w(px(26.0))
        .h(px(26.0))
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_selected()))
        .child(icon(kind, 14.0, theme::text_muted()))
}
