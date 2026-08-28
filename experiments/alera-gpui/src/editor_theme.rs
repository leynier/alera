use gpui_component::{
    highlighter::{HighlightTheme, HighlightThemeStyle, LanguageRegistry},
    Theme, ThemeMode,
};
use std::sync::Arc;

const ALERA_MARKDOWN_LANGUAGE: &str = "markdown-alera";

/// Register a Markdown variant whose heading captures match re_highlight's
/// `section` role instead of the generic code `title` role. Flutter renders
/// Markdown through highlight.js semantics, where GitHub headings are blue
/// while functions and class titles remain purple.
pub fn register_editor_languages() {
    let registry = LanguageRegistry::singleton();
    if registry
        .languages()
        .iter()
        .any(|name| name.as_ref() == ALERA_MARKDOWN_LANGUAGE)
    {
        return;
    }
    let Some(mut markdown) = registry.language("markdown") else {
        return;
    };
    markdown.name = ALERA_MARKDOWN_LANGUAGE.into();
    markdown.highlights = markdown
        .highlights
        .replace(
            "(atx_heading (inline) @title)",
            "(atx_heading (inline) @label)",
        )
        .replace(
            "(setext_heading (paragraph) @title)",
            "(setext_heading (paragraph) @label)",
        )
        .replacen("] @punctuation.special", "] @label", 1)
        .into();
    registry.register(ALERA_MARKDOWN_LANGUAGE, &markdown);
}

pub fn markdown_language_name() -> &'static str {
    ALERA_MARKDOWN_LANGUAGE
}

/// Apply the editor syntax palette selected by Flutter to the shared
/// gpui-component highlighter. Input's code-editor mode reads this same
/// global theme for its background, foreground and token styles.
pub fn apply_editor_theme<C: gpui::BorrowAppContext>(cx: &mut C, name: &str) {
    let normalized = name.trim().to_ascii_lowercase();
    let (theme_name, palette) = editor_palette(&normalized);
    let style = editor_highlight_style(palette);
    cx.update_global::<Theme, _>(|theme, _| {
        theme.highlight_theme = Arc::new(HighlightTheme {
            name: theme_name.to_owned(),
            appearance: ThemeMode::Dark,
            style,
        });
    });
}

fn editor_highlight_style(palette: EditorPalette) -> HighlightThemeStyle {
    let style_json = serde_json::json!({
        "editor.foreground": palette.foreground,
        "editor.background": palette.background,
        "editor.line_number": palette.line_number,
        "syntax": {
            "attribute": {"color": palette.attribute},
            "boolean": {"color": palette.literal},
            "comment": {"color": palette.comment},
            "constant": {"color": palette.literal},
            "constructor": {"color": palette.constructor},
            "function": {"color": palette.function},
            "keyword": {"color": palette.keyword},
            "label": {"color": palette.section, "font_weight": 700},
            "number": {"color": palette.number},
            "operator": {"color": palette.operator},
            "property": {"color": palette.property},
            "punctuation.list_marker": {"color": palette.bullet},
            "string": {"color": palette.string},
            "tag": {"color": palette.tag},
            "text.literal": {"color": palette.comment},
            "title": {"color": palette.title, "font_weight": 600},
            "type": {"color": palette.type_color},
            "variable": {"color": palette.variable},
            "emphasis": {"color": palette.foreground, "font_style": "italic"},
            "emphasis.strong": {"color": palette.foreground, "font_weight": 700}
        }
    });
    serde_json::from_value::<HighlightThemeStyle>(style_json)
        .unwrap_or_else(|_| HighlightThemeStyle::default())
}

#[derive(Clone, Copy)]
struct EditorPalette {
    background: &'static str,
    foreground: &'static str,
    line_number: &'static str,
    keyword: &'static str,
    title: &'static str,
    property: &'static str,
    string: &'static str,
    comment: &'static str,
    function: &'static str,
    type_color: &'static str,
    number: &'static str,
    variable: &'static str,
    attribute: &'static str,
    literal: &'static str,
    operator: &'static str,
    constructor: &'static str,
    tag: &'static str,
    section: &'static str,
    bullet: &'static str,
}

