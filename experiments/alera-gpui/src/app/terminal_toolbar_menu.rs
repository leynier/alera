use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Pixels, Point, Role,
    SharedString, StatefulInteractiveElement as _, Styled as _,
};

use super::terminal_toolbar::{TerminalToolbarCorner, TerminalToolbarMenu};
use super::AleraApp;
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_terminal_toolbar_menu(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let menu = self
            .terminal_toolbar_menu
            .as_ref()
            .filter(|menu| menu.session_id == session_id)?;
        let selected = TerminalToolbarCorner::from_key(
            &self.settings_state.terminal_toolbar_corner,
        );
        let position = menu.position;
        let mut panel = div()
            .id("terminal-toolbar-corner-menu")
            .role(Role::Menu)
            .aria_label("Toolbar Corner")
            .absolute()
            .left(position.x)
            .top(position.y)
            .w(px(170.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_1();
        for corner in [
            TerminalToolbarCorner::TopLeft,
            TerminalToolbarCorner::TopRight,
            TerminalToolbarCorner::BottomLeft,
            TerminalToolbarCorner::BottomRight,
        ] {
            panel = panel.child(self.terminal_toolbar_corner_menu_row(corner, selected, cx));
        }
        let overlay_session_id = session_id.to_owned();
        Some(
            div()
                .id("terminal-toolbar-menu-overlay")
                .absolute()
                .inset_0()
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        if this
                            .terminal_toolbar_menu
                            .as_ref()
                            .is_some_and(|menu| menu.session_id == overlay_session_id)
                        {
                            this.terminal_toolbar_menu = None;
                            cx.notify();
                        }
                    }),
                )
                .child(panel)
                .into_any_element(),
        )
    }

    fn terminal_toolbar_corner_menu_row(
        &self,
        corner: TerminalToolbarCorner,
        selected: TerminalToolbarCorner,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .id(SharedString::from(format!("terminal-toolbar-corner-{}", corner.key())))
            .focusable()
            .tab_stop(true)
            .role(Role::MenuItem)
            .aria_label(corner.label())
            .aria_selected(corner == selected)
            .flex()
            .items_center()
            .h(px(30.0))
            .px_2()
            .rounded_md()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface()))
            .on_click(cx.listener(move |this, _, window, cx| {
                this.terminal_toolbar_menu = None;
                this.set_terminal_toolbar_corner(corner, window, cx);
                cx.stop_propagation();
            }))
            .child(div().w(px(18.0)).when(corner == selected, |slot| {
                slot.child(icon(AleraIcon::Check, 14.0, theme::text()))
            }))
            .child(corner.label())
            .into_any_element()
    }

    pub(super) fn open_terminal_toolbar_menu(
        &mut self,
        session_id: String,
        global_position: Point<Pixels>,
        cx: &mut Context<Self>,
    ) {
        let Some(bounds) = self.terminal_toolbar_viewport_bounds.get(&session_id) else {
            return;
        };
        let local = gpui::point(
            px((global_position.x - bounds.origin.x).as_f32().clamp(
                8.0,
                (bounds.size.width.as_f32() - 178.0).max(8.0),
            )),
            px((global_position.y - bounds.origin.y).as_f32().clamp(
                8.0,
                (bounds.size.height.as_f32() - 132.0).max(8.0),
            )),
        );
        self.terminal_toolbar_menu = Some(TerminalToolbarMenu {
            session_id,
            position: local,
        });
        cx.notify();
    }
}
