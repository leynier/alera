use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, Context, CursorStyle, InteractiveElement as _,
    IntoElement as _, ParentElement as _, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::Input;

use super::AleraApp;
use crate::theme;
use crate::workspace_service::GitAction;

impl AleraApp {
    pub(super) fn refresh_git(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.git_snapshot(workspace_path).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(snapshot) => {
                        this.git_snapshot = snapshot;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn run_git_action(&mut self, action: GitAction, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.git_discard_armed = false;
        self.git_discard_path_armed = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.git_action(workspace_path.clone(), action).await;
            let snapshot = if result.is_ok() {
                service.git_snapshot(workspace_path).await.ok()
            } else {
                None
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
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn commit(&mut self, amend: bool, cx: &mut Context<Self>) {
        let message = self.commit_input.read(cx).value().trim().to_string();
        if message.is_empty() {
            self.local_message = Some("Enter A Commit Message".into());
            cx.notify();
            return;
        }
        let action = if amend {
            GitAction::Amend(message)
        } else {
            GitAction::Commit(message)
        };
        self.run_git_action(action, cx);
    }

    fn request_discard_all(&mut self, cx: &mut Context<Self>) {
        if !self.git_discard_armed {
            self.git_discard_armed = true;
            self.local_message =
                Some("Confirm Discarding All Workspace Changes By Clicking Again".into());
            cx.notify();
            return;
        }
        self.run_git_action(GitAction::DiscardAll, cx);
    }

    fn request_discard_path(&mut self, path: String, cx: &mut Context<Self>) {
        if self.git_discard_path_armed.as_deref() != Some(&path) {
            self.git_discard_path_armed = Some(path.clone());
            self.local_message = Some(format!("Click Discard Again To Revert {path}").into());
            cx.notify();
            return;
        }
        self.run_git_action(GitAction::DiscardPath(path), cx);
    }

    pub(super) fn render_git_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let snapshot = &self.git_snapshot;
        let change_rows =
            snapshot
                .changes
                .iter()
                .enumerate()
                .map(|(index, change)| {
                    let stage_path = change.path.clone();
                    let unstage_path = change.path.clone();
                    let discard_path = change.path.clone();
                    let discard_armed =
                        self.git_discard_path_armed.as_deref() == Some(change.path.as_str());
                    div()
                        .id(("git-change", index))
                        .flex()
                        .items_center()
                        .justify_between()
                        .px_3()
                        .py_2()
                        .border_b_1()
                        .border_color(theme::border())
                        .child(
                            div()
                                .flex()
                                .gap_2()
                                .child(
                                    div()
                                        .text_color(theme::accent())
                                        .child(change.status.clone()),
                                )
                                .child(change.path.clone()),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap_1()
                                .child(div().text_xs().text_color(theme::text_muted()).child(
                                    format!(
                                        "{} +{} -{}",
                                        change.area,
                                        change.added.unwrap_or(0),
                                        change.removed.unwrap_or(0)
                                    ),
                                ))
                                .child(git_button_owned(("stage-path", index), "Stage").on_click(
                                    cx.listener(move |this, _, _, cx| {
                                        this.run_git_action(
                                            GitAction::StagePath(stage_path.clone()),
                                            cx,
                                        );
                                    }),
                                ))
                                .child(
                                    git_button_owned(("unstage-path", index), "Unstage").on_click(
                                        cx.listener(move |this, _, _, cx| {
                                            this.run_git_action(
                                                GitAction::UnstagePath(unstage_path.clone()),
                                                cx,
                                            );
                                        }),
                                    ),
                                )
                                .child(
                                    git_button_owned(
                                        ("discard-path", index),
                                        if discard_armed { "Confirm" } else { "Discard" },
                                    )
                                    .when(discard_armed, |button| button.bg(theme::danger()))
                                    .on_click(cx.listener(
                                        move |this, _, _, cx| {
                                            this.request_discard_path(discard_path.clone(), cx);
                                        },
                                    )),
                                ),
                        )
                })
                .collect::<Vec<_>>();
        let stash_rows = snapshot
            .stashes
            .iter()
            .enumerate()
            .map(|(index, stash)| {
                div()
                    .id(("stash-row", index))
                    .flex()
                    .items_center()
                    .justify_between()
                    .px_3()
                    .py_2()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(stash.clone())
                    .child(
                        git_button_owned(("stash-pop", index), "Pop").on_click(cx.listener(
                            move |this, _, _, cx| {
                                this.run_git_action(GitAction::StashPop(index as u32), cx);
                            },
                        )),
                    )
            })
            .collect::<Vec<_>>();
        let patch_rows = snapshot
            .patch
            .iter()
            .enumerate()
            .map(|(index, line)| {
                let color = if line.contains(": +") {
                    theme::success()
                } else if line.contains(": -") {
                    theme::danger()
                } else {
                    theme::text_muted()
                };
                div()
                    .id(("patch-line", index))
                    .font_family("JetBrains Mono")
                    .text_sm()
                    .text_color(color)
                    .child(line.clone())
            })
            .collect::<Vec<_>>();
        let history_rows = snapshot
            .history
            .iter()
            .enumerate()
            .map(|(index, item)| {
                div()
                    .id(("history-row", index))
                    .px_3()
                    .py_2()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .font_family("JetBrains Mono")
                            .text_xs()
                            .text_color(theme::accent())
                            .child(item.id.clone()),
                    )
                    .child(item.subject.clone())
                    .when_some(item.author.clone(), |row, author| {
                        row.child(
                            div()
                                .text_xs()
                                .text_color(theme::text_muted())
                                .child(author),
                        )
                    })
            })
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
                    .child(
                        div()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(snapshot.branch.clone()),
                    )
                    .when_some(snapshot.upstream.clone(), |bar, upstream| {
                        bar.child(
                            div()
                                .text_xs()
                                .text_color(theme::text_muted())
                                .child(format!("Tracks {upstream}")),
                        )
                    })
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child(format!(
                                "Ahead {} · Behind {}{}",
                                snapshot.ahead,
                                snapshot.behind,
                                if snapshot.has_conflicts {
                                    " · Conflicts"
                                } else {
                                    ""
                                }
                            )),
                    )
                    .child(div().flex_1())
                    .child(git_button("git-refresh", "Refresh").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.refresh_git(cx);
                        },
                    )))
                    .child(git_button("git-stage", "Stage All").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.run_git_action(GitAction::StageAll, cx);
                        },
                    )))
                    .child(
                        git_button("git-unstage", "Unstage All").on_click(cx.listener(
                            |this, _, _, cx| {
                                this.run_git_action(GitAction::UnstageAll, cx);
                            },
                        )),
                    )
                    .child(
                        git_button(
                            "git-discard",
                            if self.git_discard_armed {
                                "Confirm Discard"
                            } else {
                                "Discard All"
                            },
                        )
                        .when(self.git_discard_armed, |button| button.bg(theme::danger()))
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.request_discard_all(cx);
                        })),
                    ),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .p_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(div().flex_1().child(Input::new(&self.commit_input)))
                    .child(git_button("git-commit", "Commit").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.commit(false, cx);
                        },
                    )))
                    .child(git_button("git-amend", "Amend").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.commit(true, cx);
                        },
                    )))
                    .child(git_button("git-fetch", "Fetch").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.run_git_action(GitAction::Fetch, cx);
                        },
                    )))
                    .child(git_button("git-pull", "Pull").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.run_git_action(GitAction::Pull, cx);
                        },
                    )))
                    .child(git_button("git-push", "Push").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.run_git_action(GitAction::Push, cx);
                        },
                    )))
                    .child(git_button("git-stash", "Stash").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.run_git_action(GitAction::Stash, cx);
                        },
                    ))),
            )
            .child(
                div()
                    .flex()
                    .flex_1()
                    .overflow_hidden()
                    .child(
                        section("Changes", change_rows)
                            .w(gpui::relative(0.34))
                            .border_r_1()
                            .border_color(theme::border()),
                    )
                    .child(
                        section("Diff", patch_rows)
                            .w(gpui::relative(0.38))
                            .border_r_1()
                            .border_color(theme::border()),
                    )
                    .child(section("History", history_rows).flex_1()),
            )
            .when(!stash_rows.is_empty(), |surface| {
                surface.child(
                    div()
                        .h(gpui::px(112.0))
                        .border_t_1()
                        .border_color(theme::border())
                        .child(section("Stashes", stash_rows)),
                )
            })
            .into_any_element()
    }
}

fn git_button(id: &'static str, label: &'static str) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .px_3()
        .py_1()
        .rounded_md()
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(label)
}

fn git_button_owned(
    id: impl Into<gpui::ElementId>,
    label: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .px_2()
        .py_1()
        .rounded_md()
        .bg(theme::surface_selected())
        .cursor(CursorStyle::PointingHand)
        .child(label)
}

fn section(title: &'static str, rows: Vec<gpui::Stateful<gpui::Div>>) -> gpui::Stateful<gpui::Div> {
    div()
        .id(title)
        .flex()
        .flex_col()
        .h_full()
        .overflow_y_scroll()
        .child(
            div()
                .px_3()
                .py_2()
                .bg(theme::surface())
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title),
        )
        .children(rows)
}
