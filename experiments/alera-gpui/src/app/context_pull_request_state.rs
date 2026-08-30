use gpui::{AnyElement, AppContext as _, Context, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _, div, px, prelude::FluentBuilder as _};
use gpui_component::tooltip::Tooltip;

use super::AleraApp;
use crate::{design_system::{self, ButtonKind}, forge_service::{ForgeAuthStatus, ForgeUnavailableReason}, icons::{AleraIcon, loading_indicator}, theme};

impl AleraApp {
    pub(super) fn render_pull_request_unavailable(&self, cx: &mut Context<Self>) -> Option<AnyElement> {
        if self.selected_source_control_scope().is_none() {
            return Some(design_system::empty_state("pull-request-no-git", AleraIcon::GitPullRequest,
                "Pull Request Unavailable", "This workspace is not connected to a Git repository, so there are no Pull Requests to show.").into_any_element());
        }
        if self.forge_busy && self.forge_snapshot.auth_status == ForgeAuthStatus::Unknown && self.forge_snapshot.unavailable_reason.is_none() {
            return Some(div().flex().flex_1().items_center().justify_center().child(loading_indicator(20.0, theme::text_muted())).into_any_element());
        }
        let (symbol, title, message, retry) = if let Some(reason) = self.forge_snapshot.unavailable_reason {
            let (title, message) = match reason {
                ForgeUnavailableReason::NoRemote => ("No remote", "This repository has no remote to detect a provider from."),
                ForgeUnavailableReason::ProviderNotDetected => ("Provider not detected", "Could not detect the git hosting provider. Set it in project settings."),
                ForgeUnavailableReason::UnsupportedProvider => ("Unsupported provider", "This hosting provider is not supported yet."),
            };
            (AleraIcon::GitPullRequest, title, message.to_owned(), false)
        } else {
            match self.forge_snapshot.auth_status {
                ForgeAuthStatus::CliMissing => (AleraIcon::Error, "CLI not found", "Install `gh` and ensure it is on your PATH.".to_owned(), false),
                ForgeAuthStatus::NotAuthenticated => {
                    let host = self.forge_snapshot.host.trim();
                    let command = if host.is_empty() || host == "github.com" { "gh auth login".to_owned() } else { format!("gh auth login --hostname {host}") };
                    (AleraIcon::Error, "Not authenticated", format!("Run `{command}` to sign in, then refresh."), true)
                }
                _ => return None,
            }
        };
        let action = retry.then(|| design_system::button("pull-request-auth-retry", "Refresh", ButtonKind::Outlined, self.forge_busy)
            .on_click(cx.listener(|this, _, _, cx| { if !this.forge_busy { this.refresh_forge(cx); } })).into_any_element());
        let body = design_system::empty_state_with_action("pull-request-unavailable", symbol, Some(title.into()), message.into(), action).into_any_element();
        let refresh = if self.forge_busy {
            loading_indicator(16.0, theme::text_muted()).into_any_element()
        } else {
            design_system::icon_button("pull-request-unavailable-refresh", "Refresh", AleraIcon::Refresh, true, 22.0, None, None)
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh")).into())
                .on_click(cx.listener(|this, _, _, cx| this.refresh_forge(cx))).into_any_element()
        };
        Some(pull_request_frame(body, refresh, self.forge_error.clone()).into_any_element())
    }
}

fn pull_request_frame(body: AnyElement, refresh: AnyElement, error: Option<SharedString>) -> gpui::Div {
    div().flex().flex_col().size_full().min_h_0()
        .child(div().debug_selector(|| "pull-request-state-header".into()).flex().items_center().h(px(44.0)).flex_shrink_0().px(px(12.0))
            .border_b_1().border_color(theme::border_subtle())
            .child(div().flex_1().text_size(px(13.0)).font_weight(FontWeight::MEDIUM).child("Pull Request"))
            .child(refresh))
        .when_some(error, |panel, error| panel.child(div().p(px(12.0)).flex_shrink_0()
            .bg(gpui::Rgba { a: 0.12, ..theme::danger() }).text_size(px(12.0)).text_color(theme::danger()).child(error)))
        .child(div().debug_selector(|| "pull-request-state-body".into()).flex().flex_1().min_h_0().child(body))
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Render, TestAppContext, Window};

    struct FrameProbe;
    impl Render for FrameProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            div().w(px(280.0)).h(px(500.0)).child(pull_request_frame(div().into_any_element(), div().into_any_element(), None))
        }
    }

    #[gpui::test]
    fn pull_request_unavailable_keeps_header_and_fills_remaining_height(cx: &mut TestAppContext) {
        let (_, cx) = cx.add_window_view(|_, _| FrameProbe);
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let header = cx.debug_bounds("pull-request-state-header").unwrap();
        let body = cx.debug_bounds("pull-request-state-body").unwrap();
        assert_eq!(header.size.height, px(44.0));
        assert_eq!(body.top(), header.bottom());
        assert_eq!(body.bottom(), px(500.0));
    }
}
