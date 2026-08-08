use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, App, CursorStyle, ElementId, Entity,
    Focusable as _, InteractiveElement as _, IntoElement, MouseButton, MouseDownEvent,
    ParentElement as _, RenderOnce, SharedString, Styled as _, Window,
};
use gpui_component::{
    input::{Input, InputState},
    Theme, ThemeMode,
};

use crate::{icons::loading_indicator, theme};

mod controls;
pub use controls::{
    checkbox, dropdown_trigger, dropdown_trigger_with_loading, icon_button, menu_item, radio,
    switch,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ButtonKind {
    Filled,
    Text,
    Outlined,
    Destructive,
}

pub fn configure_component_theme(cx: &mut gpui::App) {
    let component_theme = Theme::global_mut(cx);
    component_theme.mode = ThemeMode::Dark;
    component_theme.font_family = "Inter".into();
    component_theme.font_size = px(13.0);
    component_theme.mono_font_family = "JetBrains Mono".into();
    component_theme.mono_font_size = px(12.0);
    component_theme.radius = px(6.0);
    component_theme.radius_lg = px(10.0);

    let colors = &mut component_theme.colors;
    colors.background = theme::surface_selected().into();
    colors.foreground = theme::text().into();
    colors.border = theme::border().into();
    colors.input = theme::border().into();
    colors.ring = theme::accent().into();
    colors.caret = theme::text().into();
    colors.muted = theme::surface_raised().into();
    colors.muted_foreground = theme::text_faint().into();
    colors.popover = theme::surface().into();
    colors.popover_foreground = theme::text().into();
    colors.primary = theme::accent().into();
    colors.primary_foreground = theme::on_accent().into();
    colors.secondary = theme::surface_selected().into();
    colors.secondary_foreground = theme::text().into();
    colors.accent = theme::surface_selected().into();
    colors.accent_foreground = theme::text().into();
    colors.danger = theme::danger().into();
    colors.danger_foreground = theme::on_danger().into();
    colors.selection = theme::text_selection().into();
    colors.sidebar = theme::surface_selected().into();
    colors.sidebar_border = theme::border_subtle().into();
}

#[derive(IntoElement)]
pub struct AleraTextField {
    state: Entity<InputState>,
    dense: bool,
    search: bool,
    prefix: Option<AnyElement>,
    suffix: Option<AnyElement>,
    label: Option<SharedString>,
    disabled: bool,
    error: Option<SharedString>,
    height: gpui::Pixels,
}

impl AleraTextField {
    pub fn new(state: &Entity<InputState>) -> Self {
        Self {
            state: state.clone(),
            dense: false,
            search: false,
            prefix: None,
            suffix: None,
            label: None,
            disabled: false,
            error: None,
            height: px(48.0),
        }
    }

    pub fn dense(mut self) -> Self {
        self.dense = true;
        self.height = px(40.0);
        self
    }

    pub fn search(mut self) -> Self {
        self.search = true;
        self
    }

    pub fn prefix(mut self, prefix: impl IntoElement) -> Self {
        self.prefix = Some(prefix.into_any_element());
        self
    }

    pub fn suffix(mut self, suffix: impl IntoElement) -> Self {
        self.suffix = Some(suffix.into_any_element());
        self
    }

    pub fn label(mut self, label: impl Into<SharedString>) -> Self {
        self.label = Some(label.into());
        self
    }

    pub fn disabled(mut self, disabled: bool) -> Self {
        self.disabled = disabled;
        self
    }

    pub fn error(mut self, error: Option<impl Into<SharedString>>) -> Self {
        self.error = error.map(Into::into);
        self
    }

    pub fn height(mut self, height: gpui::Pixels) -> Self {
        self.height = height;
        self
    }
}

impl RenderOnce for AleraTextField {
    fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement {
        let focused = self.state.focus_handle(cx).is_focused(window);
        let has_text = !self.state.read(cx).value().is_empty();
        let border = if self.error.is_some() {
            theme::danger()
        } else if focused {
            if self.dense {
                theme::border()
            } else {
                theme::accent()
            }
        } else if self.dense {
            theme::border_subtle()
        } else {
            theme::border()
        };
        let background = if self.disabled {
            theme::surface_raised()
        } else if self.dense {
            theme::surface()
        } else {
            theme::surface_selected()
        };
        let suffix = if self.search && has_text {
            let state = self.state.clone();
            Some(
                div()
                    .id(("clear-search", self.state.entity_id()))
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(24.0))
                    .h(self.height)
                    .cursor(CursorStyle::PointingHand)
                    .on_mouse_down(MouseButton::Left, move |_: &MouseDownEvent, window, cx| {
                        state.update(cx, |state, cx| {
                            state.set_value("", window, cx);
                            state.focus(window, cx);
                        });
                        cx.stop_propagation();
                    })
                    .child(crate::icons::icon(
                        crate::icons::AleraIcon::Close,
                        12.0,
                        theme::text_faint(),
                    ))
                    .into_any_element(),
            )
        } else {
            self.suffix
        };
        let mut input = Input::new(&self.state)
            .appearance(false)
            .disabled(self.disabled)
            .size_full()
            .px(if self.dense { px(8.0) } else { px(12.0) })
            .py(if self.dense { px(12.0) } else { px(10.0) })
            .text_size(px(if self.dense { 12.0 } else { 13.0 }));
        if let Some(prefix) = self.prefix {
            input = input.prefix(prefix);
        }
        if let Some(suffix) = suffix {
            input = input.suffix(suffix);
        }

        div()
            .child(
                div()
                    .relative()
                    .h(self.height)
                    .rounded(if self.dense { px(10.0) } else { px(6.0) })
                    .border_1()
                    .border_color(border)
                    .bg(background)
                    .child(input)
                    .when_some(self.label, |field, label| {
                        field.child(
                            div()
                                .absolute()
                                .top(px(-7.0))
                                .left(px(8.0))
                                .px(px(4.0))
                                .bg(background)
                                .text_size(px(11.0))
                                .text_color(theme::text_muted())
                                .child(label),
                        )
                    }),
            )
            .when_some(self.error, |field, error| {
                field.child(
                    div()
                        .mt_1()
                        .text_size(px(12.0))
                        .text_color(theme::danger())
                        .child(error),
                )
            })
    }
}

