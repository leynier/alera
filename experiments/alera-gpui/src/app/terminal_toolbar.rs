use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, ClickEvent, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, MouseDownEvent, ParentElement as _, Pixels, Point,
    SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};

use super::AleraApp;
use crate::activity::ContextPanel;
use crate::design_system;
use crate::icons::AleraIcon;
use crate::theme;

const TOOLBAR_INSET: f32 = 4.0;
const TOOLBAR_BUTTON_SIZE: f32 = 30.0;
const TOOLBAR_GAP: f32 = 2.0;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum TerminalToolbarCorner {
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
}

impl TerminalToolbarCorner {
    pub(super) fn from_key(value: &str) -> Self {
        match value {
            "topLeft" => Self::TopLeft,
            "bottomLeft" => Self::BottomLeft,
            "bottomRight" => Self::BottomRight,
            _ => Self::TopRight,
        }
    }

    pub(super) fn key(self) -> &'static str {
        match self {
            Self::TopLeft => "topLeft",
            Self::TopRight => "topRight",
            Self::BottomLeft => "bottomLeft",
            Self::BottomRight => "bottomRight",
        }
    }

    pub(super) fn label(self) -> &'static str {
        match self {
            Self::TopLeft => "Top Left",
            Self::TopRight => "Top Right",
            Self::BottomLeft => "Bottom Left",
            Self::BottomRight => "Bottom Right",
        }
    }

    fn is_left(self) -> bool {
        matches!(self, Self::TopLeft | Self::BottomLeft)
    }

    fn is_top(self) -> bool {
        matches!(self, Self::TopLeft | Self::TopRight)
    }
}

#[derive(Clone, Debug)]
pub(super) struct TerminalToolbarDrag {
    session_id: String,
    left: f32,
    top: f32,
    width: f32,
    height: f32,
    grab_x: f32,
    grab_y: f32,
}

#[derive(Clone, Debug)]
pub(super) struct TerminalToolbarMenu {
    pub(super) session_id: String,
    pub(super) position: Point<Pixels>,
}

impl TerminalToolbarDrag {
    pub(super) fn session_id(&self) -> &str {
        &self.session_id
    }
}

impl TerminalToolbarMenu {
    pub(super) fn session_id(&self) -> &str {
        &self.session_id
    }
}

