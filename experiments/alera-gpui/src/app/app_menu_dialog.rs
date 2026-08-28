use gpui::{
    div, prelude::FluentBuilder as _, px, AppContext as _, ClipboardItem, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{alera_logo, icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(crate) fn open_about_dialog(&mut self, cx: &mut Context<Self>) {
        self.show_about_dialog = true;
        self.dismiss_status_popover(cx);
        cx.notify();
    }

    fn close_about_dialog(&mut self, cx: &mut Context<Self>) {
        self.show_about_dialog = false;
        cx.notify();
    }

    pub(super) fn render_about_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let version = format!(
            "Version {} ({})",
            env!("CARGO_PKG_VERSION"),
            option_env!("ALERA_BUILD_NUMBER").unwrap_or("76")
        );
        let copy_version = version.clone();
        let update_busy = self.settings_state.update_busy;
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
                design_system::dialog_shell("about-dialog", "About Alera", 400.0)
                    // Flutter's About dialog is capped at 400 logical px; on
                    // a scaled macOS display that produces the same roughly
                    // 310 physical px surface as the reference dialog.
                    .w(px(400.0))
                    .px(px(16.0))
                    // Keep the compact vertical rhythm of Flutter's
                    // intrinsic Dialog. The shared shell defaults to 20 px,
                    // which makes this small modal visibly too tall.
                    .pt(px(4.0))
                    .pb(px(4.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child(format!("About {}", crate::app_display_name())),
                            )
                            .child(
                                div()
                                    .id("close-about")
                                    .focusable()
                                    .tab_stop(true)
                                    .role(Role::Button)
                                    .aria_label("Close")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .tooltip(|_, cx| {
                                        cx.new(|_| gpui_component::tooltip::Tooltip::new("Close"))
                                            .into()
                                    })
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.close_about_dialog(cx);
                                    }))
                                    .child(icon(AleraIcon::Close, 14.0, theme::text_muted())),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_center()
                            .mt(px(16.0))
                            .child(alera_logo(64.0)),
                    )
                    .child(
                        div()
                            .mt(px(12.0))
                            .flex()
                            .justify_center()
                            .text_size(px(14.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child(crate::app_display_name()),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_center()
                            .gap(px(4.0))
                            .mt(px(4.0))
                            .text_size(px(13.0))
                            .text_color(theme::text_muted())
                            .child(version)
                            .child(
                                div()
                                    .id("copy-about-version")
                                    .focusable()
                                    .tab_stop(true)
                                    .role(Role::Button)
                                    .aria_label("Copy Version")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(24.0))
                                    .h(px(24.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .tooltip(|_, cx| {
                                        cx.new(|_| {
                                            gpui_component::tooltip::Tooltip::new("Copy Version")
                                        })
                                        .into()
                                    })
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        cx.write_to_clipboard(ClipboardItem::new_string(
                                            copy_version.clone(),
                                        ));
                                        this.local_message = Some("Version Copied".into());
                                        cx.notify();
                                    }))
                                    .child(icon(AleraIcon::Copy, 14.0, theme::text_muted())),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap(px(8.0))
                            .mt(px(20.0))
                            .child(
                                design_system::button(
                                    "about-check-for-updates",
                                    "Check For Updates",
                                    ButtonKind::Outlined,
                                    update_busy,
                                )
                                .when(!update_busy, |button| {
                                    button.on_click(cx.listener(|this, _, _, cx| {
                                        this.close_about_dialog(cx);
                                        this.check_for_updates_from_menu(cx);
                                    }))
                                }),
                            )
                            .child(
                                design_system::button(
                                    "close-about-button",
                                    "Close",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.close_about_dialog(cx);
                                    },
                                )),
                            ),
                    ),
            )
    }
}
