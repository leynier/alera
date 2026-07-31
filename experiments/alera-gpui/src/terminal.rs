use std::sync::{Arc, Mutex};

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::{Dimensions, Scroll};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::term::test::TermSize;
use alacritty_terminal::term::{Config, Term, TermMode};
use alacritty_terminal::vte::ansi;
use gpui::{FontStyle, FontWeight, HighlightStyle, SharedString, StyledText};

use crate::terminal_palette::resolve_color;

const DEFAULT_COLUMNS: usize = 100;
const DEFAULT_ROWS: usize = 30;
const SCROLLBACK_LINES: usize = 10_000;

#[derive(Clone, Default)]
struct TerminalEventSink {
    effects: Arc<Mutex<TerminalEffects>>,
}

#[derive(Default)]
struct TerminalEffects {
    title: Option<String>,
    pty_writes: Vec<Vec<u8>>,
    bell_count: usize,
}

impl EventListener for TerminalEventSink {
    fn send_event(&self, event: Event) {
        let Ok(mut effects) = self.effects.lock() else {
            return;
        };
        match event {
            Event::Title(title) => effects.title = Some(title),
            Event::ResetTitle => effects.title = None,
            Event::PtyWrite(text) => effects.pty_writes.push(text.into_bytes()),
            Event::Bell => effects.bell_count += 1,
            _ => {}
        }
    }
}

pub struct TerminalEmulator {
    terminal: Term<TerminalEventSink>,
    parser: ansi::Processor,
    event_sink: TerminalEventSink,
}

pub struct TerminalLine {
    pub text: StyledText,
}

pub struct TerminalSession {
    pub session_id: String,
    pub attaching: bool,
    pub running: bool,
    pub error: Option<String>,
    pub columns: usize,
    pub rows: usize,
    pub emulator: TerminalEmulator,
}

impl TerminalEmulator {
    pub fn new(columns: usize, rows: usize) -> Self {
        let event_sink = TerminalEventSink::default();
        let config = Config {
            scrolling_history: SCROLLBACK_LINES,
            ..Config::default()
        };
        let terminal = Term::new(
            config,
            &TermSize::new(columns.max(2), rows.max(2)),
            event_sink.clone(),
        );
        Self {
            terminal,
            parser: ansi::Processor::new(),
            event_sink,
        }
    }

    pub fn write(&mut self, bytes: &[u8]) {
        self.parser.advance(&mut self.terminal, bytes);
    }

    pub fn resize(&mut self, columns: usize, rows: usize) {
        self.terminal
            .resize(TermSize::new(columns.max(2), rows.max(2)));
    }

    pub fn scroll_display(&mut self, lines: i32) {
        self.terminal.scroll_display(Scroll::Delta(lines));
    }

    pub fn title(&self) -> Option<String> {
        self.event_sink
            .effects
            .lock()
            .ok()
            .and_then(|effects| effects.title.clone())
    }

    pub fn take_pty_writes(&self) -> Vec<Vec<u8>> {
        self.event_sink
            .effects
            .lock()
            .map(|mut effects| std::mem::take(&mut effects.pty_writes))
            .unwrap_or_default()
    }

    pub fn encode_key(
        &self,
        key: &str,
        key_char: Option<&str>,
        modifiers: KeyModifiers,
    ) -> Vec<u8> {
        let mode = self.terminal.mode();
        let sequence = match key {
            "enter" => Some(b"\r".as_slice()),
            "backspace" => Some(b"\x7f".as_slice()),
            "tab" => Some(if modifiers.shift {
                b"\x1b[Z".as_slice()
            } else {
                b"\t".as_slice()
            }),
            "escape" => Some(b"\x1b".as_slice()),
            "up" => Some(cursor_sequence(b'A', mode.contains(TermMode::APP_CURSOR))),
            "down" => Some(cursor_sequence(b'B', mode.contains(TermMode::APP_CURSOR))),
            "right" => Some(cursor_sequence(b'C', mode.contains(TermMode::APP_CURSOR))),
            "left" => Some(cursor_sequence(b'D', mode.contains(TermMode::APP_CURSOR))),
            "home" => Some(b"\x1b[H".as_slice()),
            "end" => Some(b"\x1b[F".as_slice()),
            "delete" => Some(b"\x1b[3~".as_slice()),
            "pageup" => Some(b"\x1b[5~".as_slice()),
            "pagedown" => Some(b"\x1b[6~".as_slice()),
            _ => None,
        };
        if let Some(sequence) = sequence {
            return with_alt_prefix(sequence, modifiers.alt);
        }
        if modifiers.control {
            if let Some(character) = key.chars().next() {
                if character.is_ascii() {
                    let control = (character.to_ascii_uppercase() as u8) & 0x1f;
                    return with_alt_prefix(&[control], modifiers.alt);
                }
            }
        }
        if modifiers.platform || modifiers.function {
            return Vec::new();
        }
        key_char
            .or_else(|| (key.chars().count() == 1).then_some(key))
            .map(|text| with_alt_prefix(text.as_bytes(), modifiers.alt))
            .unwrap_or_default()
    }

