use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::input::{Input, Textarea};
use gpui_component::tooltip::Tooltip;

use super::AleraApp;
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_pull_request_composer(&self, cx: &mut Context<Self>) -> AnyElement {
        // Flutter opens the create form whenever creation is possible, even
        // when the provider reports an unlinked/suggested review. The
        // suggested review is shown only after choosing the link flow.
        if self.forge_link_form_open || self.forge_snapshot.branch.is_empty() {
            return self.render_pull_request_link_form(cx);
        }
        let base_value = self.forge_base_input.read(cx).value().to_string();
        let form_enabled = !self.forge_busy && !self.forge_ai_busy;
        let can_generate = self.settings_state.ai_assist_enabled
            && form_enabled
            && !self.forge_snapshot.branch.is_empty()
            && !base_value.trim().is_empty();
        let forge_ai_busy = self.forge_ai_busy;
        let create_draft = self.forge_create_draft;
        div()
            .id("pull-request-composer")
            .relative()
            .flex()
            .flex_col()
            .flex_1()
            .min_h_0()
            .px(px(16.0))
            .py(px(12.0))
            .gap_3()
            .child(
                div()
                    .id("context-pr-header")
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
                            "context-refresh-pull-request",
                            if self.forge_busy {
                                AleraIcon::Loading
                            } else {
                                AleraIcon::Refresh
                            },
                        )
                        .aria_label("Refresh")
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh")).into())
                        .on_click(cx.listener(|this, _, _, cx| {
                            if !this.forge_busy {
                                this.refresh_forge(cx);
                            }
                        })),
                    ),
            )
            .when_some(self.forge_error.clone(), |panel, error| {
                panel.child(super::context_pull_request::pull_request_error_banner(
                    error,
                ))
            })
            .child(field_label("Base Branch").mt(px(8.0)))
            .child(
                div()
                    .id("context-base-branch-select")
                    .focusable()
                    .tab_stop(form_enabled)
                    .role(Role::ComboBox)
                    .aria_label("Base Branch")
                    .aria_expanded(self.forge_base_menu_open)
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .px_3()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .cursor(if form_enabled {
                        CursorStyle::PointingHand
                    } else {
                        CursorStyle::Arrow
                    })
                    .when(form_enabled, |field| {
                        field.on_click(cx.listener(|this, _, _, cx| {
                            this.forge_base_menu_open = !this.forge_base_menu_open;
                            this.forge_create_menu_open = false;
                            cx.notify();
                        }))
                    })
                    .child(div().flex_1().text_sm().child(base_value))
                    .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_muted())),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(field_label("Title"))
                    .when(
                        self.settings_state.ai_assist_enabled || self.forge_ai_busy,
                        |row| {
                            row.child(
                                div()
                                    .id("context-generate-pr-details")
                                    .focusable()
                                    .tab_stop(can_generate || self.forge_ai_busy)
                                    .role(Role::Button)
                                    .aria_label(if forge_ai_busy {
                                        "Stop Generating Pull Request Details"
                                    } else {
                                        "Generate Title And Description With AI"
                                    })
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(24.0))
                                    .h(px(24.0))
                                    .rounded_md()
                                    .text_xs()
                                    .text_color(theme::accent())
                                    .cursor(if can_generate || self.forge_ai_busy {
                                        CursorStyle::PointingHand
                                    } else {
                                        CursorStyle::Arrow
                                    })
                                    .when(can_generate || self.forge_ai_busy, |button| {
                                        button
                                            .tooltip(move |_, cx| {
                                                cx.new(|_| {
                                                    Tooltip::new(if forge_ai_busy {
                                                        "Stop Generating Pull Request Details"
                                                    } else {
                                                        "Generate Title And Description With AI"
                                                    })
                                                })
                                                .into()
                                            })
                                            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                                                if this.forge_ai_hovered != *hovered {
                                                    this.forge_ai_hovered = *hovered;
                                                    cx.notify();
                                                }
                                            }))
                                            .hover(|style| style.bg(theme::surface_selected()))
                                            .on_click(cx.listener(|this, _, window, cx| {
                                                if this.forge_ai_busy {
                                                    this.cancel_pull_request_generation(cx);
                                                } else {
                                                    this.generate_pull_request_details(window, cx);
                                                }
                                            }))
                                    })
                                    .child(icon(
                                        if self.forge_ai_busy {
                                            if self.forge_ai_hovered {
                                                AleraIcon::Stop
                                            } else {
                                                AleraIcon::Loading
                                            }
                                        } else {
                                            AleraIcon::Ai
                                        },
                                        14.0,
                                        if self.forge_ai_busy {
                                            theme::danger()
                                        } else {
                                            theme::text_muted()
                                        },
                                    )),
                            )
                        },
                    ),
            )
            .child(
                div()
                    .relative()
                    .child(Input::new(&self.forge_title_input).disabled(!form_enabled))
                    .when(self.forge_ai_busy, |field| {
                        field.child(
                            div()
                                .absolute()
                                .inset_0()
                                .rounded_md()
                                .bg(theme::overlay_scrim()),
                        )
                    }),
            )
            .child(field_label("Description"))
            .child(
                div()
                    .relative()
                    .h(px(64.0))
                    .child(
                        Textarea::new(&self.forge_body_input)
                            .disabled(!form_enabled)
                            .h_full(),
                    )
                    .when(self.forge_ai_busy, |field| {
                        field.child(
                            div()
                                .absolute()
                                .inset_0()
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_md()
                                .border_1()
                                .border_color(theme::border_subtle())
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
                                        .child(icon(AleraIcon::Loading, 14.0, theme::text_muted()))
                                        .child("Generating With AI"),
                                ),
                        )
                    }),
            )
            .when_some(self.forge_form_error.clone(), |form, error| {
                form.child(div().text_sm().text_color(theme::danger()).child(error))
            })
            .child(
                div()
                    .flex()
                    .gap_1()
                    .child(
                        pr_button_with_icon(
                            "context-create-pr",
                            if create_draft {
                                AleraIcon::Edit
                            } else {
                                AleraIcon::GitPullRequest
                            },
                            if create_draft {
                                "Draft Pull Request"
                            } else {
                                "Create Pull Request"
                            },
                            true,
                        )
                        .flex_1()
                        .when(form_enabled, |button| {
                            button.on_click(cx.listener(move |this, _, _, cx| {
                                this.create_review(create_draft, cx);
                            }))
                        })
                        .when(!form_enabled, |button| button.cursor(CursorStyle::Arrow))
                        .h(px(28.0))
                        .min_h(px(28.0)),
                    )
                    .child(
                        pr_icon_button_with_style(
                            "context-create-draft",
                            AleraIcon::ChevronDown,
                            true,
                        )
                        .aria_label("Pull Request Type")
                        .when(form_enabled, |button| {
                            button.on_click(cx.listener(|this, _, _, cx| {
                                this.forge_create_menu_open = !this.forge_create_menu_open;
                                this.forge_base_menu_open = false;
                                cx.notify();
                            }))
                        })
                        .when(!form_enabled, |button| button.cursor(CursorStyle::Arrow))
                        .w(px(34.0))
                        .h(px(28.0))
                        .min_h(px(28.0))
                        .px_0(),
                    ),
            )
            .child(div().flex_1())
            .child(
                div()
                    .id("context-open-link-pr")
                    .focusable()
                    .tab_stop(form_enabled)
                    .role(Role::Button)
                    .aria_label("Link Existing Pull Request")
                    .flex()
                    .items_center()
                    .justify_center()
                    .h(px(40.0))
                    .text_sm()
                    .text_color(theme::text_muted())
                    .cursor(if form_enabled {
                        CursorStyle::PointingHand
                    } else {
                        CursorStyle::Arrow
                    })
                    .when(form_enabled, |button| {
                        button.on_click(cx.listener(|this, _, _, cx| {
                            this.forge_link_form_open = true;
                            this.forge_form_error = None;
                            cx.notify();
                        }))
                    })
                    .child("Link Existing Pull Request"),
            )
            .when(self.forge_base_menu_open, |composer| {
                let mut options = self.forge_snapshot.base_branches.clone();
                if options.is_empty() {
                    options.push(if self.forge_snapshot.suggested_base_branch.is_empty() {
                        "main".to_owned()
                    } else {
                        self.forge_snapshot.suggested_base_branch.clone()
                    });
                }
                if !self.forge_snapshot.branch.is_empty()
                    && !options.contains(&self.forge_snapshot.branch)
                {
                    options.push(self.forge_snapshot.branch.clone());
                }
                let menu_width = options
                    .iter()
                    .map(|branch| branch.chars().count() as f32 * 7.8 + 54.0)
                    .fold(266.0_f32, f32::max)
                    .min(520.0);
                composer.child(
                    div()
                        .id("context-base-branch-menu")
                        .role(Role::Menu)
                        .aria_label("Base Branch")
                        .absolute()
                        .top(px(113.0))
                        .right(px(12.0))
                        .w(px(menu_width))
                        .occlude()
                        .rounded_md()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface_raised())
                        .shadow_lg()
                        .py_1()
                        .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                            this.forge_base_menu_open = false;
                            cx.notify();
                        }))
                        .children(options.into_iter().enumerate().map(|(index, branch)| {
                            let selected_branch = branch.clone();
                            let is_selected =
                                self.forge_base_input.read(cx).value() == branch.as_str();
                            div()
                                .id(("context-base-branch-option", index))
                                .focusable()
                                .tab_stop(true)
                                .role(Role::MenuItem)
                                .aria_label(branch.clone())
                                .aria_selected(is_selected)
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_click(cx.listener(move |this, _, window, cx| {
                                    this.forge_base_menu_open = false;
                                    this.forge_base_input.update(cx, |input, cx| {
                                        input.set_value(selected_branch.clone(), window, cx);
                                    });
                                    cx.notify();
                                }))
                                .child(div().flex_1().child(branch))
                                .when(is_selected, |row| {
                                    row.child(icon(AleraIcon::Check, 13.0, theme::accent()))
                                })
                        })),
                )
            })
            .when(self.forge_create_menu_open, |composer| {
                composer.child(
                    div()
                        .id("context-create-pr-menu")
                        .role(Role::Menu)
                        .aria_label("Pull Request Type")
                        .absolute()
                        .top(px(274.0))
                        .right(px(16.0))
                        .w(px(210.0))
                        .occlude()
                        .rounded_md()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface_raised())
                        .shadow_lg()
                        .py_1()
                        .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                            this.forge_create_menu_open = false;
                            cx.notify();
                        }))
                        .child(
                            div()
                                .id("context-create-publish-option")
                                .focusable()
                                .tab_stop(true)
                                .role(Role::MenuItem)
                                .aria_label("Create Pull Request")
                                .aria_selected(!create_draft)
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .gap_2()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.forge_create_menu_open = false;
                                    this.forge_create_draft = false;
                                    this.persist_sidebar_view_prefs(cx);
                                    cx.notify();
                                }))
                                .child(icon(AleraIcon::GitPullRequest, 14.0, theme::text_muted()))
                                .child(div().flex_1().child("Create Pull Request"))
                                .when(!create_draft, |row| {
                                    row.child(icon(AleraIcon::Check, 13.0, theme::accent()))
                                }),
                        )
                        .child(
                            div()
                                .id("context-create-draft-option")
                                .focusable()
                                .tab_stop(true)
                                .role(Role::MenuItem)
                                .aria_label("Draft Pull Request")
                                .aria_selected(create_draft)
                                .flex()
                                .items_center()
                                .h(px(30.0))
                                .px_3()
                                .gap_2()
                                .text_sm()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_selected()))
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.forge_create_menu_open = false;
                                    this.forge_create_draft = true;
                                    this.persist_sidebar_view_prefs(cx);
                                    cx.notify();
                                }))
                                .child(icon(AleraIcon::Edit, 14.0, theme::text_muted()))
                                .child(div().flex_1().child("Draft Pull Request"))
                                .when(create_draft, |row| {
                                    row.child(icon(AleraIcon::Check, 13.0, theme::accent()))
                                }),
                        ),
                )
            })
            .into_any_element()
    }

    fn render_pull_request_link_form(&self, cx: &mut Context<Self>) -> AnyElement {
        let can_link = !self.forge_busy;
        // A suggested review does not disable creation in Flutter. It merely
        // remains available as a candidate in the link form.
        let can_create = !self.forge_snapshot.branch.is_empty();
        div()
            .id("pull-request-link-form")
            .flex()
            .flex_col()
            .flex_1()
            .p_3()
            .gap_3()
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
                            "context-refresh-link-pr",
                            if self.forge_busy {
                                AleraIcon::Loading
                            } else {
                                AleraIcon::Refresh
                            },
                        )
                        .aria_label("Refresh")
                        .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh")).into())
                        .on_click(cx.listener(|this, _, _, cx| {
                            if !this.forge_busy {
                                this.refresh_forge(cx);
                            }
                        })),
                    ),
            )
            .child(
                div()
                    .mt_2()
                    .text_sm()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Link Pull Request"),
            )
            .child(field_label("Pull Request"))
            .child(Input::new(&self.forge_link_input))
            .when_some(
                self.forge_snapshot.suggested_review.as_ref(),
                |form, suggestion| {
                    let number = suggestion.number;
                    form.child(field_label("Suggested Pull Request")).child(
                        div()
                            .id("context-suggested-pr")
                            .focusable()
                            .tab_stop(can_link)
                            .role(Role::Button)
                            .aria_label("Suggested Pull Request")
                            .flex()
                            .items_center()
                            .w_full()
                            .min_h(px(42.0))
                            .px_3()
                            .gap_2()
                            .rounded_md()
                            .border_1()
                            .border_color(theme::border_subtle())
                            .bg(theme::surface_raised())
                            .cursor(if can_link {
                                CursorStyle::PointingHand
                            } else {
                                CursorStyle::Arrow
                            })
                            .when(can_link, |card| {
                                card.hover(|style| style.bg(theme::surface_selected()))
                                    .on_click(cx.listener(move |this, _, window, cx| {
                                        this.forge_link_input.update(cx, |input, cx| {
                                            input.set_value(format!("#{number}"), window, cx);
                                        });
                                        this.forge_form_error = None;
                                        cx.notify();
                                    }))
                            })
                            .child(icon(AleraIcon::GitPullRequest, 16.0, theme::text_muted()))
                            .child(
                                div().flex_1().text_sm().overflow_hidden().child(format!(
                                    "#{} · {}",
                                    suggestion.number, suggestion.title
                                )),
                            ),
                    )
                },
            )
            .when_some(self.forge_form_error.clone(), |form, error| {
                form.child(div().text_sm().text_color(theme::danger()).child(error))
            })
            .child(
                pr_button_with_icon("context-link-pr", AleraIcon::Link, "Link", true)
                    .w_full()
                    .when(!can_link, |button| {
                        button
                            .bg(theme::surface_selected())
                            .text_color(theme::text_faint())
                            .cursor(CursorStyle::Arrow)
                    })
                    .when(can_link, |button| {
                        button.on_click(cx.listener(|this, _, _, cx| {
                            this.link_existing_review(cx);
                        }))
                    }),
            )
            .child(div().flex_1())
            .when(can_create, |form| {
                form.child(
                    div()
                        .id("context-return-create-pr")
                        .focusable()
                        .tab_stop(true)
                        .role(Role::Button)
                        .aria_label("Create Pull Request")
                        .flex()
                        .items_center()
                        .justify_center()
                        .h(px(34.0))
                        .rounded_md()
                        .bg(theme::surface_selected())
                        .text_sm()
                        .cursor(CursorStyle::PointingHand)
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.forge_link_form_open = false;
                            this.forge_form_error = None;
                            cx.notify();
                        }))
                        .child("Create Pull Request"),
                )
            })
            .into_any_element()
    }
}

fn field_label(label: &'static str) -> gpui::Div {
    div().text_xs().text_color(theme::text_muted()).child(label)
}

fn pr_button_with_icon(
    id: &'static str,
    kind: AleraIcon,
    label: &'static str,
    filled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
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
        .rounded_lg()
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
    pr_icon_button_with_style(id, kind, false)
}

fn pr_icon_button_with_style(
    id: &'static str,
    kind: AleraIcon,
    filled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .flex()
        .items_center()
        .justify_center()
        .w(px(30.0))
        .h(px(30.0))
        .rounded_md()
        .when(filled, |button| button.bg(theme::accent()))
        .text_color(if filled {
            theme::on_accent()
        } else {
            theme::text_muted()
        })
        .cursor(CursorStyle::PointingHand)
        .hover(move |style| {
            style.bg(if filled {
                theme::accent_hover()
            } else {
                theme::surface_selected()
            })
        })
        .when(filled, |button| button.rounded_lg())
        .child(icon(
            kind,
            if filled { 14.0 } else { 16.0 },
            if filled {
                theme::on_accent()
            } else {
                theme::text_muted()
            },
        ))
}
