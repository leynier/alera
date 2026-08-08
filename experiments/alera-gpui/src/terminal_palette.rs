use alacritty_terminal::vte::ansi;
use gpui::{rgb, Hsla};

use crate::terminal_theme_catalog::TerminalThemePalette;

pub fn resolve_color(color: ansi::Color, palette: TerminalThemePalette) -> Option<Hsla> {
    let resolved = match color {
        ansi::Color::Spec(value) => value,
        ansi::Color::Indexed(index) => indexed_color(index, palette),
        ansi::Color::Named(named) => named_color(named, palette),
    };
    Some(
        rgb((u32::from(resolved.r) << 16) | (u32::from(resolved.g) << 8) | u32::from(resolved.b))
            .into(),
    )
}

fn named_color(named: ansi::NamedColor, palette: TerminalThemePalette) -> ansi::Rgb {
    use ansi::NamedColor::*;
    let value = match named {
        Black | DimBlack => palette.normal[0],
        Red | DimRed => palette.normal[1],
        Green | DimGreen => palette.normal[2],
        Yellow | DimYellow => palette.normal[3],
        Blue | DimBlue => palette.normal[4],
        Magenta | DimMagenta => palette.normal[5],
        Cyan | DimCyan => palette.normal[6],
        White | DimWhite => palette.normal[7],
        Background => palette.background,
        Foreground | BrightForeground | DimForeground => palette.foreground,
        Cursor => palette.cursor,
        BrightBlack => palette.bright[0],
        BrightRed => palette.bright[1],
        BrightGreen => palette.bright[2],
        BrightYellow => palette.bright[3],
        BrightBlue => palette.bright[4],
        BrightMagenta => palette.bright[5],
        BrightCyan => palette.bright[6],
        BrightWhite => palette.bright[7],
    };
    packed_rgb(value)
}

fn indexed_color(index: u8, palette: TerminalThemePalette) -> ansi::Rgb {
    if index < 16 {
        return packed_rgb(if index < 8 {
            palette.normal[index as usize]
        } else {
            palette.bright[(index - 8) as usize]
        });
    }
    if index < 232 {
        let index = index - 16;
        let component = |value: u8| if value == 0 { 0 } else { value * 40 + 55 };
        return rgb_value(
            component(index / 36),
            component((index / 6) % 6),
            component(index % 6),
        );
    }
    let gray = (index - 232) * 10 + 8;
    rgb_value(gray, gray, gray)
}

fn rgb_value(r: u8, g: u8, b: u8) -> ansi::Rgb {
    ansi::Rgb { r, g, b }
}

fn packed_rgb(value: u32) -> ansi::Rgb {
    rgb_value(
        ((value >> 16) & 0xff) as u8,
        ((value >> 8) & 0xff) as u8,
        (value & 0xff) as u8,
    )
}
