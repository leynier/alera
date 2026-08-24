use freya::{icons, prelude::*};

use crate::alera_scroll_view::AleraScrollView as ScrollView;
use crate::{ACCENT, BORDER, MUTED, SURFACE, TEXT, settings_terminal::terminal_row_shell};

pub(super) fn autocomplete_row(
    mut value: State<String>,
    mut open_menu: State<Option<String>>,
    mut just_opened: State<bool>,
    mut highlighted: State<usize>,
    font_families: State<Vec<String>>,
    mut committed: State<String>,
) -> Element {
    const KEY: &str = "terminal-font-family";
    let query = value.read().trim().to_lowercase();
    let families = font_families.read().clone();
    let filtered = families
        .iter()
        .filter(|font| query.is_empty() || font.to_lowercase().starts_with(&query))
        .chain(families.iter().filter(|font| {
            let font = font.to_lowercase();
            !query.is_empty() && !font.starts_with(&query) && font.contains(&query)
        }))
        .cloned()
        .collect::<Vec<_>>();
    let is_open = open_menu.read().as_deref() == Some(KEY);
    let mut value_for_clear = value;
    let mut open_for_clear = open_menu;
    let mut open_for_arrow = open_menu;
    let mut opened_for_arrow = just_opened;
    let mut open_for_validate = open_menu;
    let mut opened_for_validate = just_opened;
    let mut value_for_submit = value;
    let mut committed_for_submit = committed;
    let mut open_for_submit = open_menu;
    let filtered_for_keys = filtered.clone();
    let mut value_for_keys = value;
    let mut committed_for_keys = committed;
    let mut open_for_keys = open_menu;
    let trailing = rect()
        .horizontal()
        .cross_align(Alignment::Center)
        .maybe_child((!value.read().is_empty()).then(|| {
            rect()
                .width(Size::px(28.))
                .height(Size::px(28.))
                .center()
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Clear")
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    value_for_clear.set(String::new());
                    open_for_clear.set(Some(KEY.to_string()));
                    highlighted.set(0);
                })
                .child(
                    SvgViewer::new(icons::lucide::circle_x())
                        .width(Size::px(16.))
                        .height(Size::px(16.))
                        .color(MUTED),
                )
        }))
        .child(
            rect()
                .width(Size::px(28.))
                .height(Size::px(28.))
                .center()
                .corner_radius(4.)
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt("Fonts")
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    if open_for_arrow.read().as_deref() == Some(KEY) {
                        open_for_arrow.set(None);
                        opened_for_arrow.set(false);
                    } else {
                        open_for_arrow.set(Some(KEY.to_string()));
                        opened_for_arrow.set(true);
                        highlighted.set(0);
                    }
                })
                .child(
                    SvgViewer::new(if is_open {
                        icons::lucide::chevron_up()
                    } else {
                        icons::lucide::chevron_down()
                    })
                    .width(Size::px(16.))
                    .height(Size::px(16.))
                    .color(MUTED),
                ),
        );
    let input = Input::new(value)
        .key("terminal-font-family-field")
        .width(Size::fill())
        .placeholder("SF Mono")
        .compact()
        .filled()
        .theme_colors(
            InputColorsThemePartial::new()
                .background(SURFACE)
                .focus_background(SURFACE)
                .border_fill(BORDER)
                .focus_border_fill(ACCENT)
                .color(TEXT)
                .placeholder_color(MUTED),
        )
        .trailing(trailing)
        .on_validate(move |_| {
            open_for_validate.set(Some(KEY.to_string()));
            opened_for_validate.set(false);
        })
        .on_submit(move |text: String| {
            let trimmed = text.trim();
            let next = if trimmed.is_empty() {
                committed_for_submit.read().clone()
            } else {
                trimmed.to_string()
            };
            value_for_submit.set(next.clone());
            committed_for_submit.set(next);
            open_for_submit.set(None);
        })
        .on_pre_key_down(move |event: Event<KeyboardEventData>| match &event.key {
            Key::Named(NamedKey::ArrowDown) => {
                event.stop_propagation();
                if !filtered_for_keys.is_empty() {
                    let next = if open_for_keys.read().as_deref() == Some(KEY) {
                        (highlighted() + 1).min(filtered_for_keys.len() - 1)
                    } else {
                        0
                    };
                    highlighted.set(next);
                }
                open_for_keys.set(Some(KEY.to_string()));
                false
            }
            Key::Named(NamedKey::ArrowUp) => {
                event.stop_propagation();
                if !filtered_for_keys.is_empty() {
                    let next_highlighted = highlighted().saturating_sub(1);
                    highlighted.set(next_highlighted);
                }
                open_for_keys.set(Some(KEY.to_string()));
                false
            }
            Key::Named(NamedKey::Enter) if open_for_keys.read().as_deref() == Some(KEY) => {
                event.stop_propagation();
                if let Some(font) = filtered_for_keys.get(highlighted()) {
                    value_for_keys.set(font.clone());
                    committed_for_keys.set(font.clone());
                }
                open_for_keys.set(None);
                false
            }
            Key::Named(NamedKey::Escape) if open_for_keys.read().as_deref() == Some(KEY) => {
                event.stop_propagation();
                value_for_keys.set(committed_for_keys.read().clone());
                open_for_keys.set(None);
                false
            }
            _ => true,
        });
    let menu = is_open.then(|| {
        let menu_height = ((filtered.len().max(1) as f32 * 34.) + 8.).min(220.);
        let mut menu_items = rect()
            .width(Size::fill())
            .vertical()
            .padding(Gaps::new_all(4.))
            .background(SURFACE);
        if filtered.is_empty() {
            menu_items = menu_items.child(
                rect()
                    .height(Size::px(36.))
                    .padding(Gaps::new_all(8.))
                    .child(
                        label()
                            .font_size(12.)
                            .color(MUTED)
                            .text("No Matching Fonts"),
                    ),
            );
        }
        for (index, font) in filtered.into_iter().enumerate() {
            let mut value = value;
            let mut committed = committed;
            let mut close = open_menu;
            let mut hovered = highlighted;
            let font_for_click = font.clone();
            menu_items = menu_items.child(
                rect()
                    .height(Size::px(34.))
                    .padding(Gaps::new(8., 5., 8., 5.))
                    .corner_radius(5.)
                    .background(if highlighted() == index {
                        (42, 42, 42)
                    } else {
                        SURFACE
                    })
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(font.clone())
                    .on_pointer_enter(move |_| {
                        hovered.set(index);
                        Cursor::set(CursorIcon::Pointer);
                    })
                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        value.set(font_for_click.clone());
                        committed.set(font_for_click.clone());
                        close.set(None);
                    })
                    .child(label().font_size(12.).color(TEXT).text(font)),
            );
        }
        rect()
            .width(Size::fill())
            .height(Size::px(menu_height))
            .background(SURFACE)
            .border(Border::new().width(1.).fill(BORDER))
            .corner_radius(7.)
            .on_press(|event: Event<PressEventData>| event.stop_propagation())
            .on_global_pointer_press(move |_| {
                if just_opened() {
                    just_opened.set(false);
                } else {
                    let trimmed = value.read().trim().to_string();
                    if trimmed.is_empty() {
                        value.set(committed.read().clone());
                    } else {
                        value.set(trimmed.clone());
                        committed.set(trimmed);
                    }
                    open_menu.set(None);
                }
            })
            .child(
                ScrollView::new()
                    .width(Size::fill())
                    .height(Size::fill())
                    .show_scrollbar(true)
                    .child(menu_items),
            )
    });

    terminal_row_shell("Font Family", "Typeface used in new terminal sessions.")
        .child(
            rect()
                .width(Size::px(220.))
                .vertical()
                .spacing(6.)
                .child(input)
                .maybe_child(menu),
        )
        .into_element()
}
