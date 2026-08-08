use gpui::{
    deferred, div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, MouseButton, ParentElement as _, SharedString,
    Styled as _,
};

use super::sidebar_view_options_components::sidebar_sort_label;
use super::{AleraApp, SidebarSortBy, SidebarSortTarget};
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_sort_options(
        &self,
        target: SidebarSortTarget,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let selected = match target {
            SidebarSortTarget::Project => self.sidebar_project_sort,
            SidebarSortTarget::Workspace => self.sidebar_workspace_sort,
        };
        deferred(
            div()
                .id(match target {
                    SidebarSortTarget::Project => "sidebar-project-sort-menu",
                    SidebarSortTarget::Workspace => "sidebar-workspace-sort-menu",
                })
                .absolute()
                .top(px(34.0))
                .right_0()
                .w(px(160.0))
                .occlude()
                .rounded_md()
                .border_1()
                .border_color(theme::border())
                .bg(theme::surface())
                .shadow_md()
                .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                    this.sidebar_sort_dropdown = None;
                    cx.notify();
                }))
                .children(
                    [
                        SidebarSortBy::Name,
                        SidebarSortBy::Recent,
                        SidebarSortBy::Activity,
                    ]
                    .into_iter()
                    .map(|sort| {
                        let label = sidebar_sort_label(sort);
                        div()
                            .id(SharedString::from(format!(
                                "sidebar-{}-sort-{}",
                                match target {
                                    SidebarSortTarget::Project => "project",
                                    SidebarSortTarget::Workspace => "workspace",
                                },
                                label
                            )))
                            .flex()
                            .items_center()
                            .h(px(32.0))
                            .px_3()
                            .text_sm()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .when(selected == sort, |row| {
                                row.bg(theme::accent_subtle()).child(icon(
                                    AleraIcon::Check,
                                    14.0,
                                    theme::text(),
                                ))
                            })
                            .when(selected != sort, |row| row.child(div().w(px(14.0))))
                            .child(div().ml_2().child(label))
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _, _, cx| match target {
                                    SidebarSortTarget::Project => {
                                        this.set_sidebar_project_sort(sort, cx);
                                    }
                                    SidebarSortTarget::Workspace => {
                                        this.set_sidebar_workspace_sort(sort, cx);
                                    }
                                }),
                            )
                    }),
                ),
        )
        .into_any_element()
    }
}
