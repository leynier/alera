use std::collections::BTreeMap;

use freya::prelude::{State, WritableUtils};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::local_settings;
use alera_desktop_core::terminal_theme_catalog::{TerminalThemePalette, terminal_theme_palette};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub(crate) struct StoredTerminalSettings {
    pub(crate) terminal_font_family: String,
    pub(crate) terminal_font_size: f64,
    pub(crate) terminal_font_weight: i64,
    pub(crate) terminal_line_height: f64,
    pub(crate) terminal_padding_x: f64,
    pub(crate) terminal_padding_y: f64,
    pub(crate) terminal_cursor_shape: String,
    pub(crate) terminal_cursor_blink: bool,
    pub(crate) terminal_cursor_opacity: f64,
    pub(crate) terminal_theme_name: String,
    pub(crate) terminal_background_opacity: f64,
    pub(crate) terminal_word_separators: Option<String>,
    pub(crate) terminal_color_overrides: BTreeMap<String, String>,
    pub(crate) terminal_scrollback_lines: i64,
    pub(crate) terminal_tui_scroll_sensitivity: i64,
    pub(crate) terminal_clipboard_on_select: bool,
    pub(crate) terminal_allow_osc52_clipboard: bool,
    pub(crate) terminal_host_scrollback_bytes: i64,
    pub(crate) terminal_buffer_budget_megabytes: i64,
    pub(crate) terminal_login_shell: bool,
}

impl Default for StoredTerminalSettings {
    fn default() -> Self {
        Self {
            terminal_font_family: "JetBrains Mono".to_string(),
            terminal_font_size: 13.,
            terminal_font_weight: 400,
            terminal_line_height: 1.3,
            terminal_padding_x: 12.,
            terminal_padding_y: 12.,
            terminal_cursor_shape: "block".to_string(),
            terminal_cursor_blink: false,
            terminal_cursor_opacity: 1.,
            terminal_theme_name: "Alera Dark".to_string(),
            terminal_background_opacity: 1.,
            terminal_word_separators: None,
            terminal_color_overrides: BTreeMap::new(),
            terminal_scrollback_lines: 10_000,
            terminal_tui_scroll_sensitivity: 1,
            terminal_clipboard_on_select: false,
            terminal_allow_osc52_clipboard: false,
            terminal_host_scrollback_bytes: 10_000_000,
            terminal_buffer_budget_megabytes: 256,
            terminal_login_shell: cfg!(target_os = "macos"),
        }
    }
}

impl StoredTerminalSettings {
    pub(crate) fn resolved_palette(&self) -> TerminalThemePalette {
        let mut palette = terminal_theme_palette(&self.terminal_theme_name);
        let resolve = |key: &str, fallback| {
            self.terminal_color_overrides
                .get(key)
                .and_then(|value| parse_hex(value))
                .unwrap_or(fallback)
        };
        palette.foreground = resolve("foreground", palette.foreground);
        palette.background = resolve("background", palette.background);
        palette.cursor = resolve("cursor", palette.cursor);
        palette.selection = resolve("selection", palette.selection);
        palette
    }

    fn sanitize(mut self) -> Self {
        if self.terminal_font_family.trim().is_empty() {
            self.terminal_font_family = "JetBrains Mono".to_string();
        }
        self.terminal_font_size = self.terminal_font_size.clamp(8., 32.);
        self.terminal_font_weight = self.terminal_font_weight.clamp(100, 900);
        self.terminal_line_height = self.terminal_line_height.clamp(0.8, 2.4);
        self.terminal_padding_x = self.terminal_padding_x.clamp(0., 64.);
        self.terminal_padding_y = self.terminal_padding_y.clamp(0., 64.);
        self.terminal_cursor_opacity = self.terminal_cursor_opacity.clamp(0., 1.);
        self.terminal_background_opacity = self.terminal_background_opacity.clamp(0., 1.);
        if !matches!(
            self.terminal_cursor_shape.as_str(),
            "block" | "bar" | "underline"
        ) {
            self.terminal_cursor_shape = "block".to_string();
        }
        self
    }
}

fn parse_hex(value: &str) -> Option<u32> {
    let digits = value.trim().trim_start_matches('#');
    (digits.len() == 6)
        .then(|| u32::from_str_radix(digits, 16).ok())
        .flatten()
}

#[derive(Clone, Debug, PartialEq)]
pub(super) struct TerminalDraft {
    pub font_family: String,
    pub font_size: String,
    pub font_weight: String,
    pub line_height: String,
    pub padding_x: String,
    pub padding_y: String,
    pub cursor_shape: String,
    pub cursor_blink: bool,
    pub cursor_opacity: String,
    pub theme_name: String,
    pub background_opacity: String,
    pub foreground: String,
    pub background: String,
    pub cursor: String,
    pub selection: String,
    pub tui_scroll: String,
    pub clipboard_on_select: bool,
    pub allow_osc52: bool,
    pub login_shell: bool,
    pub scrollback_lines: String,
    pub host_scrollback_mb: String,
    pub buffer_budget_mb: String,
    pub word_separators: String,
}

