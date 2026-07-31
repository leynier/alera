use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, InteractiveElement as _,
    IntoElement as _, ParentElement as _, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::Input;
use serde_json::json;

use super::AleraApp;
use crate::forge_service::{ForgeAction, MergeMethod};
use crate::theme;

impl AleraApp {
    pub(super) fn refresh_forge(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.forge_generation += 1;
        let generation = self.forge_generation;
        self.forge_busy = true;
        let service = self.forge_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.snapshot(workspace_path).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.forge_generation {
                    return;
                }
                this.forge_busy = false;
                match result {
                    Ok(snapshot) => {
                        this.forge_snapshot = snapshot;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn run_forge_action(&mut self, action: ForgeAction, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let workspace_id = self.selected_workspace_id.clone();
        self.forge_generation += 1;
        let generation = self.forge_generation;
        self.forge_busy = true;
        self.forge_danger_armed = None;
        let service = self.forge_service.clone();
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = service.action(workspace_path.clone(), action).await;
            let snapshot = if result.is_ok() {
                service.snapshot(workspace_path).await.ok()
            } else {
                None
            };
            if let (Some(workspace_id), Some(review)) = (
                workspace_id,
                snapshot
                    .as_ref()
                    .and_then(|snapshot| snapshot.review.as_ref()),
            ) {
                let _ = bridge
                    .request(
                        "linkedReview.upsert",
                        json!({
                            "workspaceId": workspace_id,
                            "dismissed": false,
                            "provider": "github",
                            "number": review.number,
                            "url": review.url,
                            "linkedAt": chrono::Utc::now().to_rfc3339(),
                        }),
                    )
                    .await;
            }
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.forge_generation {
                    return;
                }
                this.forge_busy = false;
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.forge_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn create_review(&mut self, draft: bool, cx: &mut Context<Self>) {
        let title = self.forge_title_input.read(cx).value().trim().to_string();
        let body = self.forge_body_input.read(cx).value().to_string();
        let base = self.forge_base_input.read(cx).value().trim().to_string();
        if title.is_empty() || base.is_empty() {
            self.local_message = Some("Title And Base Branch Are Required".into());
            cx.notify();
            return;
        }
        self.run_forge_action(
            ForgeAction::Create {
                title,
                body,
                base,
                draft,
            },
            cx,
        );
    }

    fn update_review(&mut self, cx: &mut Context<Self>) {
        let Some(review) = self.forge_snapshot.review.as_ref() else {
            return;
        };
        let title = self.forge_title_input.read(cx).value().trim().to_string();
        let body = self.forge_body_input.read(cx).value().to_string();
        let base = self.forge_base_input.read(cx).value().trim().to_string();
        if title.is_empty() || base.is_empty() {
            self.local_message = Some("Title And Base Branch Are Required".into());
            cx.notify();
            return;
        }
        self.run_forge_action(
            ForgeAction::Update {
                number: review.number,
                title,
                body,
                base,
            },
            cx,
        );
    }

    pub(super) fn render_forge_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let snapshot = &self.forge_snapshot;
        let review_card = if let Some(review) = &snapshot.review {
            let number = review.number;
            let draft = review.draft;
            let merge_number = number;
            let squash_number = number;
            let rebase_number = number;
            let close_number = number;
            div()
                .flex()
                .flex_col()
                .gap_2()
                .child(
                    div()
                        .text_lg()
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(format!("#{} {}", review.number, review.title)),
                )
                .child(
                    div()
                        .text_sm()
                        .text_color(theme::text_muted())
                        .child(format!(
                            "{} · {} → {} · {} · {}",
                            review.author,
                            review.head_branch,
                            review.base_branch,
                            review.state,
                            review.mergeable
                        )),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(theme::accent())
                        .child(review.url.clone()),
                )
                .child(
                    div()
                        .flex()
                        .flex_wrap()
                        .gap_2()
                        .child(forge_button("forge-fill", "Use Review Values").on_click(
                            cx.listener(|this, _, window, cx| this.fill_review_fields(window, cx)),
                        ))
                        .child(
                            forge_button(
                                "forge-draft",
                                if draft {
                                    "Mark Ready"
                                } else {
                                    "Convert To Draft"
                                },
                            )
                            .on_click(cx.listener(
                                move |this, _, _, cx| {
                                    this.run_forge_action(
                                        ForgeAction::SetDraft {
                                            number,
                                            draft: !draft,
                                        },
                                        cx,
                                    );
                                },
                            )),
                        )
                        .child(forge_button("forge-merge", "Merge").on_click(cx.listener(
                            move |this, _, _, cx| {
                                this.confirm_forge_action(
                                    "Merge",
                                    ForgeAction::Merge {
                                        number: merge_number,
                                        method: MergeMethod::Merge,
                                    },
                                    cx,
                                );
                            },
                        )))
                        .child(forge_button("forge-squash", "Squash").on_click(cx.listener(
                            move |this, _, _, cx| {
                                this.confirm_forge_action(
                                    "Squash",
                                    ForgeAction::Merge {
                                        number: squash_number,
                                        method: MergeMethod::Squash,
                                    },
                                    cx,
                                );
                            },
                        )))
                        .child(forge_button("forge-rebase", "Rebase").on_click(cx.listener(
                            move |this, _, _, cx| {
                                this.confirm_forge_action(
                                    "Rebase",
                                    ForgeAction::Merge {
                                        number: rebase_number,
                                        method: MergeMethod::Rebase,
                                    },
                                    cx,
                                );
                            },
                        )))
                        .child(forge_button("forge-close", "Close").on_click(cx.listener(
                            move |this, _, _, cx| {
                                this.confirm_forge_action(
                                    "Close",
                                    ForgeAction::Close {
                                        number: close_number,
                                    },
                                    cx,
                                );
                            },
                        ))),
                )
                .into_any_element()
        } else {
            div()
                .text_color(theme::text_muted())
                .child("No Open Pull Request For This Branch")
                .into_any_element()
        };
        let checks = snapshot
            .checks
            .iter()
            .enumerate()
            .map(|(index, check)| {
                div()
                    .id(("forge-check", index))
                    .px_3()
                    .py_2()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .flex()
                            .justify_between()
                            .child(check.name.clone())
                            .child(
                                div()
                                    .text_color(check_color(&check.bucket))
                                    .child(check.state.clone()),
                            ),
                    )
                    .when_some(check.workflow.clone(), |row, workflow| {
                        row.child(
                            div()
                                .text_xs()
                                .text_color(theme::text_muted())
                                .child(workflow),
                        )
                    })
                    .when_some(check.description.clone(), |row, description| {
                        row.child(
                            div()
                                .text_xs()
                                .text_color(theme::text_muted())
                                .child(description),
                        )
                    })
                    .when_some(check.link.clone(), |row, link| {
                        row.child(div().text_xs().text_color(theme::accent()).child(link))
                    })
            })
            .collect::<Vec<_>>();
        let comments = snapshot
            .comments
            .iter()
            .enumerate()
            .map(|(index, comment)| {
                div()
                    .id(("forge-comment", index))
                    .px_3()
                    .py_2()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(comment.author.clone()),
                    )
                    .child(comment.body.clone())
                    .when_some(comment.url.clone(), |row, url| {
                        row.child(div().text_xs().text_color(theme::accent()).child(url))
                    })
            })
            .collect::<Vec<_>>();

        div()
            .flex()
            .flex_col()
            .flex_1()
            .overflow_hidden()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .p_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(div().font_weight(gpui::FontWeight::SEMIBOLD).child(format!(
                        "{} · {} · {} · {}",
                        snapshot.provider, snapshot.host, snapshot.repo_slug, snapshot.branch
                    )))
                    .child(
                        div()
                            .text_xs()
                            .text_color(if snapshot.authenticated {
                                theme::success()
                            } else {
                                theme::warning()
                            })
                            .child(if snapshot.authenticated {
                                "Authenticated"
                            } else {
                                "Authentication Required"
                            }),
                    )
                    .child(div().flex_1())
                    .child(
                        forge_button("forge-refresh", "Refresh")
                            .on_click(cx.listener(|this, _, _, cx| this.refresh_forge(cx))),
                    ),
            )
            .child(
                div()
                    .p_4()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(review_card),
            )
            .child(
                div()
                    .flex()
                    .flex_1()
                    .overflow_hidden()
                    .child(
                        div()
                            .id("forge-checks")
                            .w(gpui::relative(0.34))
                            .h_full()
                            .overflow_y_scroll()
                            .border_r_1()
                            .border_color(theme::border())
                            .child(section_title("Checks"))
                            .children(checks),
                    )
                    .child(
                        div()
                            .id("forge-conversation")
                            .w(gpui::relative(0.33))
                            .h_full()
                            .overflow_y_scroll()
                            .border_r_1()
                            .border_color(theme::border())
                            .child(section_title("Conversation"))
                            .children(comments)
                            .child(
                                div()
                                    .p_3()
                                    .child(Input::new(&self.forge_comment_input))
                                    .child(
                                        forge_button("forge-comment-add", "Add Comment").on_click(
                                            cx.listener(|this, _, _, cx| {
                                                this.add_review_comment(cx);
                                            }),
                                        ),
                                    ),
                            ),
                    )
                    .child(
                        div()
                            .id("forge-composer")
                            .flex_1()
                            .h_full()
                            .overflow_y_scroll()
                            .child(section_title("Composer"))
                            .p_3()
                            .gap_2()
                            .child(Input::new(&self.forge_title_input))
                            .child(Input::new(&self.forge_base_input))
                            .child(
                                div()
                                    .h(gpui::px(150.0))
                                    .child(Input::new(&self.forge_body_input).h_full()),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_wrap()
                                    .gap_2()
                                    .child(
                                        forge_button("forge-create", "Create Pull Request")
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.create_review(false, cx);
                                            })),
                                    )
                                    .child(
                                        forge_button("forge-create-draft", "Create Draft")
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.create_review(true, cx);
                                            })),
                                    )
                                    .child(
                                        forge_button("forge-update", "Update Pull Request")
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.update_review(cx);
                                            })),
                                    ),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn forge_button(id: &'static str, label: &'static str) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .mt_2()
        .px_3()
        .py_1()
        .rounded_md()
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(label)
}

fn section_title(title: &'static str) -> gpui::Div {
    div()
        .px_3()
        .py_2()
        .bg(theme::surface())
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .child(title)
}

fn check_color(bucket: &str) -> gpui::Rgba {
    match bucket.to_ascii_lowercase().as_str() {
        "pass" | "success" => theme::success(),
        "fail" | "cancel" => theme::danger(),
        _ => theme::warning(),
    }
}