fn editor_palette(name: &str) -> (&'static str, EditorPalette) {
    match name {
        "github dark" => (
            "GitHub Dark",
            EditorPalette {
                background: "#0d1117",
                foreground: "#c9d1d9",
                line_number: "#8b949e",
                keyword: "#ff7b72",
                title: "#d2a8ff",
                property: "#79c0ff",
                string: "#a5d6ff",
                comment: "#8b949e",
                function: "#d2a8ff",
                type_color: "#ff7b72",
                number: "#79c0ff",
                variable: "#79c0ff",
                attribute: "#79c0ff",
                literal: "#79c0ff",
                operator: "#79c0ff",
                constructor: "#ffa657",
                tag: "#7ee787",
                section: "#1f6feb",
                bullet: "#f2cc60",
            },
        ),
        "github dark dimmed" => (
            "GitHub Dark Dimmed",
            EditorPalette {
                background: "#22272e",
                foreground: "#adbac7",
                line_number: "#768390",
                keyword: "#f47067",
                title: "#dcbdfb",
                property: "#6cb6ff",
                string: "#96d0ff",
                comment: "#768390",
                function: "#dcbdfb",
                type_color: "#f47067",
                number: "#6cb6ff",
                variable: "#6cb6ff",
                attribute: "#6cb6ff",
                literal: "#6cb6ff",
                operator: "#6cb6ff",
                constructor: "#f69d50",
                tag: "#8ddb8c",
                section: "#316dca",
                bullet: "#eac55f",
            },
        ),
        "vs2015" => (
            "VS2015",
            EditorPalette {
                background: "#1e1e1e",
                foreground: "#dcdcdc",
                line_number: "#858585",
                keyword: "#569cd6",
                title: "#dcdcdc",
                property: "#9cdcfe",
                string: "#d69d85",
                comment: "#608b4e",
                function: "#dcdcdc",
                type_color: "#4ec9b0",
                number: "#b8d7a3",
                variable: "#bd63c5",
                attribute: "#9cdcfe",
                literal: "#569cd6",
                operator: "#dcdcdc",
                constructor: "#4ec9b0",
                tag: "#9b9b9b",
                section: "#ffd700",
                bullet: "#d7ba7d",
            },
        ),
        "atom one dark" => (
            "Atom One Dark",
            EditorPalette {
                background: "#282c34",
                foreground: "#abb2bf",
                line_number: "#5c6370",
                keyword: "#c678dd",
                title: "#61aeee",
                property: "#d19a66",
                string: "#98c379",
                comment: "#5c6370",
                function: "#61aeee",
                type_color: "#d19a66",
                number: "#d19a66",
                variable: "#d19a66",
                attribute: "#98c379",
                literal: "#56b6c2",
                operator: "#c678dd",
                constructor: "#e6c07b",
                tag: "#e06c75",
                section: "#e06c75",
                bullet: "#61aeee",
            },
        ),
        "night owl" => (
            "Night Owl",
            EditorPalette {
                background: "#011627",
                foreground: "#d6deeb",
                line_number: "#5ca7e4",
                keyword: "#c792ea",
                title: "#82b1ff",
                property: "#80cbc4",
                string: "#ecc48d",
                comment: "#637777",
                function: "#82aaff",
                type_color: "#82aaff",
                number: "#f78c6c",
                variable: "#addb67",
                attribute: "#7fdbca",
                literal: "#ff5874",
                operator: "#c792ea",
                constructor: "#7fdbca",
                tag: "#7fdbca",
                section: "#82b1ff",
                bullet: "#d9f5dd",
            },
        ),
        "nord" => (
            "Nord",
            EditorPalette {
                background: "#2e3440",
                foreground: "#d8dee9",
                line_number: "#4c566a",
                keyword: "#81a1c1",
                title: "#88c0d0",
                property: "#88c0d0",
                string: "#a3be8c",
                comment: "#4c566a",
                function: "#88c0d0",
                type_color: "#8fbcbb",
                number: "#b48ead",
                variable: "#d8dee9",
                attribute: "#d8dee9",
                literal: "#81a1c1",
                operator: "#81a1c1",
                constructor: "#8fbcbb",
                tag: "#81a1c1",
                section: "#88c0d0",
                bullet: "#81a1c1",
            },
        ),
        "monokai" => (
            "Monokai",
            EditorPalette {
                background: "#272822",
                foreground: "#dddddd",
                line_number: "#75715e",
                keyword: "#f92672",
                title: "#ffffff",
                property: "#a6e22e",
                string: "#a6e22e",
                comment: "#75715e",
                function: "#a6e22e",
                type_color: "#66d9ef",
                number: "#ae81ff",
                variable: "#a6e22e",
                attribute: "#bf79db",
                literal: "#f92672",
                operator: "#f92672",
                constructor: "#e6db74",
                tag: "#f92672",
                section: "#a6e22e",
                bullet: "#a6e22e",
            },
        ),
        "tokyo night dark" => (
            "Tokyo Night Dark",
            EditorPalette {
                background: "#1a1b26",
                foreground: "#9aa5ce",
                line_number: "#565f89",
                keyword: "#bb9af7",
                title: "#7dcfff",
                property: "#7dcfff",
                string: "#9ece6a",
                comment: "#565f89",
                function: "#7dcfff",
                type_color: "#ff9e64",
                number: "#ff9e64",
                variable: "#ff9e64",
                attribute: "#bb9af7",
                literal: "#ff9e64",
                operator: "#bb9af7",
                constructor: "#e0af68",
                tag: "#73daca",
                section: "#7aa2f7",
                bullet: "#9ece6a",
            },
        ),
        "dracula" => (
            "Dracula",
            EditorPalette {
                background: "#282936",
                foreground: "#e9e9f4",
                line_number: "#626483",
                keyword: "#b45bcf",
                title: "#00f769",
                property: "#62d6e8",
                string: "#ebff87",
                comment: "#626483",
                function: "#62d6e8",
                type_color: "#b45bcf",
                number: "#b45bcf",
                variable: "#ea51b2",
                attribute: "#62d6e8",
                literal: "#b45bcf",
                operator: "#e9e9f4",
                constructor: "#a1efe4",
                tag: "#62d6e8",
                section: "#62d6e8",
                bullet: "#ea51b2",
            },
        ),
        _ => (
            "Alera",
            EditorPalette {
                background: "#101010",
                foreground: "#f5f5f5",
                line_number: "#606060",
                keyword: "#c792ea",
                title: "#82aaff",
                property: "#82aaff",
                string: "#22c55e",
                comment: "#606060",
                function: "#82aaff",
                type_color: "#89ddff",
                number: "#f59e0b",
                variable: "#ffcc80",
                attribute: "#ffcb6b",
                literal: "#ffcb6b",
                operator: "#89ddff",
                constructor: "#ffcb6b",
                tag: "#c792ea",
                section: "#82aaff",
                bullet: "#f59e0b",
            },
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        editor_highlight_style, editor_palette, markdown_language_name, register_editor_languages,
    };
    use gpui_component::{
        highlighter::{HighlightTheme, LanguageRegistry, SyntaxHighlighter},
        Rope, ThemeMode,
    };
    use std::sync::Arc;

    #[test]
    fn editor_palette_catalog_matches_flutter_names() {
        for (name, expected_label, expected_background) in [
            ("alera", "Alera", "#101010"),
            ("github dark", "GitHub Dark", "#0d1117"),
            ("github dark dimmed", "GitHub Dark Dimmed", "#22272e"),
            ("vs2015", "VS2015", "#1e1e1e"),
            ("atom one dark", "Atom One Dark", "#282c34"),
            ("night owl", "Night Owl", "#011627"),
            ("nord", "Nord", "#2e3440"),
            ("monokai", "Monokai", "#272822"),
            ("tokyo night dark", "Tokyo Night Dark", "#1a1b26"),
            ("dracula", "Dracula", "#282936"),
        ] {
            let (label, palette) = editor_palette(name);
            assert_eq!(label, expected_label);
            assert_eq!(palette.background, expected_background);
            let style = editor_highlight_style(palette);
            assert!(style.editor_background.is_some());
            // CodeForge does not paint a persistent current-line background
            // or a brighter current-line number. Keeping these absent avoids
            // a GPUI-only stripe in active and inactive editor panes.
            assert!(style.editor_active_line.is_none());
            assert!(style.editor_active_line_number.is_none());
            assert!(style.syntax.label.is_some());
            assert!(style.syntax.punctuation_list_marker.is_some());
        }
    }

    #[test]
    fn markdown_headings_use_the_flutter_section_capture() {
        register_editor_languages();
        let language = LanguageRegistry::singleton()
            .language(markdown_language_name())
            .expect("Alera Markdown language should be registered");
        assert!(language.highlights.contains("@label"));
        assert!(!language
            .highlights
            .contains("(atx_heading (inline) @title)"));

        let source = "# Heading\n";
        let rope = Rope::from_str(source);
        let mut highlighter = SyntaxHighlighter::new(markdown_language_name());
        highlighter.update(None, &rope, None);
        let (_, palette) = editor_palette("github dark");
        let theme = Arc::new(HighlightTheme {
            name: "GitHub Dark".to_owned(),
            appearance: ThemeMode::Dark,
            style: editor_highlight_style(palette),
        });
        let styles = highlighter.styles(&(0..source.len()), theme.as_ref());
        assert!(styles
            .iter()
            .any(|(range, style)| { range.start < 9 && range.end > 2 && style.color.is_some() }));
    }
}