impl From<StoredTerminalSettings> for TerminalDraft {
    fn from(value: StoredTerminalSettings) -> Self {
        let colors = value.terminal_color_overrides.clone();
        let color = |key: &str| colors.get(key).cloned().unwrap_or_default();
        Self {
            font_family: value.terminal_font_family,
            font_size: compact_number(value.terminal_font_size),
            font_weight: value.terminal_font_weight.to_string(),
            line_height: compact_number(value.terminal_line_height),
            padding_x: compact_number(value.terminal_padding_x),
            padding_y: compact_number(value.terminal_padding_y),
            cursor_shape: value.terminal_cursor_shape,
            cursor_blink: value.terminal_cursor_blink,
            cursor_opacity: compact_number(value.terminal_cursor_opacity),
            theme_name: value.terminal_theme_name,
            background_opacity: compact_number(value.terminal_background_opacity),
            foreground: color("foreground"),
            background: color("background"),
            cursor: color("cursor"),
            selection: color("selection"),
            tui_scroll: value.terminal_tui_scroll_sensitivity.to_string(),
            clipboard_on_select: value.terminal_clipboard_on_select,
            allow_osc52: value.terminal_allow_osc52_clipboard,
            login_shell: value.terminal_login_shell,
            scrollback_lines: value.terminal_scrollback_lines.to_string(),
            host_scrollback_mb: (value.terminal_host_scrollback_bytes / 1_000_000).to_string(),
            buffer_budget_mb: value.terminal_buffer_budget_megabytes.to_string(),
            word_separators: value.terminal_word_separators.unwrap_or_default(),
        }
    }
}

#[derive(Clone, Copy)]
pub(super) struct TerminalSignals {
    pub font_family: State<String>,
    pub font_size: State<String>,
    pub font_weight: State<String>,
    pub line_height: State<String>,
    pub padding_x: State<String>,
    pub padding_y: State<String>,
    pub cursor_shape: State<String>,
    pub cursor_blink: State<bool>,
    pub cursor_opacity: State<String>,
    pub theme_name: State<String>,
    pub background_opacity: State<String>,
    pub foreground: State<String>,
    pub background: State<String>,
    pub cursor: State<String>,
    pub selection: State<String>,
    pub tui_scroll: State<String>,
    pub clipboard_on_select: State<bool>,
    pub allow_osc52: State<bool>,
    pub login_shell: State<bool>,
    pub scrollback_lines: State<String>,
    pub host_scrollback_mb: State<String>,
    pub buffer_budget_mb: State<String>,
    pub word_separators: State<String>,
}

impl TerminalSignals {
    pub fn draft(self) -> TerminalDraft {
        TerminalDraft {
            font_family: self.font_family.read().clone(),
            font_size: self.font_size.read().clone(),
            font_weight: self.font_weight.read().clone(),
            line_height: self.line_height.read().clone(),
            padding_x: self.padding_x.read().clone(),
            padding_y: self.padding_y.read().clone(),
            cursor_shape: self.cursor_shape.read().clone(),
            cursor_blink: *self.cursor_blink.read(),
            cursor_opacity: self.cursor_opacity.read().clone(),
            theme_name: self.theme_name.read().clone(),
            background_opacity: self.background_opacity.read().clone(),
            foreground: self.foreground.read().clone(),
            background: self.background.read().clone(),
            cursor: self.cursor.read().clone(),
            selection: self.selection.read().clone(),
            tui_scroll: self.tui_scroll.read().clone(),
            clipboard_on_select: *self.clipboard_on_select.read(),
            allow_osc52: *self.allow_osc52.read(),
            login_shell: *self.login_shell.read(),
            scrollback_lines: self.scrollback_lines.read().clone(),
            host_scrollback_mb: self.host_scrollback_mb.read().clone(),
            buffer_budget_mb: self.buffer_budget_mb.read().clone(),
            word_separators: self.word_separators.read().clone(),
        }
    }

    pub fn apply(mut self, draft: TerminalDraft) {
        self.font_family.set(draft.font_family);
        self.font_size.set(draft.font_size);
        self.font_weight.set(draft.font_weight);
        self.line_height.set(draft.line_height);
        self.padding_x.set(draft.padding_x);
        self.padding_y.set(draft.padding_y);
        self.cursor_shape.set(draft.cursor_shape);
        self.cursor_blink.set(draft.cursor_blink);
        self.cursor_opacity.set(draft.cursor_opacity);
        self.theme_name.set(draft.theme_name);
        self.background_opacity.set(draft.background_opacity);
        self.foreground.set(draft.foreground);
        self.background.set(draft.background);
        self.cursor.set(draft.cursor);
        self.selection.set(draft.selection);
        self.tui_scroll.set(draft.tui_scroll);
        self.clipboard_on_select.set(draft.clipboard_on_select);
        self.allow_osc52.set(draft.allow_osc52);
        self.login_shell.set(draft.login_shell);
        self.scrollback_lines.set(draft.scrollback_lines);
        self.host_scrollback_mb.set(draft.host_scrollback_mb);
        self.buffer_budget_mb.set(draft.buffer_budget_mb);
        self.word_separators.set(draft.word_separators);
    }
}

