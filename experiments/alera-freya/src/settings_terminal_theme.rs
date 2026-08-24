use alera_desktop_core::terminal_theme_catalog::{
    TERMINAL_THEME_NAMES, TerminalThemePalette, terminal_theme_palette,
};
use freya::{icons, prelude::*};

use crate::alera_scroll_view::AleraScrollView as ScrollView;
use crate::{ACCENT, BORDER, MUTED, SURFACE, SURFACE_RAISED, TEXT};

pub(super) fn picker(value: State<String>, search: State<String>) -> Element {
    let selected_name = value.read().clone();
    let query = search.read().trim().to_lowercase();
    let filtered = TERMINAL_THEME_NAMES
        .iter()
        .copied()
        .filter(|name| query.is_empty() || name.to_lowercase().contains(&query))
        .collect::<Vec<_>>();
    let palette = terminal_theme_palette(&selected_name);
    let count = filtered.len();
    let mut options = rect().width(Size::fill()).vertical();
    for name in filtered {
        let selected = name == selected_name;
        options = options.child(theme_option(name, selected, value));
    }

    rect()
        .width(Size::fill())
        .padding(Gaps::new_all(17.))
        .vertical()
        .spacing(12.)
        .child(
            rect()
                .vertical()
                .spacing(3.)
                .child(label().font_size(14.).color(TEXT).text("Theme Preset"))
                .child(
                    label()
                        .font_size(12.)
                        .color(MUTED)
                        .text("Search and select a built-in terminal color theme."),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(302.))
                .horizontal()
                .content(Content::Flex)
                .spacing(16.)
                .cross_align(Alignment::Start)
                .child(
                    rect()
                        .width(Size::flex(1.))
                        .vertical()
                        .spacing(8.)
                        .child(
                            Input::new(search)
                                .width(Size::fill())
                                .placeholder("Search built-in themes")
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
                                .leading(
                                    SvgViewer::new(icons::lucide::search())
                                        .width(Size::px(16.))
                                        .height(Size::px(16.))
                                        .color(MUTED),
                                ),
                        )
                        .child(
                            rect()
                                .width(Size::fill())
                                .height(Size::px(254.))
                                .vertical()
                                .background(SURFACE)
                                .border(Border::new().width(1.).fill(BORDER))
                                .corner_radius(7.)
                                .child(
                                    rect()
                                        .height(Size::px(38.))
                                        .padding(Gaps::new(12., 8., 12., 8.))
                                        .horizontal()
                                        .content(Content::Flex)
                                        .cross_align(Alignment::Center)
                                        .child(
                                            label()
                                                .font_size(11.)
                                                .color(MUTED)
                                                .text(format!("Selected: {selected_name}")),
                                        )
                                        .child(rect().width(Size::flex(1.)).child(""))
                                        .child(label().font_size(11.).color(MUTED).text(format!(
                                            "Showing {count} of {}",
                                            TERMINAL_THEME_NAMES.len()
                                        ))),
                                )
                                .child(
                                    ScrollView::new()
                                        .width(Size::fill())
                                        .height(Size::flex(1.))
                                        .show_scrollbar(true)
                                        .child(options),
                                ),
                        ),
                )
                .child(theme_preview(&selected_name, palette)),
        )
        .into_element()
}

fn theme_option(name: &'static str, selected: bool, mut value: State<String>) -> Element {
    let palette = terminal_theme_palette(name);
    rect()
        .width(Size::fill())
        .height(Size::px(34.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(9.)
        .padding(Gaps::new(10., 5., 10., 5.))
        .background(if selected { SURFACE_RAISED } else { SURFACE })
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(name)
        .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
        .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            value.set(name.to_string());
        })
        .child(color_dots(palette))
        .child(label().font_size(12.).color(TEXT).text(name))
        .child(rect().width(Size::flex(1.)).child(""))
        .maybe_child(selected.then(|| {
            SvgViewer::new(icons::lucide::check())
                .width(Size::px(14.))
                .height(Size::px(14.))
                .color(TEXT)
        }))
        .into_element()
}

fn color_dots(palette: TerminalThemePalette) -> Element {
    rect()
        .width(Size::px(18.))
        .height(Size::px(12.))
        .horizontal()
        .content(Content::Flex)
        .spacing(2.)
        .children(
            [palette.normal[1], palette.normal[2], palette.normal[4]].map(|color| {
                rect()
                    .width(Size::flex(1.))
                    .height(Size::fill())
                    .corner_radius(6.)
                    .background(rgb(color))
            }),
        )
        .into_element()
}

fn theme_preview(name: &str, palette: TerminalThemePalette) -> Element {
    rect()
        .width(Size::px(280.))
        .height(Size::px(172.))
        .vertical()
        .spacing(8.)
        .padding(Gaps::new_all(12.))
        .background(rgb(palette.background))
        .border(Border::new().width(1.).fill(BORDER))
        .corner_radius(7.)
        .font_family("JetBrains Mono")
        .child(
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(8.)
                .child(
                    rect()
                        .width(Size::px(8.))
                        .height(Size::px(8.))
                        .corner_radius(4.)
                        .background(rgb(palette.normal[2])),
                )
                .child(
                    label()
                        .font_size(11.)
                        .color(rgb(palette.foreground))
                        .text(name.to_string()),
                ),
        )
        .child(
            label()
                .font_size(11.)
                .color(rgb(palette.foreground))
                .text("$ git status --short"),
        )
        .child(
            label()
                .font_size(11.)
                .color(rgb(palette.normal[3]))
                .text("M  lib/src/features/settings/presentation/settings_dialog.dart"),
        )
        .child(
            label()
                .font_size(11.)
                .color(rgb(palette.normal[2]))
                .text("A  lib/src/features/settings/domain/terminal_theme_catalog.dart"),
        )
        .child(
            label()
                .font_size(11.)
                .color(rgb(palette.normal[4]))
                .text("?? experiments/alera-freya/"),
        )
        .into_element()
}

fn rgb(value: u32) -> (u8, u8, u8) {
    (
        ((value >> 16) & 0xff) as u8,
        ((value >> 8) & 0xff) as u8,
        (value & 0xff) as u8,
    )
}
