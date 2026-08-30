use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, InteractiveElement as _,
    IntoElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _,
    Styled as _,
};
use gpui_component::input::Input;

use super::forge_stack::StackWorkspaceCandidate;
use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_pull_request_stack_section(&self, cx: &mut Context<Self>) -> AnyElement {
        let current_number = self
            .forge_snapshot
            .review
            .as_ref()
            .map(|review| review.number)
            .unwrap_or_default();
        let candidates = self.forge_stack_workspace_candidates();
        let stack = self.forge_snapshot.stack.as_ref();
        let mut card = div()
            .id("pull-request-stack-section")
            .mt_3()
            .p_3()
            .rounded_md()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(icon(AleraIcon::GitGraph, 15.0, theme::text_muted()))
                    .child(
                        div()
                            .flex_1()
                            .text_size(crate::theme::body_size())
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(stack.map_or_else(
                                || "Stacked Pull Requests".to_string(),
                                |stack| format!("Stack #{}", stack.number),
                            )),
                    )
                    .when_some(stack, |header, stack| {
                        let position = stack
                            .entries
                            .iter()
                            .find(|entry| entry.review.number == current_number)
                            .map(|entry| entry.position);
                        header.child(div().text_size(crate::theme::caption_size()).text_color(theme::text_muted()).child(
                            position.map_or_else(
                                || format!("{} Pull Requests", stack.entries.len()),
                                |position| format!("{position} of {}", stack.entries.len()),
                            ),
                        ))
                    }),
            );
        if let Some(stack) = stack {
            card = card
                .child(
                    div()
                        .mt_2()
                        .text_size(crate::theme::caption_size())
                        .text_color(theme::text_muted())
                        .child(format!(
                            "Base: {}{}",
                            if stack.base_branch.is_empty() {
                                "Repository Default"
                            } else {
                                &stack.base_branch
                            },
                            if stack.open { "" } else { " · Closed" }
                        )),
                )
                .children(stack.entries.iter().map(|entry| {
                    let review = &entry.review;
                    let url = review.url.clone();
                    let current = review.number == current_number;
                    let local_workspace = candidates
                        .iter()
                        .find(|workspace| workspace.branch == review.head_branch)
                        .map(|workspace| workspace.id.clone());
                    div()
                        .id(SharedString::from(format!(
                            "stack-review-{}",
                            review.number
                        )))
                        .mt_1()
                        .flex()
                        .items_center()
                        .gap_2()
                        .px_2()
                        .py_1()
                        .rounded_sm()
                        .when(current, |row| row.bg(theme::accent_subtle()))
                        .cursor(CursorStyle::PointingHand)
                        .hover(|style| style.bg(theme::surface_raised()))
                        .on_click(move |_, _, cx| {
                            if !url.is_empty() {
                                cx.open_url(&url);
                            }
                        })
                        .child(icon(
                            stack_review_icon(&review.state, review.draft),
                            13.0,
                            stack_review_color(&review.state, review.draft),
                        ))
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .text_size(crate::theme::caption_size())
                                .overflow_hidden()
                                .text_ellipsis()
                                .child(format!("#{} {}", review.number, review.title)),
                        )
                        .when(current, |row| {
                            row.child(div().text_size(crate::theme::caption_size()).text_color(theme::accent()).child("Current"))
                        })
                        .when_some(local_workspace, |row, workspace_id| {
                            row.child(
                                div()
                                    .id(SharedString::from(format!(
                                        "stack-open-workspace-{workspace_id}"
                                    )))
                                    .role(Role::Button)
                                    .aria_label("Open Workspace")
                                    .p_1()
                                    .rounded_sm()
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.select_workspace(workspace_id.clone(), cx);
                                        cx.stop_propagation();
                                    }))
                                    .child(icon(AleraIcon::FolderOpen, 13.0, theme::text_muted())),
                            )
                        })
                }));
        } else {
            card = card.child(
                div()
                    .mt_2()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::text_muted())
                    .child("This Pull Request Is Not Part Of A Native GitHub Stack."),
            );
        }
        if let Some(error) = self.forge_snapshot.stack_error.as_ref() {
            card = card.child(
                div()
                    .mt_2()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::danger())
                    .child(error.clone()),
            );
        }
        if self.forge_stack_editing {
            card = card.child(self.render_stack_number_editor(cx));
        } else if self.forge_stack_workspace_editing {
            card = card.child(self.render_stack_workspace_editor(&candidates, cx));
        } else {
            let workspace_label = if stack.is_some() {
                "Add Workspaces"
            } else {
                "Create From Workspaces"
            };
            let review_label = if stack.is_some() {
                "Add Pull Requests"
            } else {
                "Link Existing Pull Requests"
            };
            card = card.child(
                div()
                    .mt_3()
                    .flex()
                    .flex_wrap()
                    .gap_2()
                    .when(
                        candidates.len() >= if stack.is_some() { 1 } else { 2 },
                        |actions| {
                            actions.child(
                                design_system::button(
                                    "stack-workspaces",
                                    workspace_label,
                                    ButtonKind::Outlined,
                                    self.forge_busy,
                                )
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.begin_forge_stack_workspace_link(cx);
                                    },
                                )),
                            )
                        },
                    )
                    .child(
                        design_system::button(
                            "stack-reviews",
                            review_label,
                            ButtonKind::Outlined,
                            self.forge_busy,
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.begin_forge_stack_link(window, cx);
                        })),
                    ),
            );
        }
        card.into_any_element()
    }

    fn render_stack_number_editor(&self, cx: &mut Context<Self>) -> gpui::Div {
        div()
            .mt_3()
            .child(
                div()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::text_muted())
                    .child("Pull Request Numbers, Bottom To Top"),
            )
            .child(div().mt_1().child(Input::new(&self.forge_link_input)))
            .when_some(self.forge_form_error.clone(), |editor, error| {
                editor.child(
                    div()
                        .mt_2()
                        .text_size(crate::theme::caption_size())
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .child(
                div()
                    .mt_2()
                    .flex()
                    .justify_end()
                    .gap_2()
                    .child(
                        design_system::button(
                            "cancel-stack-link",
                            "Cancel",
                            ButtonKind::Text,
                            false,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.close_forge_stack_editor(cx);
                        })),
                    )
                    .child(
                        design_system::button(
                            "confirm-stack-link",
                            "Link Pull Requests",
                            ButtonKind::Filled,
                            self.forge_busy,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.submit_forge_stack_link(cx);
                        })),
                    ),
            )
    }

    fn render_stack_workspace_editor(
        &self,
        candidates: &[StackWorkspaceCandidate],
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        div()
            .mt_3()
            .child(
                div()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::text_muted())
                    .child("Workspace Layers, Bottom To Top"),
            )
            .children(candidates.iter().map(|workspace| {
                let id = workspace.id.clone();
                let selected = self
                    .forge_stack_selected_workspace_ids
                    .contains(&workspace.id);
                div()
                    .id(SharedString::from(format!(
                        "stack-workspace-{}",
                        workspace.id
                    )))
                    .mt_1()
                    .flex()
                    .items_center()
                    .gap_2()
                    .px_2()
                    .py_1()
                    .rounded_sm()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.toggle_forge_stack_workspace(id.clone(), cx);
                    }))
                    .child(icon(
                        if selected {
                            AleraIcon::Check
                        } else {
                            AleraIcon::Circle
                        },
                        13.0,
                        if selected {
                            theme::accent()
                        } else {
                            theme::text_faint()
                        },
                    ))
                    .child(div().flex_1().text_size(crate::theme::caption_size()).child(workspace.name.clone()))
                    .child(
                        div()
                            .text_size(crate::theme::caption_size())
                            .text_color(theme::text_muted())
                            .child(workspace.branch.clone()),
                    )
            }))
            .when_some(self.forge_form_error.clone(), |editor, error| {
                editor.child(
                    div()
                        .mt_2()
                        .text_size(crate::theme::caption_size())
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .child(
                div()
                    .mt_2()
                    .flex()
                    .justify_end()
                    .gap_2()
                    .child(
                        design_system::button(
                            "cancel-stack-workspaces",
                            "Cancel",
                            ButtonKind::Text,
                            false,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.close_forge_stack_editor(cx);
                        })),
                    )
                    .child(
                        design_system::button(
                            "confirm-stack-workspaces",
                            "Link Workspaces",
                            ButtonKind::Filled,
                            self.forge_busy,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.submit_forge_stack_workspaces(cx);
                        })),
                    ),
            )
    }
}

fn stack_review_icon(state: &str, draft: bool) -> AleraIcon {
    if draft {
        AleraIcon::Edit
    } else if state.eq_ignore_ascii_case("merged") {
        AleraIcon::GitMerge
    } else if state.eq_ignore_ascii_case("closed") {
        AleraIcon::GitPullRequestClosed
    } else {
        AleraIcon::GitPullRequest
    }
}

fn stack_review_color(state: &str, draft: bool) -> gpui::Rgba {
    if draft {
        theme::text_muted()
    } else if state.eq_ignore_ascii_case("merged") {
        theme::accent()
    } else if state.eq_ignore_ascii_case("closed") {
        theme::danger()
    } else {
        theme::success()
    }
}
