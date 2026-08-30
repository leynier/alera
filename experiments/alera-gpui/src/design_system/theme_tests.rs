use super::*;

#[gpui::test]
fn component_theme_synchronizes_dark_paint_tokens(cx: &mut gpui::TestAppContext) {
    let cx = cx.add_empty_window();
    cx.update(|_, cx| {
        gpui_component::init(cx);
        configure_component_theme(cx);
        let configured = Theme::global(cx);
        assert!(configured.mode.is_dark());
        assert_eq!(configured.font_size, px(16.0));
        for (paint, color) in [
            (configured.tokens.background.color, configured.background),
            (configured.tokens.popover.color, configured.popover),
            (configured.tokens.primary.color, configured.primary),
            (configured.tokens.muted.color, configured.muted),
            (configured.tokens.table.color, configured.table),
            (configured.tokens.table_head.color, configured.table_head),
        ] {
            assert_eq!(paint, color);
        }
        assert_eq!(configured.table, gpui::Hsla::from(theme::app_background()));
        assert_eq!(configured.table_head_foreground, gpui::Hsla::from(theme::text()));
    });
}

#[test]
fn typography_roles_match_the_flutter_source_scale() {
    let flutter = include_str!("../../../../lib/src/app/theme/alera_dark_theme.dart");
    for (role, size) in [
        ("bodyMedium", theme::body_size()),
        ("bodySmall", theme::caption_size()),
        ("titleLarge", theme::title_size()),
        ("headlineMedium", theme::headline_size()),
    ] {
        let pattern = format!(r"{role}: const TextStyle\([^)]*fontSize:\s*(\d+)");
        let expression = regex::Regex::new(&pattern).unwrap();
        let capture = expression.captures(flutter).unwrap();
        let reference: f32 = capture[1].parse().unwrap();
        assert_eq!(size, px(reference), "Flutter text role {role}");
    }
}
