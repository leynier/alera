use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle, Focusable as _,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::InputState;

use super::settings_state::ClaudeQuotaProfile;
use super::AleraApp;
use crate::{design_system, theme};

impl AleraApp {
    pub(super) fn open_claude_profile_dialog(
        &mut self,
        index: Option<usize>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let profile = index.and_then(|index| self.settings_state.claude_profiles.get(index));
        let alias = profile
            .map(|profile| profile.alias.clone())
            .unwrap_or_default();
        let name = profile
            .map(|profile| profile.profile.clone())
            .unwrap_or_default();
        let usage_name = profile
            .and_then(|profile| profile.usage_display_name.clone())
            .or_else(|| profile.map(|profile| profile.alias.clone()))
            .unwrap_or_default();
        self.claude_profile_show_in_usage = profile
            .map(|profile| profile.show_in_usage)
            .unwrap_or(true);
        self.claude_profile_alias_input
            .update(cx, |input, cx| input.set_value(alias, window, cx));
        self.claude_profile_name_input
            .update(cx, |input, cx| input.set_value(name, window, cx));
        self.claude_profile_usage_name_input
            .update(cx, |input, cx| input.set_value(usage_name, window, cx));
        self.editing_claude_profile_index = index;
        self.claude_profile_error = None;
        self.show_claude_profile_dialog = true;
        self.claude_profile_alias_input
            .focus_handle(cx)
            .focus(window, cx);
        cx.notify();
    }

    pub(super) fn close_claude_profile_dialog(&mut self, cx: &mut Context<Self>) {
        self.show_claude_profile_dialog = false;
        self.editing_claude_profile_index = None;
        self.claude_profile_error = None;
        cx.notify();
    }

    pub(super) fn save_claude_profile(&mut self, cx: &mut Context<Self>) {
        let alias = self
            .claude_profile_alias_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        let profile = self
            .claude_profile_name_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        let usage_display_name = self
            .claude_profile_usage_name_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        if alias.is_empty() || profile.is_empty() {
            self.claude_profile_error = Some("Alias And Profile Are Required.".to_string());
            cx.notify();
            return;
        }
        let editing = self.editing_claude_profile_index;
        let duplicate =
            self.settings_state
                .claude_profiles
                .iter()
                .enumerate()
                .any(|(index, candidate)| {
                    Some(index) != editing
                        && (candidate.alias == alias || candidate.profile == profile)
                });
        if duplicate {
            self.claude_profile_error = Some("Alias And Profile Must Be Unique.".to_string());
            cx.notify();
            return;
        }
        let next = ClaudeQuotaProfile {
            alias,
            profile,
            show_in_usage: self.claude_profile_show_in_usage,
            usage_display_name: (!usage_display_name.is_empty()).then_some(usage_display_name),
        };
        self.update_quota_settings(
            |settings| {
                if let Some(index) = editing {
                    if let Some(profile) = settings.claude_profiles.get_mut(index) {
                        *profile = next;
                    }
                } else {
                    settings.claude_profiles.push(next);
                }
            },
            cx,
        );
        self.close_claude_profile_dialog(cx);
    }

    pub(super) fn move_claude_profile(
        &mut self,
        index: usize,
        offset: isize,
        cx: &mut Context<Self>,
    ) {
        let target = index as isize + offset;
        if target < 0 || target >= self.settings_state.claude_profiles.len() as isize {
            return;
        }
        self.update_quota_settings(
            |settings| settings.claude_profiles.swap(index, target as usize),
            cx,
        );
    }

    pub(super) fn remove_claude_profile(&mut self, index: usize, cx: &mut Context<Self>) {
        if index >= self.settings_state.claude_profiles.len() {
            return;
        }
        self.update_quota_settings(
            |settings| {
                let removed = settings.claude_profiles.remove(index);
                settings
                    .quota_unpinned_keys
                    .remove(&format!("claude:{}", removed.profile));
            },
            cx,
        );
    }

    pub(super) fn render_claude_profile_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .absolute()
            .inset_0()
            .flex()
            .items_center()
            .justify_center()
            .occlude()
            .bg(theme::overlay_scrim())
            .child(
                div()
                    .id("claude-profile-dialog")
                    .role(Role::Dialog)
                    .aria_label(if self.editing_claude_profile_index.is_some() {
                        "Edit CCS Profile"
                    } else {
                        "Add CCS Profile"
                    })
                    .w(px(480.0))
                    .p_6()
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .shadow_lg()
                    .child(
                        div()
                            .text_size(px(18.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(if self.editing_claude_profile_index.is_some() {
                                "Edit CCS Profile"
                            } else {
                                "Add CCS Profile"
                            }),
                    )
                    .child(profile_input("Alias", &self.claude_profile_alias_input))
                    .child(profile_input(
                        "CCS Profile",
                        &self.claude_profile_name_input,
                    ))
                    .child(
                        div()
                            .id("claude-profile-show-in-usage")
                            .role(gpui::Role::CheckBox)
                            .aria_label("Show In Usage")
                            .flex()
                            .items_center()
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.claude_profile_show_in_usage =
                                    !this.claude_profile_show_in_usage;
                                cx.notify();
                            }))
                            .child(design_system::checkbox(
                                self.claude_profile_show_in_usage,
                                true,
                                Some("Show In Usage".into()),
                            )),
                    )
                    .child(profile_input(
                        "Usage Name",
                        &self.claude_profile_usage_name_input,
                    ))
                    .when_some(self.claude_profile_error.clone(), |dialog, error| {
                        dialog.child(
                            div()
                                .mt_2()
                                .text_size(px(12.0))
                                .text_color(theme::danger())
                                .child(error),
                        )
                    })
                    .child(
                        div()
                            .mt_5()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .child(
                                dialog_button("cancel-claude-profile", "Cancel", false).on_click(
                                    cx.listener(|this, _, _, cx| {
                                        this.close_claude_profile_dialog(cx);
                                    }),
                                ),
                            )
                            .child(
                                dialog_button("save-claude-profile", "Save Profile", true)
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.save_claude_profile(cx);
                                    })),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn profile_input(label: &'static str, input: &gpui::Entity<InputState>) -> gpui::Div {
    div()
        .mt_3()
        .child(
            div()
                .mb_1()
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(design_system::text_field(input))
}

fn dialog_button(
    id: &'static str,
    label: &'static str,
    primary: bool,
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
        .h(px(34.0))
        .px_3()
        .rounded_lg()
        .cursor(CursorStyle::PointingHand)
        .border_1()
        .border_color(if primary {
            theme::accent()
        } else {
            theme::border()
        })
        .bg(if primary {
            theme::accent()
        } else {
            theme::surface()
        })
        .text_color(if primary {
            theme::on_accent()
        } else {
            theme::text()
        })
        .hover(|style| style.bg(theme::surface_raised()))
        .child(label)
}
