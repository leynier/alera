use gpui::{
    div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    IntoElement, MouseButton, MouseDownEvent, ParentElement as _, Styled as _,
};

use super::{AddProjectMode, AleraApp};
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_add_project_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
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
            .child(
                design_system::dialog_shell(614.0)
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(icon(AleraIcon::FolderSpecial, 18.0, theme::accent()))
                            .child("Add Project"),
                    )
                    .child(
                        div()
                            .mt_4()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(
                            "Choose An Existing Local Folder Or Clone A Git Repository From A URL.",
                        ),
                    )
                    .child(self.render_add_project_mode_selector(cx))
                    .child(self.render_add_project_fields(cx))
                    .when_some(self.error.clone(), |dialog, error| {
                        dialog.child(
                            div()
                                .mt_3()
                                .text_sm()
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
                            .mt_5()
                            .child(
                                design_system::button(
                                    "cancel-add-project",
                                    "Cancel",
                                    ButtonKind::Text,
                                    false,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                        this.close_add_project_dialog(cx);
                                        cx.stop_propagation();
                                    }),
                                ),
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
                                    button.cursor(CursorStyle::PointingHand).on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                            this.submit_add_project(cx);
                                            cx.stop_propagation();
                                        }),
                                    )
                                }),
                            ),
                    ),
            )
    }

    fn can_submit_add_project(&self, cx: &Context<Self>) -> bool {
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
            .rounded_md()
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
                AleraIcon::Download,
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
            .flex()
            .flex_1()
            .items_center()
            .justify_center()
            .h_full()
            .rounded_md()
            .text_sm()
            .font_weight(gpui::FontWeight::SEMIBOLD)
            .text_color(theme::text_muted())
            .cursor(CursorStyle::PointingHand)
            .gap_2()
            .when(selected, |button| {
                button
                    .bg(theme::surface_selected())
                    .text_color(theme::text())
            })
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                    this.select_add_project_mode(mode, cx);
                    cx.stop_propagation();
                }),
            )
            .child(icon(icon_kind, 14.0, theme::text_muted()))
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
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child("Alera Will Detect Whether The Folder Is A Git Repository. Non-Git Folders Only Get A Primary")
                    .child(div().child("Workspace.")),
            )
            .child(
                div().mt_6().child(
                    design_system::text_field(&self.local_project_path_input)
                        .label("Project Path")
                        .suffix(
                            design_system::icon_button(
                                "browse-local-project",
                                AleraIcon::FolderOpen,
                                true,
                                30.0,
                                None,
                                None,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, window, cx| {
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
            .child(div().text_sm().text_color(theme::text_muted()).child(
                "Alera Runs Git Clone Into The Destination Folder And Registers The Repository.",
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
                                AleraIcon::NewFolder,
                                true,
                                30.0,
                                None,
                                None,
                            )
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, window, cx| {
                                    this.browse_clone_parent(window, cx);
                                    cx.stop_propagation();
                                }),
                            ),
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
