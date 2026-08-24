use freya::prelude::*;

use crate::{ACCENT, BORDER, MUTED, SURFACE, TEXT, settings_terminal::terminal_row_shell};

pub(super) fn input_row(
    title: &'static str,
    description: &'static str,
    value: State<String>,
    fallback: &'static str,
) -> Element {
    let stored_value = value.read().clone();
    let current = Color::from_hex(if stored_value.trim().is_empty() {
        fallback
    } else {
        stored_value.trim()
    })
    .unwrap_or(Color::BLACK);
    let mut value_for_picker = value;
    let mut value_for_submit = value;
    terminal_row_shell(title, description)
        .child(
            rect()
                .width(Size::px(220.))
                .height(Size::px(40.))
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(8.)
                .child(
                    ColorPicker::new(move |color: Color| {
                        value_for_picker.set(format!(
                            "#{:02x}{:02x}{:02x}",
                            color.r(),
                            color.g(),
                            color.b()
                        ));
                    })
                    .value(current),
                )
                .child(
                    Input::new(value)
                        .width(Size::flex(1.))
                        .placeholder(fallback)
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
                        .on_submit(move |raw: String| {
                            value_for_submit.set(normalize_hex(&raw).unwrap_or_default());
                        }),
                ),
        )
        .into_element()
}

fn normalize_hex(value: &str) -> Option<String> {
    let digits = value.trim().trim_start_matches('#');
    if digits.len() != 6 || !digits.chars().all(|value| value.is_ascii_hexdigit()) {
        return None;
    }
    Some(format!("#{}", digits.to_lowercase()))
}

#[cfg(test)]
mod tests {
    use super::normalize_hex;

    #[test]
    fn normalizes_complete_rgb_hex_values() {
        assert_eq!(normalize_hex(" #F5A010 ").as_deref(), Some("#f5a010"));
        assert_eq!(normalize_hex("invalid"), None);
        assert_eq!(normalize_hex("#fff"), None);
    }
}
