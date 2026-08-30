use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, App, CursorStyle, ElementId, Entity,
    Focusable as _, InteractiveElement as _, IntoElement, MouseButton, MouseDownEvent,
    ParentElement as _, RenderOnce, Role, SharedString, StatefulInteractiveElement as _,
    Styled as _, Window,
};
use gpui_component::{
    input::{Input, InputState},
    Theme, ThemeMode,
};

use crate::{icons::loading_indicator, theme};

mod controls;
mod empty_state;
pub use empty_state::{empty_state, empty_state_with_action};
#[cfg(all(test, feature = "gpui-tests"))]
mod control_geometry_tests;
mod text_area;
mod selectable_text;
pub use selectable_text::AleraSelectableText;
pub use text_area::AleraTextArea;
#[cfg(all(test, feature = "gpui-tests"))]
mod theme_tests;
#[cfg(all(test, feature = "gpui-tests"))]
mod text_field_tests;
pub use controls::{
    checkbox, dropdown_trigger, dropdown_trigger_with_loading, icon_button, menu_item, radio,
    switch,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ButtonKind {
    Filled,
    Elevated,
    Text,
    Outlined,
    Destructive,
}

pub fn configure_component_theme(cx: &mut gpui::App) {
    Theme::change(ThemeMode::Dark, None, cx);
    let component_theme = Theme::global_mut(cx);
    component_theme.font_family = "Inter".into();
    // Root uses this for rem geometry; Alera text roles stay explicit below it.
    component_theme.font_size = px(16.0);
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
    colors.muted_foreground = theme::text_muted().into();
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
    colors.link = theme::info().into();
    colors.selection = theme::ui_text_selection().into();
    colors.sidebar = theme::surface_selected().into();
    colors.sidebar_border = theme::border_subtle().into();
    colors.table = theme::app_background().into();
    colors.table_head = theme::surface_selected().into();
    colors.table_head_foreground = theme::text().into();
    colors.table_even = theme::app_background().into();
    colors.table_row_border = theme::border().into();

    // The pinned component library paints resolved tokens, while older
    // consumers still read colors. Alera uses solid fills in both paths.
    component_theme.tokens = (&component_theme.colors).into();
    Theme::sync_base(cx);
}

#[derive(IntoElement)]
pub struct AleraTextField {
    state: Entity<InputState>,
    dense: bool,
    search: bool,
    prefix: Option<AnyElement>,
    suffix: Option<AnyElement>,
    label: Option<SharedString>,
    accessibility_label: Option<SharedString>,
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
            accessibility_label: None,
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

    pub fn aria_label(mut self, label: impl Into<SharedString>) -> Self {
        self.accessibility_label = Some(label.into());
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
        let focused = !self.disabled && self.state.focus_handle(cx).is_focused(window);
        let has_text = !self.state.read(cx).value().is_empty();
        let floating_label = label_floats(focused, has_text);
        let has_prefix = self.prefix.is_some();
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
        let has_suffix = suffix.is_some();
        let accessibility_label = self
            .accessibility_label
            .or_else(|| self.label.clone())
            .or_else(|| self.search.then(|| SharedString::from("Search")));
        let mut input = Input::new(&self.state)
            .appearance(false)
            .disabled(self.disabled)
            .size_full()
            .px(if self.dense { px(8.0) } else { px(12.0) })
            .py(if self.dense { px(12.0) } else { px(10.0) })
            .text_size(px(if self.dense { 12.0 } else { 14.0 }));
        if let Some(label) = accessibility_label {
            input = input.aria_label(label);
        }
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
                    .cursor(if self.disabled { CursorStyle::Arrow } else { CursorStyle::IBeam })
                    .child(input)
                    .when_some(self.label, |field, label| {
                        if floating_label {
                            field.child(
                            div()
                                .absolute()
                                .top(px(-6.0))
                                .left(px(8.0))
                                .px(px(4.0))
                                .text_size(px(8.25))
                                .line_height(px(12.0))
                                .text_color(if focused { theme::accent() } else { theme::text_muted() })
                                .child(div().absolute().left_0().right_0().top(px(6.0)).h(px(1.0)).bg(background))
                                .child(label),
                            )
                        } else {
                            field.child(div().absolute().top(px(1.0)).bottom(px(1.0))
                                .left(px(if has_prefix { 40.0 } else { 12.0 }))
                                .right(px(if has_suffix { 42.0 } else { 12.0 }))
                                .flex().items_center().bg(background)
                                .text_size(px(11.0)).text_color(theme::text_muted()).child(label))
                        }
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

fn label_floats(focused: bool, has_text: bool) -> bool {
    focused || has_text
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
    let label = label.into();
    button_with_loading(id, label, kind, disabled, false)
}

pub fn button_with_loading(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: ButtonKind,
    disabled: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    button_with_loading_and_leading_icon(id, label, kind, disabled, loading, None)
}

pub fn button_with_leading_icon(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: ButtonKind,
    disabled: bool,
    leading: AnyElement,
) -> gpui::Stateful<gpui::Div> {
    button_with_loading_and_leading_icon(id, label, kind, disabled, false, Some(leading))
}

pub fn button_with_loading_and_leading_icon(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: ButtonKind,
    disabled: bool,
    loading: bool,
    leading: Option<AnyElement>,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    let filled = matches!(kind, ButtonKind::Filled | ButtonKind::Destructive);
    let elevated = kind == ButtonKind::Elevated;
    let destructive = kind == ButtonKind::Destructive;
    let outlined = kind == ButtonKind::Outlined;
    let background = if destructive {
        theme::danger()
    } else if filled {
        theme::accent()
    } else if elevated {
        theme::surface()
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
    let mut button = div()
        .id(id)
        .focusable()
        .tab_stop(!disabled)
        .role(Role::Button)
        .aria_label(label.clone())
        .flex()
        .items_center()
        .justify_center()
        .min_w(px(0.0))
        .h(px(match kind {
            ButtonKind::Filled | ButtonKind::Outlined | ButtonKind::Destructive => 26.0,
            ButtonKind::Text | ButtonKind::Elevated => 32.0,
        }))
        .px(px(match kind {
            ButtonKind::Outlined => 24.0,
            ButtonKind::Text => 12.0,
            ButtonKind::Filled | ButtonKind::Elevated | ButtonKind::Destructive => 14.0,
        }))
        .rounded(px(10.0))
        .text_size(px(13.0))
        .font_weight(gpui::FontWeight::MEDIUM)
        .bg(if disabled {
            if filled || elevated { theme::disabled_control_background() } else { theme::transparent() }
        } else {
            background
        })
        .text_color(if disabled {
            theme::disabled_control_foreground()
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
                    ButtonKind::Elevated => style.bg(theme::surface_selected()),
                    ButtonKind::Destructive => style.bg(theme::danger_hover()),
                    ButtonKind::Text | ButtonKind::Outlined => style.bg(theme::surface_selected()),
                })
        });
    if loading {
        button = button.child(loading_indicator(14.0, theme::text_faint()));
    } else if let Some(leading) = leading {
        button = button.child(div().mr(px(8.0)).child(leading));
    }
    button.child(label)
}

pub fn dialog_shell(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    width: f32,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .role(Role::Dialog)
        .aria_label(label.into())
        .w(px(width))
        .rounded_xl()
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::surface())
        .shadow_lg()
        .p(px(20.0))
}
