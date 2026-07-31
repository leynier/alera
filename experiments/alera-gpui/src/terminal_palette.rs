use alacritty_terminal::vte::ansi;
use gpui::{rgb, Hsla};

pub fn resolve_color(color: ansi::Color, _background: bool) -> Option<Hsla> {
    let resolved = match color {
        ansi::Color::Spec(value) => value,
        ansi::Color::Indexed(index) => indexed_color(index),
        ansi::Color::Named(named) => named_color(named),
    };
    Some(
        rgb((u32::from(resolved.r) << 16) | (u32::from(resolved.g) << 8) | u32::from(resolved.b))
            .into(),
    )
}

fn named_color(named: ansi::NamedColor) -> ansi::Rgb {
    use ansi::NamedColor::*;
    match named {
        Black => rgb_value(40, 44, 52),
        Red => rgb_value(224, 108, 117),
        Green => rgb_value(152, 195, 121),
        Yellow => rgb_value(229, 192, 123),
        Blue => rgb_value(97, 175, 239),
        Magenta => rgb_value(198, 120, 221),
        Cyan => rgb_value(86, 182, 194),
        White => rgb_value(171, 178, 191),
        Background => rgb_value(15, 17, 21),
        Foreground | BrightForeground | DimForeground => rgb_value(231, 233, 238),
        Cursor => rgb_value(121, 167, 255),
        BrightBlack => rgb_value(92, 99, 112),
        BrightRed => rgb_value(248, 128, 137),
        BrightGreen => rgb_value(180, 222, 149),
        BrightYellow => rgb_value(255, 215, 150),
        BrightBlue => rgb_value(126, 197, 255),
        BrightMagenta => rgb_value(222, 148, 245),
        BrightCyan => rgb_value(113, 211, 222),
        BrightWhite => rgb_value(255, 255, 255),
        DimBlack => rgb_value(28, 31, 37),
        DimRed => rgb_value(156, 76, 82),
        DimGreen => rgb_value(106, 137, 85),
        DimYellow => rgb_value(160, 134, 86),
        DimBlue => rgb_value(68, 122, 167),
        DimMagenta => rgb_value(139, 84, 155),
        DimCyan => rgb_value(60, 127, 136),
        DimWhite => rgb_value(120, 125, 134),
    }
}

fn indexed_color(index: u8) -> ansi::Rgb {
    if index < 16 {
        return match index {
            0 => named_color(ansi::NamedColor::Black),
            1 => named_color(ansi::NamedColor::Red),
            2 => named_color(ansi::NamedColor::Green),
            3 => named_color(ansi::NamedColor::Yellow),
            4 => named_color(ansi::NamedColor::Blue),
            5 => named_color(ansi::NamedColor::Magenta),
            6 => named_color(ansi::NamedColor::Cyan),
            7 => named_color(ansi::NamedColor::White),
            8 => named_color(ansi::NamedColor::BrightBlack),
            9 => named_color(ansi::NamedColor::BrightRed),
            10 => named_color(ansi::NamedColor::BrightGreen),
            11 => named_color(ansi::NamedColor::BrightYellow),
            12 => named_color(ansi::NamedColor::BrightBlue),
            13 => named_color(ansi::NamedColor::BrightMagenta),
            14 => named_color(ansi::NamedColor::BrightCyan),
            _ => named_color(ansi::NamedColor::BrightWhite),
        };
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
