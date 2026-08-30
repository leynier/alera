use gpui::{
    div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    AnyElement, IntoElement, MouseButton, ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _, Toggled,
};

use super::{AddProjectMode, AleraApp};
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_add_project_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        if self.add_project_busy {
            return div().absolute().inset_0().occlude().flex().items_center().justify_center()
                .bg(theme::overlay_scrim())
                .child(design_system::dialog_shell("add-project-progress", "Cloning Repository", 360.0)
                    .flex().items_center().gap(px(12.0))
                    .child(crate::icons::loading_indicator(20.0, theme::accent()))
                    .child("Cloning repository…"))
                .into_any_element();
        }
        let submit_enabled = self.can_submit_add_project(cx) && !self.add_project_busy;
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, window, cx| {
                this.close_add_project_dialog(window, cx);
            }))
            .child(
                design_system::dialog_shell("add-project-dialog", "Add Project", 600.0)
                    .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .text_size(crate::theme::title_size())
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(icon(AleraIcon::FolderSpecial, 18.0, theme::accent()))
                            .child("Add Project"),
                    )
                    .child(
                        div()
                            .mt_4()
                            .text_size(crate::theme::caption_size())
                            .text_color(theme::text_muted())
                            .child(
                            "Choose an existing local folder or clone a Git repository from a URL.",
                        ),
                    )
                    .child(self.render_add_project_mode_selector(cx))
                    .child(self.render_add_project_fields(cx))
                    .when_some(self.error.clone(), |dialog, error| {
                        dialog.child(
                            div()
                                .mt_3()
                                .text_size(crate::theme::body_size())
                                .text_color(theme::danger())
                                .child(error),
                        )
                    })
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_end()
                            .gap_2()
                            .mt_4()
                            .child(
                                design_system::button(
                                    "cancel-add-project",
                                    "Cancel",
                                    ButtonKind::Text,
                                    false,
                                )
                                .on_click(cx.listener(
                                    |this, _, window, cx| {
                                        this.close_add_project_dialog(window, cx);
                                        cx.stop_propagation();
                                    },
                                )),
                            )
                            .child(
                                design_system::button_with_loading(
                                    "submit-add-project",
                                    if self.add_project_busy {
                                        match self.add_project_mode {
                                            AddProjectMode::LocalFolder => "Adding Project",
                                            AddProjectMode::CloneFromUrl => "Cloning Project",
                                        }
                                    } else {
                                        "Add Project"
                                    },
                                    ButtonKind::Filled,
                                    !submit_enabled && !self.add_project_busy,
                                    self.add_project_busy,
                                )
                                .when(submit_enabled, |button| {
                                    button
                                        .cursor(CursorStyle::PointingHand)
                                        .on_click(cx.listener(|this, _, window, cx| {
                                            this.submit_add_project(window, cx);
                                            cx.stop_propagation();
                                        }))
                                }),
                            ),
                    ),
            ).into_any_element()
    }

    pub(super) fn can_submit_add_project(&self, cx: &Context<Self>) -> bool {
        match self.add_project_mode {
            AddProjectMode::LocalFolder => !self
                .local_project_path_input
                .read(cx)
                .value()
                .trim()
                .is_empty(),
            AddProjectMode::CloneFromUrl => {
                !self
                    .clone_project_url_input
                    .read(cx)
                    .value()
                    .trim()
                    .is_empty()
                    && !self
                        .clone_project_destination_input
                        .read(cx)
                        .value()
                        .trim()
                        .is_empty()
            }
        }
    }

    fn render_add_project_mode_selector(&self, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .mt_4()
            .w(px(314.0))
            .h(px(32.0))
            .rounded(px(6.0))
            .border_1()
            .border_color(theme::border())
            .child(self.add_project_mode_button(
                AddProjectMode::LocalFolder,
                AleraIcon::FolderOpen,
                "Local Folder",
                cx,
            ))
            .child(self.add_project_mode_button(
                AddProjectMode::CloneFromUrl,
                AleraIcon::CloudDownload,
                "Clone From URL",
                cx,
            ))
    }

    fn add_project_mode_button(
        &self,
        mode: AddProjectMode,
        icon_kind: AleraIcon,
        label: &'static str,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let selected = self.add_project_mode == mode;
        div()
            .id(match mode {
                AddProjectMode::LocalFolder => "add-local-project-mode",
                AddProjectMode::CloneFromUrl => "add-clone-project-mode",
            })
            .focusable()
            .tab_stop(true)
            .role(Role::RadioButton)
            .aria_label(label)
            .aria_selected(selected)
            .aria_toggled(if selected {
                Toggled::True
            } else {
                Toggled::False
            })
            .flex()
            .flex_1()
            .items_center()
            .justify_center()
            .h_full()
            .rounded_md()
            .text_size(crate::theme::body_size())
            .font_weight(gpui::FontWeight::MEDIUM)
            .text_color(theme::text_muted())
            .cursor(CursorStyle::PointingHand)
            .gap_2()
            .when(selected, |button| {
                button
                    .bg(theme::surface_selected())
                    .text_color(theme::text())
            })
            .on_click(cx.listener(move |this, _, window, cx| {
                this.select_add_project_mode(mode, window, cx);
                cx.stop_propagation();
            }))
            .child(icon(icon_kind, 16.0, theme::text_muted()))
            .child(label)
    }

    fn render_add_project_fields(&self, cx: &mut Context<Self>) -> impl IntoElement {
        match self.add_project_mode {
            AddProjectMode::LocalFolder => self.render_local_project_fields(cx).into_any_element(),
            AddProjectMode::CloneFromUrl => self.render_clone_project_fields(cx).into_any_element(),
        }
    }

    fn render_local_project_fields(&self, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .mt_4()
            .child(
                div()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::text_muted())
                    .child("Alera will detect whether the folder is a Git repository. Non-Git folders only get a primary workspace."),
            )
            .child(
                div().mt_3().child(
                    design_system::text_field(&self.local_project_path_input)
                        .label("Project Path")
                        .suffix(
                            design_system::icon_button(
                                "browse-local-project",
                                "Browse",
                                AleraIcon::FolderOpen,
                                true,
                                30.0,
                                None,
                                None,
                            )
                            .on_click(
                                cx.listener(|this, _, window, cx| {
                                    this.browse_local_project(window, cx);
                                    cx.stop_propagation();
                                }),
                            ),
                        ),
                ),
            )
            .child(self.render_display_name_field())
    }

    fn render_clone_project_fields(&self, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .mt_4()
            .child(div().text_size(crate::theme::caption_size()).text_color(theme::text_muted()).child(
                "Alera will run git clone into the destination folder and register the cloned repository.",
            ))
            .child(
                div().mt_3().child(
                    design_system::text_field(&self.clone_project_url_input).label("Git URL"),
                ),
            )
            .child(
                div().mt_3().child(
                    design_system::text_field(&self.clone_project_destination_input)
                        .label("Destination Folder")
                        .suffix(
                            design_system::icon_button(
                                "browse-clone-parent",
                                "Choose Parent Folder",
                                AleraIcon::NewFolder,
                                true,
                                30.0,
                                None,
                                None,
                            )
                            .on_click(cx.listener(
                                |this, _, window, cx| {
                                    this.browse_clone_parent(window, cx);
                                    cx.stop_propagation();
                                },
                            )),
                        ),
                ),
            )
            .child(self.render_display_name_field())
    }

    fn render_display_name_field(&self) -> impl IntoElement {
        div().mt_3().child(
            design_system::text_field(&self.project_display_name_input)
                .label("Display Name (Optional)"),
        )
    }
}
