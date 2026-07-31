use gpui::{px, rgb, Pixels, Rgba};

pub fn app_background() -> Rgba {
    rgb(0x0f1115)
}

pub fn surface() -> Rgba {
    rgb(0x15181e)
}

pub fn surface_raised() -> Rgba {
    rgb(0x1a1e25)
}

pub fn surface_selected() -> Rgba {
    rgb(0x252b35)
}

pub fn border() -> Rgba {
    rgb(0x2a2e37)
}

pub fn text() -> Rgba {
    rgb(0xe7e9ee)
}

pub fn text_muted() -> Rgba {
    rgb(0x8d95a5)
}

pub fn accent() -> Rgba {
    rgb(0x79a7ff)
}

pub fn success() -> Rgba {
    rgb(0x75c991)
}

pub fn warning() -> Rgba {
    rgb(0xe3b341)
}

pub fn danger() -> Rgba {
    rgb(0xf47067)
}

pub fn title_bar_height() -> Pixels {
    px(42.0)
}

pub fn activity_rail_width() -> Pixels {
    px(48.0)
}

pub fn sidebar_width() -> Pixels {
    px(284.0)
}

pub fn status_bar_height() -> Pixels {
    px(24.0)
}

pub fn tab_bar_height() -> Pixels {
    px(38.0)
}