impl AleraApp {
    pub(super) fn render_terminal_toolbar(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let pulse = self.terminal_pulse_supported();
        let has_canvas = !self.agent_canvas_values.is_empty();
        let corner = TerminalToolbarCorner::from_key(&self.settings_state.terminal_toolbar_corner);
        let button_count = 3 + usize::from(pulse) + usize::from(has_canvas);
        let width = toolbar_extent(button_count);
        let mut actions = Vec::new();
        if pulse {
            let pulse_session_id = session_id.to_owned();
            actions.push(
                design_system::icon_button(
                    SharedString::from(format!("terminal-pulse-{session_id}")),
                    "Configure Terminal Pulse",
                    AleraIcon::Activity,
                    true,
                    TOOLBAR_BUTTON_SIZE,
                    Some(theme::surface_raised()),
                    Some(theme::border_subtle()),
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    this.open_terminal_pulse_dialog(pulse_session_id.clone(), window, cx);
                    cx.stop_propagation();
                }))
                .into_any_element(),
            );
        }
        let composer_visible = self.terminal_composer_visible.contains(session_id);
        let composer_session_id = session_id.to_owned();
        actions.push(
            design_system::icon_button(
                SharedString::from(format!("terminal-composer-toggle-{session_id}")),
                if composer_visible {
                    "Hide Terminal Composer"
                } else {
                    "Show Terminal Composer"
                },
                AleraIcon::Composer,
                true,
                TOOLBAR_BUTTON_SIZE,
                Some(if composer_visible {
                    theme::accent_subtle()
                } else {
                    theme::surface_raised()
                }),
                Some(theme::border_subtle()),
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                this.toggle_terminal_composer(composer_session_id.clone(), window, cx);
                cx.stop_propagation();
            }))
            .into_any_element(),
        );
        let refresh_session_id = session_id.to_owned();
        actions.push(
            design_system::icon_button(
                SharedString::from(format!("terminal-refresh-{session_id}")),
                "Refresh Terminal",
                AleraIcon::Refresh,
                true,
                TOOLBAR_BUTTON_SIZE,
                Some(theme::surface_raised()),
                Some(theme::border_subtle()),
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                this.refresh_terminal_viewport(refresh_session_id.clone(), cx);
                cx.stop_propagation();
            }))
            .into_any_element(),
        );
        if has_canvas {
            let canvas_session_id = session_id.to_owned();
            actions.push(
                design_system::icon_button(
                    SharedString::from(format!("terminal-agent-canvas-{session_id}")),
                    "Agent Canvas",
                    AleraIcon::Agent,
                    true,
                    TOOLBAR_BUTTON_SIZE,
                    Some(theme::surface_raised()),
                    Some(theme::border_subtle()),
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.show_terminal_agent_canvas(&canvas_session_id, cx);
                    cx.stop_propagation();
                }))
                .into_any_element(),
            );
        }
        let menu_session_id = session_id.to_owned();
        let mut cluster = div()
            .id(SharedString::from(format!("terminal-toolbar-{session_id}")))
            .flex()
            .items_center()
            .gap(px(TOOLBAR_GAP))
            .w(px(width))
            .h(px(TOOLBAR_BUTTON_SIZE))
            .on_aux_click(cx.listener(move |this, event: &ClickEvent, _, cx| {
                this.open_terminal_toolbar_menu(menu_session_id.clone(), event.position(), cx);
                cx.stop_propagation();
            }));
        if !corner.is_left() {
            cluster = cluster.child(self.render_terminal_toolbar_handle(session_id, cx));
        }
        cluster = cluster.children(actions);
        if corner.is_left() {
            cluster = cluster.child(self.render_terminal_toolbar_handle(session_id, cx));
        }

        if let Some(drag) = self
            .terminal_toolbar_drag
            .as_ref()
            .filter(|drag| drag.session_id == session_id)
        {
            return cluster
                .absolute()
                .left(px(drag.left))
                .top(px(drag.top))
                .into_any_element();
        }
        cluster
            .absolute()
            .when(corner.is_top(), |toolbar| toolbar.top(px(TOOLBAR_INSET)))
            .when(!corner.is_top(), |toolbar| {
                toolbar.bottom(px(TOOLBAR_INSET))
            })
            .when(corner.is_left(), |toolbar| toolbar.left(px(TOOLBAR_INSET)))
            .when(!corner.is_left(), |toolbar| {
                toolbar.right(px(TOOLBAR_INSET))
            })
            .into_any_element()
    }

    fn render_terminal_toolbar_handle(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let session_id = session_id.to_owned();
        design_system::icon_button(
            SharedString::from(format!("terminal-toolbar-handle-{session_id}")),
            "Move Toolbar",
            AleraIcon::DragHandle,
            true,
            TOOLBAR_BUTTON_SIZE,
            Some(theme::surface_raised()),
            Some(theme::border_subtle()),
        )
        .cursor(CursorStyle::OpenHand)
        .on_mouse_down(
            gpui::MouseButton::Left,
            cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                this.start_terminal_toolbar_drag(&session_id, event.position, cx);
                cx.stop_propagation();
            }),
        )
        .into_any_element()
    }

    fn start_terminal_toolbar_drag(
        &mut self,
        session_id: &str,
        position: Point<Pixels>,
        cx: &mut Context<Self>,
    ) {
        let Some(bounds) = self
            .terminal_toolbar_viewport_bounds
            .get(session_id)
            .copied()
        else {
            return;
        };
        let pulse = self.terminal_pulse_supported();
        let has_canvas = !self.agent_canvas_values.is_empty();
        let width = toolbar_extent(3 + usize::from(pulse) + usize::from(has_canvas));
        let height = TOOLBAR_BUTTON_SIZE;
        let corner = TerminalToolbarCorner::from_key(&self.settings_state.terminal_toolbar_corner);
        let left = if corner.is_left() {
            TOOLBAR_INSET
        } else {
            (bounds.size.width.as_f32() - width - TOOLBAR_INSET).max(TOOLBAR_INSET)
        };
        let top = if corner.is_top() {
            TOOLBAR_INSET
        } else {
            (bounds.size.height.as_f32() - height - TOOLBAR_INSET).max(TOOLBAR_INSET)
        };
        self.terminal_toolbar_drag = Some(TerminalToolbarDrag {
            session_id: session_id.to_owned(),
            left,
            top,
            width,
            height,
            grab_x: (position.x - bounds.origin.x).as_f32() - left,
            grab_y: (position.y - bounds.origin.y).as_f32() - top,
        });
        self.terminal_toolbar_menu = None;
        cx.notify();
    }

    pub(super) fn update_terminal_toolbar_drag(
        &mut self,
        position: Point<Pixels>,
        cx: &mut Context<Self>,
    ) {
        let Some(drag) = self.terminal_toolbar_drag.as_mut() else {
            return;
        };
        let Some(bounds) = self
            .terminal_toolbar_viewport_bounds
            .get(&drag.session_id)
            .copied()
        else {
            return;
        };
        drag.left = clamp_toolbar_axis(
            (position.x - bounds.origin.x).as_f32() - drag.grab_x,
            bounds.size.width.as_f32(),
            drag.width,
        );
        drag.top = clamp_toolbar_axis(
            (position.y - bounds.origin.y).as_f32() - drag.grab_y,
            bounds.size.height.as_f32(),
            drag.height,
        );
        cx.notify();
    }

    pub(super) fn finish_terminal_toolbar_drag(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(drag) = self.terminal_toolbar_drag.take() else {
            return;
        };
        let Some(bounds) = self.terminal_toolbar_viewport_bounds.get(&drag.session_id) else {
            cx.notify();
            return;
        };
        let left = drag.left + drag.width / 2.0 <= bounds.size.width.as_f32() / 2.0;
        let top = drag.top + drag.height / 2.0 <= bounds.size.height.as_f32() / 2.0;
        let corner = match (top, left) {
            (true, true) => TerminalToolbarCorner::TopLeft,
            (true, false) => TerminalToolbarCorner::TopRight,
            (false, true) => TerminalToolbarCorner::BottomLeft,
            (false, false) => TerminalToolbarCorner::BottomRight,
        };
        self.set_terminal_toolbar_corner(corner, window, cx);
    }

    pub(super) fn set_terminal_toolbar_corner(
        &mut self,
        corner: TerminalToolbarCorner,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.settings_state.terminal_toolbar_corner = corner.key().to_owned();
        self.persist_settings();
        self.persist_shared_flutter_settings(
            self.settings_state.shared_flutter_local_payload(),
            cx,
        );
        if let Some(select) = self.settings_selects.get("terminal-toolbar-corner") {
            select.update(cx, |select, cx| {
                select.set_selected_value(&SharedString::from(corner.label()), window, cx);
            });
        }
        cx.notify();
    }

    fn show_terminal_agent_canvas(&mut self, session_id: &str, cx: &mut Context<Self>) {
        if self
            .agent_canvas_values
            .iter()
            .any(|canvas| canvas.get("id").and_then(serde_json::Value::as_str) == Some(session_id))
        {
            self.agent_canvas_selected_id = Some(session_id.to_owned());
        }
        self.context_sidebar_collapsed = false;
        self.select_context_panel(ContextPanel::AgentCanvas, cx);
    }
}

fn toolbar_extent(button_count: usize) -> f32 {
    button_count as f32 * TOOLBAR_BUTTON_SIZE + button_count.saturating_sub(1) as f32 * TOOLBAR_GAP
}

fn clamp_toolbar_axis(value: f32, viewport: f32, toolbar: f32) -> f32 {
    let max = viewport - toolbar - TOOLBAR_INSET;
    if max <= TOOLBAR_INSET {
        TOOLBAR_INSET
    } else {
        value.clamp(TOOLBAR_INSET, max)
    }
}

#[cfg(test)]
mod tests {
    use super::{clamp_toolbar_axis, toolbar_extent};

    #[test]
    fn toolbar_geometry_matches_flutter_tokens() {
        assert_eq!(toolbar_extent(3), 94.0);
        assert_eq!(clamp_toolbar_axis(-10.0, 320.0, 94.0), 4.0);
        assert_eq!(clamp_toolbar_axis(500.0, 320.0, 94.0), 222.0);
        assert_eq!(clamp_toolbar_axis(30.0, 40.0, 94.0), 4.0);
    }
}
