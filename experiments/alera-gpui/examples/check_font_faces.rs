//! Native text-system regression, without a window, runtime or user settings.

#[path = "../src/app_fonts.rs"]
mod app_fonts;

fn main() {
    let app = gpui_platform::headless();
    let text_system = app.text_system();
    let baseline = std::env::args().any(|arg| arg == "--variable-baseline");
    if baseline {
        text_system
            .add_fonts(vec![
                std::borrow::Cow::Borrowed(include_bytes!("../../../assets/fonts/Inter-Variable.ttf")),
                std::borrow::Cow::Borrowed(include_bytes!("../../../assets/fonts/JetBrainsMono-Variable.ttf")),
            ])
            .expect("load original variable fonts");
    } else {
        app_fonts::register(&text_system).expect("load bundled font faces");
    }
    for (family, max_weight) in [("Inter", 900), ("JetBrains Mono", 800)] {
        let mut ids = Vec::new();
        for weight in (100..=max_weight).step_by(100) {
            let mut font = gpui::font(family);
            font.weight = if baseline {
                gpui::FontWeight(weight as f32)
            } else {
                app_fonts::font_weight(family, weight as f32)
            };
            let id = text_system.resolve_font(&font);
            println!("{family} {weight}: {id:?}");
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
        if baseline {
            println!("{family}: {} distinct original faces", ids.len());
        } else {
            assert_eq!(ids.len(), max_weight / 100, "weights must resolve to distinct native faces for {family}");
        }
    }
}