pub fn text_field(state: &Entity<InputState>) -> AleraTextField {
    AleraTextField::new(state)
}

pub fn dense_text_field(state: &Entity<InputState>, prefix: Option<AnyElement>) -> AleraTextField {
    let field = AleraTextField::new(state).dense();
    if let Some(prefix) = prefix {
        field.prefix(prefix)
    } else {
        field
    }
}

pub fn search_field(state: &Entity<InputState>, dense: bool) -> AleraTextField {
    let field = AleraTextField::new(state)
        .search()
        .prefix(crate::icons::icon(
            crate::icons::AleraIcon::Search,
            if dense { 14.0 } else { 16.0 },
            theme::text_faint(),
        ));
    if dense {
        field.dense()
    } else {
        field
    }
}

pub fn button(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: ButtonKind,
    disabled: bool,
) -> gpui::Stateful<gpui::Div> {
    button_with_loading(id, label, kind, disabled, false)
}

pub fn button_with_loading(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: ButtonKind,
    disabled: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    let filled = matches!(kind, ButtonKind::Filled | ButtonKind::Destructive);
    let destructive = kind == ButtonKind::Destructive;
    let outlined = kind == ButtonKind::Outlined;
    let background = if destructive {
        theme::danger()
    } else if filled {
        theme::accent()
    } else {
        theme::transparent()
    };
    let foreground = if destructive {
        theme::on_danger()
    } else if filled {
        theme::on_accent()
    } else {
        theme::text()
    };

    div()
        .id(id)
        .flex()
        .items_center()
        .justify_center()
        .min_w(px(0.0))
        .h(px(34.0))
        .px(px(match kind {
            ButtonKind::Outlined => 24.0,
            ButtonKind::Text => 12.0,
            ButtonKind::Filled | ButtonKind::Destructive => 14.0,
        }))
        .rounded_lg()
        .text_size(px(13.0))
        .font_weight(gpui::FontWeight::MEDIUM)
        .bg(if disabled {
            theme::surface_raised()
        } else {
            background
        })
        .text_color(if disabled {
            theme::text_faint()
        } else {
            foreground
        })
        .when(outlined, |button| {
            button.border_1().border_color(theme::border())
        })
        .when(!disabled, |button| {
            button
                .cursor(CursorStyle::PointingHand)
                .hover(move |style| match kind {
                    ButtonKind::Filled => style.bg(theme::accent_hover()),
                    ButtonKind::Destructive => style.bg(theme::danger_hover()),
                    ButtonKind::Text | ButtonKind::Outlined => style.bg(theme::surface_selected()),
                })
        })
        .when(loading, |button| {
            button.child(loading_indicator(14.0, theme::text_faint()))
        })
        .child(label.into())
}

pub fn dialog_shell(width: f32) -> gpui::Div {
    div()
        .w(px(width))
        .rounded_xl()
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::surface())
        .shadow_lg()
        .p(px(20.0))
}
