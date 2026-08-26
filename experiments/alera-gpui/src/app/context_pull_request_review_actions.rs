use gpui::{
    div, px, AnyElement, Context, CursorStyle, InteractiveElement as _, IntoElement as _,
    ParentElement as _, Styled as _,
};
use serde_json::json;

use super::AleraApp;
use crate::forge_service::{ForgeAction, MergeMethod};
use crate::theme;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum PullRequestReviewAction {
    Merge,
    Squash,
    Rebase,
    MarkReady,
    ConvertToDraft,
    Close,
    Unlink,
}

impl PullRequestReviewAction {
    pub(super) fn label(self) -> &'static str {
        match self {
            Self::Merge => "Create Merge Commit",
            Self::Squash => "Squash and Merge",
            Self::Rebase => "Rebase and Merge",
            Self::MarkReady => "Mark Ready For Review",
            Self::ConvertToDraft => "Convert To Draft",
            Self::Close => "Close Pull Request",
            Self::Unlink => "Unlink Pull Request",
        }
    }

    fn destructive(self) -> bool {
        self == Self::Close
    }
}

#[derive(Clone, Copy, Debug)]
pub(super) struct PullRequestConfirmation {
    pub action: PullRequestReviewAction,
    pub number: u64,
}

impl AleraApp {
    pub(super) fn available_pull_request_actions(&self) -> Vec<PullRequestReviewAction> {
        let Some(review) = self.forge_snapshot.review.as_ref() else {
            return Vec::new();
        };
        let mut actions = Vec::new();
        if review.draft {
            actions.push(PullRequestReviewAction::MarkReady);
        } else if review.state.eq_ignore_ascii_case("open") {
            actions.extend([
                PullRequestReviewAction::Merge,
                PullRequestReviewAction::Squash,
                PullRequestReviewAction::Rebase,
                PullRequestReviewAction::ConvertToDraft,
            ]);
        }
        if review.state.eq_ignore_ascii_case("open") {
            actions.push(PullRequestReviewAction::Close);
        }
        actions.push(PullRequestReviewAction::Unlink);
        actions
    }

    pub(super) fn selected_pull_request_action(&self) -> Option<PullRequestReviewAction> {
        let available = self.available_pull_request_actions();
        self.forge_review_action
            .filter(|action| available.contains(action))
            .or_else(|| available.first().copied())
    }

    pub(super) fn request_pull_request_action(
        &mut self,
        action: PullRequestReviewAction,
        number: u64,
        cx: &mut Context<Self>,
    ) {
        self.forge_review_action_menu_open = false;
        self.forge_review_confirmation = Some(PullRequestConfirmation { action, number });
        cx.notify();
    }

    pub(super) fn confirm_pull_request_action(&mut self, cx: &mut Context<Self>) {
        let Some(confirmation) = self.forge_review_confirmation.take() else {
            return;
        };
        let number = confirmation.number;
        match confirmation.action {
            PullRequestReviewAction::Merge => self.run_forge_action(
                ForgeAction::Merge {
                    number,
                    method: MergeMethod::Merge,
                },
                cx,
            ),
            PullRequestReviewAction::Squash => self.run_forge_action(
                ForgeAction::Merge {
                    number,
                    method: MergeMethod::Squash,
                },
                cx,
            ),
            PullRequestReviewAction::Rebase => self.run_forge_action(
                ForgeAction::Merge {
                    number,
                    method: MergeMethod::Rebase,
                },
                cx,
            ),
            PullRequestReviewAction::MarkReady => self.run_forge_action(
                ForgeAction::SetDraft {
                    number,
                    draft: false,
                },
                cx,
            ),
            PullRequestReviewAction::ConvertToDraft => self.run_forge_action(
                ForgeAction::SetDraft {
                    number,
                    draft: true,
                },
                cx,
            ),
            PullRequestReviewAction::Close => {
                self.run_forge_action(ForgeAction::Close { number }, cx)
            }
            PullRequestReviewAction::Unlink => self.unlink_pull_request(number, cx),
        }
    }

    fn unlink_pull_request(&mut self, number: u64, cx: &mut Context<Self>) {
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let review = self.forge_snapshot.review.clone();
        let bridge = self.bridge.clone();
        self.forge_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "linkedReview.upsert",
                    json!({
                        "workspaceId": workspace_id,
                        "dismissed": true,
                        "provider": "github",
                        "number": number,
                        "url": review.as_ref().map(|review| review.url.as_str()),
                        "linkedAt": chrono::Utc::now().to_rfc3339(),
                    }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.forge_busy = false;
                match result {
                    Ok(_) => {
                        this.forge_link_form_open = true;
                        this.local_message = Some("Pull Request Unlinked".into());
                        this.refresh_forge(cx);
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

    pub(super) fn render_pull_request_confirmation(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(confirmation) = self.forge_review_confirmation else {
            return div().into_any_element();
        };
        let action = confirmation.action;
        let provider = if self.forge_snapshot.provider.is_empty() {
            "Provider"
        } else {
            &self.forge_snapshot.provider
        };
        let title = format!("{} PR #{}?", action.label(), confirmation.number);
        let message = match action {
            PullRequestReviewAction::Close => {
                "This Will Close The Pull Request Without Merging It.".to_string()
            }
            PullRequestReviewAction::Unlink => format!(
                "This Will Remove The Pull Request Link From This Workspace. The Pull Request On {provider} Will Not Be Changed."
            ),
            PullRequestReviewAction::ConvertToDraft => {
                format!("This Will Convert The Pull Request To Draft On {provider}.")
            }
            PullRequestReviewAction::MarkReady => {
                format!("This Will Mark The Pull Request As Ready For Review On {provider}.")
            }
            PullRequestReviewAction::Merge
            | PullRequestReviewAction::Squash
            | PullRequestReviewAction::Rebase => {
                format!("This Will Update The Pull Request On {provider}.")
            }
        };
        div()
            .absolute()
            .inset_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.forge_review_confirmation = None;
                    cx.notify();
                }),
            )
            .child(
                div()
                    .w(px(420.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p(px(20.0))
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        div()
                            .text_size(px(14.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child(title),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(message),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_5()
                            .child(
                                confirmation_button("cancel-pr-action", "Cancel", false, false)
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.forge_review_confirmation = None;
                                            cx.notify();
                                        }),
                                    ),
                            )
                            .child(
                                confirmation_button(
                                    "confirm-pr-action",
                                    action.label(),
                                    action.destructive(),
                                    true,
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.confirm_pull_request_action(cx);
                                    }),
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn confirmation_button(
    id: &'static str,
    label: &'static str,
    destructive: bool,
    primary: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .flex_1()
        .h(px(36.0))
        .px_4()
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .bg(if destructive {
            theme::danger()
        } else if primary {
            theme::accent()
        } else {
            theme::transparent()
        })
        .text_color(if destructive {
            theme::on_danger()
        } else if primary {
            theme::app_background()
        } else {
            theme::text()
        })
        .hover(move |style| {
            style.bg(if destructive {
                theme::danger_hover()
            } else if primary {
                theme::accent_hover()
            } else {
                theme::surface_selected()
            })
        })
        .child(label)
}