pub(super) fn load_draft() -> TerminalDraft {
    load_settings().into()
}

pub(crate) fn load_settings() -> StoredTerminalSettings {
    local_settings::load_subset::<StoredTerminalSettings>().sanitize()
}

pub(super) fn persist_draft(draft: &TerminalDraft) -> Result<(), String> {
    let Some(fields) = persisted_fields(draft) else {
        return Ok(());
    };
    local_settings::persist_fields(fields)
}

pub(super) fn compact_number(value: f64) -> String {
    if value.fract() == 0. {
        format!("{value:.0}")
    } else {
        value.to_string()
    }
}

fn persisted_fields(draft: &TerminalDraft) -> Option<Vec<(&'static str, Value)>> {
    if draft.font_family.trim().is_empty() {
        return None;
    }
    let number = |value: &str| value.trim().parse::<f64>().ok();
    let integer = |value: &str| value.trim().parse::<i64>().ok();
    let colors = [
        ("foreground", &draft.foreground),
        ("background", &draft.background),
        ("cursor", &draft.cursor),
        ("selection", &draft.selection),
    ]
    .into_iter()
    .filter_map(|(key, value)| normalize_hex(value).map(|value| (key, value)))
    .collect::<BTreeMap<_, _>>();
    Some(vec![
        ("terminal_font_family", json!(&draft.font_family)),
        (
            "terminal_font_size",
            json!(number(&draft.font_size)?.clamp(8., 32.)),
        ),
        (
            "terminal_font_weight",
            json!(integer(&draft.font_weight)?.clamp(100, 900)),
        ),
        (
            "terminal_line_height",
            json!(number(&draft.line_height)?.clamp(0.8, 2.4)),
        ),
        (
            "terminal_padding_x",
            json!(number(&draft.padding_x)?.clamp(0., 64.)),
        ),
        (
            "terminal_padding_y",
            json!(number(&draft.padding_y)?.clamp(0., 64.)),
        ),
        ("terminal_cursor_shape", json!(&draft.cursor_shape)),
        ("terminal_cursor_blink", json!(draft.cursor_blink)),
        (
            "terminal_cursor_opacity",
            json!(number(&draft.cursor_opacity)?.clamp(0., 1.)),
        ),
        ("terminal_theme_name", json!(&draft.theme_name)),
        (
            "terminal_background_opacity",
            json!(number(&draft.background_opacity)?.clamp(0., 1.)),
        ),
        (
            "terminal_word_separators",
            json!((!draft.word_separators.trim().is_empty()).then(|| draft.word_separators.trim())),
        ),
        ("terminal_color_overrides", json!(colors)),
        (
            "terminal_scrollback_lines",
            json!(integer(&draft.scrollback_lines)?.clamp(100, 200_000)),
        ),
        (
            "terminal_tui_scroll_sensitivity",
            json!(integer(&draft.tui_scroll)?.clamp(1, 10)),
        ),
        (
            "terminal_clipboard_on_select",
            json!(draft.clipboard_on_select),
        ),
        ("terminal_allow_osc52_clipboard", json!(draft.allow_osc52)),
        (
            "terminal_host_scrollback_bytes",
            json!(integer(&draft.host_scrollback_mb)?.clamp(1, 256) * 1_000_000),
        ),
        (
            "terminal_buffer_budget_megabytes",
            json!(integer(&draft.buffer_budget_mb)?.clamp(0, 4096)),
        ),
        ("terminal_login_shell", json!(draft.login_shell)),
    ])
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
    use super::{StoredTerminalSettings, TerminalDraft, persisted_fields};

    #[test]
    fn terminal_draft_validates_and_converts_storage_units() {
        let mut draft: TerminalDraft = StoredTerminalSettings::default().into();
        draft.font_size = "200".to_string();
        draft.host_scrollback_mb = "12".to_string();
        let fields = persisted_fields(&draft).expect("valid draft");
        let field = |name: &str| {
            fields
                .iter()
                .find(|(key, _)| *key == name)
                .map(|(_, value)| value)
        };
        assert_eq!(
            field("terminal_font_size").and_then(serde_json::Value::as_f64),
            Some(32.)
        );
        assert_eq!(
            field("terminal_host_scrollback_bytes").and_then(serde_json::Value::as_i64),
            Some(12_000_000)
        );
    }
}
