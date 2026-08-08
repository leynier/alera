use gpui::{px, rgb, rgba, Pixels, Rgba};

pub fn app_background() -> Rgba {
    rgb(0x101010)
}

pub fn surface() -> Rgba {
    rgb(0x181818)
}

pub fn surface_raised() -> Rgba {
    rgb(0x242424)
}

pub fn surface_selected() -> Rgba {
    rgb(0x202020)
}

pub fn border() -> Rgba {
    rgb(0x323232)
}

pub fn border_subtle() -> Rgba {
    rgb(0x272727)
}

pub fn text() -> Rgba {
    rgb(0xf5f5f5)
}

pub fn text_muted() -> Rgba {
    rgb(0xa1a1a1)
}

pub fn text_faint() -> Rgba {
    rgb(0x606060)
}

pub fn accent() -> Rgba {
    rgb(0xe0e0e0)
}

pub fn accent_hover() -> Rgba {
    rgb(0xcecece)
}

pub fn accent_subtle() -> Rgba {
    rgba(0xe0e0e01a)
}

pub fn text_selection() -> Rgba {
    rgba(0x2195f36e)
}

pub fn on_accent() -> Rgba {
    app_background()
}

pub fn on_accent_divider() -> Rgba {
    rgba(0x1010102e)
}

pub fn overlay_scrim() -> Rgba {
    rgba(0x00000099)
}

pub fn success() -> Rgba {
    rgb(0x22c55e)
}

pub fn warning() -> Rgba {
    rgb(0xf59e0b)
}

pub fn info() -> Rgba {
    rgb(0x60a5fa)
}

pub fn danger() -> Rgba {
    rgb(0xf87171)
}

pub fn danger_hover() -> Rgba {
    rgb(0xe66767)
}

pub fn diff_add_background() -> Rgba {
    rgba(0x22c55e14)
}

pub fn diff_delete_background() -> Rgba {
    rgba(0xf8717114)
}

pub fn on_danger() -> Rgba {
    rgb(0x2c0d0d)
}

pub fn transparent() -> Rgba {
    rgba(0x00000000)
}

pub fn header_height() -> Pixels {
    px(44.0)
}

pub fn status_bar_height() -> Pixels {
    px(30.0)
}

pub fn tab_bar_height() -> Pixels {
    px(44.0)
}