    pub fn encode_paste(&self, text: &str) -> Vec<u8> {
        if self.terminal.mode().contains(TermMode::BRACKETED_PASTE) {
            let mut bytes = Vec::with_capacity(text.len() + 12);
            bytes.extend_from_slice(b"\x1b[200~");
            bytes.extend_from_slice(text.replace("\x1b[201~", "").as_bytes());
            bytes.extend_from_slice(b"\x1b[201~");
            bytes
        } else {
            text.as_bytes().to_vec()
        }
    }

    pub fn visible_lines(&self) -> Vec<TerminalLine> {
        let rows = self.terminal.screen_lines();
        let columns = self.terminal.columns();
        let mut cells = vec![Vec::with_capacity(columns); rows];
        let content = self.terminal.renderable_content();
        for indexed in content.display_iter {
            let row = indexed.point.line.0;
            if row < 0 || row as usize >= rows {
                continue;
            }
            cells[row as usize].push(indexed.cell.clone());
        }

        cells
            .into_iter()
            .map(|row| {
                let mut text = String::with_capacity(columns);
                let mut highlights = Vec::new();
                for cell in row {
                    if cell.flags.contains(Flags::WIDE_CHAR_SPACER) {
                        continue;
                    }
                    let start = text.len();
                    let character = if cell.flags.contains(Flags::HIDDEN) {
                        ' '
                    } else {
                        cell.c
                    };
                    text.push(character);
                    if let Some(zerowidth) = cell.zerowidth() {
                        text.extend(zerowidth);
                    }
                    let end = text.len();
                    let style = HighlightStyle {
                        color: resolve_color(cell.fg, false),
                        background_color: resolve_color(cell.bg, true),
                        font_weight: cell
                            .flags
                            .intersects(Flags::BOLD | Flags::BOLD_ITALIC)
                            .then_some(FontWeight::BOLD),
                        font_style: cell
                            .flags
                            .intersects(Flags::ITALIC | Flags::BOLD_ITALIC)
                            .then_some(FontStyle::Italic),
                        ..HighlightStyle::default()
                    };
                    highlights.push((start..end, style));
                }
                TerminalLine {
                    text: StyledText::new(SharedString::from(text)).with_highlights(highlights),
                }
            })
            .collect()
    }

    #[allow(dead_code)]
    pub fn visible_text(&self) -> String {
        self.terminal
            .renderable_content()
            .display_iter
            .filter(|indexed| !indexed.cell.flags.contains(Flags::WIDE_CHAR_SPACER))
            .map(|indexed| {
                if indexed.cell.flags.contains(Flags::HIDDEN) {
                    ' '
                } else {
                    indexed.cell.c
                }
            })
            .collect()
    }
}

impl Default for TerminalEmulator {
    fn default() -> Self {
        Self::new(DEFAULT_COLUMNS, DEFAULT_ROWS)
    }
}

impl TerminalSession {
    pub fn new(session_id: String) -> Self {
        Self {
            session_id,
            attaching: true,
            running: true,
            error: None,
            columns: DEFAULT_COLUMNS,
            rows: DEFAULT_ROWS,
            emulator: TerminalEmulator::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct KeyModifiers {
    pub control: bool,
    pub alt: bool,
    pub shift: bool,
    pub platform: bool,
    pub function: bool,
}

fn cursor_sequence(final_byte: u8, application: bool) -> &'static [u8] {
    match (final_byte, application) {
        (b'A', true) => b"\x1bOA",
        (b'B', true) => b"\x1bOB",
        (b'C', true) => b"\x1bOC",
        (b'D', true) => b"\x1bOD",
        (b'A', false) => b"\x1b[A",
        (b'B', false) => b"\x1b[B",
        (b'C', false) => b"\x1b[C",
        (b'D', false) => b"\x1b[D",
        _ => b"",
    }
}

fn with_alt_prefix(bytes: &[u8], alt: bool) -> Vec<u8> {
    if !alt {
        return bytes.to_vec();
    }
    let mut prefixed = Vec::with_capacity(bytes.len() + 1);
    prefixed.push(0x1b);
    prefixed.extend_from_slice(bytes);
    prefixed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vt_output_updates_visible_rows_and_styles() {
        let mut terminal = TerminalEmulator::new(20, 3);
        terminal.write(b"plain\r\n\x1b[31mred\x1b[0m");
        let lines = terminal.visible_lines();
        assert_eq!(lines.len(), 3);
        assert!(terminal.visible_text().contains("plain"));
    }

    #[test]
    fn key_encoding_respects_application_cursor_and_control_keys() {
        let terminal = TerminalEmulator::new(20, 3);
        assert_eq!(
            terminal.encode_key(
                "c",
                Some("c"),
                KeyModifiers {
                    control: true,
                    ..KeyModifiers::default()
                }
            ),
            vec![3]
        );
        assert_eq!(
            terminal.encode_key("up", None, KeyModifiers::default()),
            b"\x1b[A"
        );
    }

    #[test]
    fn bracketed_paste_strips_embedded_terminator() {
        let mut terminal = TerminalEmulator::new(20, 3);
        terminal.write(b"\x1b[?2004h");
        assert_eq!(
            terminal.encode_paste("a\x1b[201~b"),
            b"\x1b[200~ab\x1b[201~"
        );
    }
}
