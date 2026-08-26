use std::sync::OnceLock;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::{Dimensions, Scroll};
use alacritty_terminal::index::{Column, Point as GridPoint, Side};
use alacritty_terminal::selection::{Selection, SelectionType};
use alacritty_terminal::term::cell::{Cell, Flags};
use alacritty_terminal::term::test::TermSize;
use alacritty_terminal::term::{viewport_to_point, Config, Term, TermMode};
use alacritty_terminal::vte::ansi;
use gpui::{FontStyle, FontWeight, HighlightStyle, SharedString, StyledText};
use regex::Regex;

use crate::{terminal_palette::resolve_color, terminal_theme_catalog::terminal_theme_palette};

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
    selection_anchor: Option<GridPoint>,
    selection_kind: TerminalSelectionKind,
}

pub struct TerminalLine {
    pub text: StyledText,
    #[cfg_attr(not(test), allow(dead_code))]
    pub plain_text: String,
    pub cursor_column: Option<usize>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TerminalLink {
    pub uri: String,
    pub row: usize,
    pub start_column: usize,
    pub end_column: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TerminalPoint {
    pub row: usize,
    pub column: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalSelectionKind {
    Simple,
    Semantic,
    Lines,
}

const DEFAULT_WORD_SEPARATORS: &[char] = &['\0', ' ', '.', ':', '-', '\\', '"', '*', '+', '/'];

pub struct TerminalSession {
    pub session_id: String,
    pub attaching: bool,
    /// Prevent duplicate resume requests while the host is sending a full
    /// snapshot or a delta on the terminal lane.
    pub output_resync_in_flight: bool,
    pub operation: Option<TerminalSessionOperation>,
    pub operation_started_at: Option<Instant>,
    pub running: bool,
    pub error: Option<String>,
    pub columns: usize,
    pub rows: usize,
    pub emulator: TerminalEmulator,
    restore_generation: u64,
    restore_pending: Option<Vec<u8>>,
    restore_offset: usize,
    restore_total_bytes: usize,
    restore_output_pending: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TerminalSessionOperation {
    Starting,
    Reconnecting,
    Restarting,
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
            selection_anchor: None,
            selection_kind: TerminalSelectionKind::Simple,
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
            "space" => Some(b" ".as_slice()),
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

    pub fn visible_lines(&self, theme_name: &str) -> Vec<TerminalLine> {
        let palette = terminal_theme_palette(theme_name);
        let rows = self.terminal.screen_lines();
        let columns = self.terminal.columns();
        let mut cells = vec![vec![Cell::default(); columns]; rows];
        let content = self.terminal.renderable_content();
        let display_offset = content.display_offset as i32;
        let cursor = (display_offset == 0 && content.cursor.shape != ansi::CursorShape::Hidden)
            .then_some(content.cursor.point);
        for indexed in content.display_iter {
            let row = indexed.point.line.0 + display_offset;
            if row < 0 || row as usize >= rows {
                continue;
            }
            let column = indexed.point.column.0;
            if column < columns {
                cells[row as usize][column] = indexed.cell.clone();
            }
        }

        cells
            .into_iter()
            .enumerate()
            .map(|(row_index, row)| {
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
                        color: resolve_color(cell.fg, palette),
                        background_color: (cell.bg
                            != ansi::Color::Named(ansi::NamedColor::Background))
                        .then(|| resolve_color(cell.bg, palette))
                        .flatten(),
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
                    text: StyledText::new(SharedString::from(text.clone()))
                        .with_highlights(highlights),
                    plain_text: text,
                    cursor_column: cursor
                        .filter(|point| point.line.0 == row_index as i32)
                        .map(|point| point.column.0),
                }
            })
            .collect()
    }

    pub fn link_at(&self, point: TerminalPoint) -> Option<TerminalLink> {
        let content = self.terminal.renderable_content();
        let display_offset = content.display_offset as i32;
        let mut row_cells = content
            .display_iter
            .filter_map(|indexed| {
                let row = indexed.point.line.0 + display_offset;
                (row == point.row as i32).then_some((indexed.point.column.0, indexed.cell.clone()))
            })
            .collect::<Vec<_>>();
        row_cells.sort_by_key(|(column, _)| *column);

        if let Some((_, cell)) = row_cells.iter().find(|(column, _)| *column == point.column) {
            if let Some(hyperlink) = cell.hyperlink() {
                let uri = hyperlink.uri();
                if supports_web_uri(uri) {
                    let start_column = row_cells
                        .iter()
                        .filter(|(_, candidate)| {
                            candidate.hyperlink().is_some_and(|link| link.uri() == uri)
                        })
                        .map(|(column, _)| *column)
                        .min()?;
                    let end_column = row_cells
                        .iter()
                        .filter(|(_, candidate)| {
                            candidate.hyperlink().is_some_and(|link| link.uri() == uri)
                        })
                        .map(|(column, cell)| {
                            column + usize::from(!cell.flags.contains(Flags::WIDE_CHAR_SPACER))
                        })
                        .max()?;
                    return Some(TerminalLink {
                        uri: uri.to_owned(),
                        row: point.row,
                        start_column,
                        end_column,
                    });
                }
            }
        }

        let columns = self.terminal.columns();
        let mut text = vec![' '; columns];
        for (column, cell) in row_cells {
            if column < columns && !cell.flags.contains(Flags::WIDE_CHAR_SPACER) {
                text[column] = if cell.flags.contains(Flags::HIDDEN) {
                    ' '
                } else {
                    cell.c
                };
            }
        }
        let text = text.into_iter().collect::<String>();
        visible_http_link_at(&text, point)
    }

    pub fn begin_selection(
        &mut self,
        point: TerminalPoint,
        kind: TerminalSelectionKind,
        configured_separators: Option<&str>,
    ) {
        if kind == TerminalSelectionKind::Semantic {
            let separators = configured_separators
                .filter(|value| !value.trim().is_empty())
                .map(str::to_owned)
                .unwrap_or_else(|| DEFAULT_WORD_SEPARATORS.iter().collect());
            self.terminal.set_options(Config {
                scrolling_history: SCROLLBACK_LINES,
                semantic_escape_chars: separators,
                ..Config::default()
            });
        }
        let point = self.buffer_point(point);
        let selection_type = match kind {
            TerminalSelectionKind::Simple => SelectionType::Simple,
            TerminalSelectionKind::Semantic => SelectionType::Semantic,
            TerminalSelectionKind::Lines => SelectionType::Lines,
        };
        self.selection_anchor = Some(point);
        self.selection_kind = kind;
        self.terminal.selection = Some(Selection::new(selection_type, point, Side::Left));
    }

    pub fn update_selection(&mut self, point: TerminalPoint) {
        let point = self.buffer_point(point);
        let Some(anchor) = self.selection_anchor else {
            return;
        };
        let selection_type = match self.selection_kind {
            TerminalSelectionKind::Simple => SelectionType::Simple,
            TerminalSelectionKind::Semantic => SelectionType::Semantic,
            TerminalSelectionKind::Lines => SelectionType::Lines,
        };
        let (anchor_side, head_side) = if point < anchor {
            (Side::Right, Side::Left)
        } else {
            (Side::Left, Side::Right)
        };
        let mut selection = Selection::new(selection_type, anchor, anchor_side);
        selection.update(point, head_side);
        self.terminal.selection = Some(selection);
    }

    pub fn clear_selection(&mut self) {
        self.terminal.selection = None;
        self.selection_anchor = None;
    }

    pub fn selected_text(&self) -> Option<String> {
        self.terminal
            .selection_to_string()
            .map(|text| text.strip_suffix('\n').unwrap_or(&text).to_owned())
    }

    pub fn selection_range_for_viewport_row(&self, row: usize) -> Option<(usize, usize)> {
        let content = self.terminal.renderable_content();
        let selection = content.selection?;
        let point = |column| {
            GridPoint::new(
                alacritty_terminal::index::Line(row as i32 - content.display_offset as i32),
                Column(column),
            )
        };
        let start =
            (0..self.terminal.columns()).find(|column| selection.contains(point(*column)))?;
        let end = (start + 1..self.terminal.columns())
            .take_while(|column| selection.contains(point(*column)))
            .last()
            .map(|column| column + 1)
            .unwrap_or(start + 1);
        Some((start, end))
    }

    fn buffer_point(&self, point: TerminalPoint) -> GridPoint {
        viewport_to_point(
            self.terminal.grid().display_offset(),
            GridPoint::new(point.row, Column(point.column)),
        )
    }

    pub fn scroll_metrics(&self) -> (usize, usize, usize) {
        let history = self.terminal.grid().history_size();
        (
            self.terminal.renderable_content().display_offset,
            history,
            self.terminal.screen_lines(),
        )
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

fn visible_http_link_at(text: &str, point: TerminalPoint) -> Option<TerminalLink> {
    static URL_PATTERN: OnceLock<Regex> = OnceLock::new();
    let pattern =
        URL_PATTERN.get_or_init(|| Regex::new(r"(?i)https?://[^\s]+").expect("valid URL regex"));
    for matched in pattern.find_iter(text) {
        let mut end = trim_visible_url_end(text, matched.start(), matched.end());
        if end <= matched.start() {
            continue;
        }
        let start_column = text[..matched.start()].chars().count();
        let mut end_column = text[..end].chars().count();
        while end > matched.start() && end_column <= start_column {
            end -= 1;
            end_column = text[..end].chars().count();
        }
        if point.column < start_column || point.column >= end_column {
            continue;
        }
        let uri = &text[matched.start()..end];
        if supports_web_uri(uri) {
            return Some(TerminalLink {
                uri: uri.to_owned(),
                row: point.row,
                start_column,
                end_column,
            });
        }
    }
    None
}

fn supports_web_uri(uri: &str) -> bool {
    let authority = uri
        .strip_prefix("https://")
        .or_else(|| uri.strip_prefix("http://"))
        .or_else(|| uri.strip_prefix("HTTPS://"))
        .or_else(|| uri.strip_prefix("HTTP://"));
    authority.is_some_and(|authority| {
        authority
            .split(['/', '?', '#'])
            .next()
            .is_some_and(|host| !host.trim().is_empty())
    })
}

fn trim_visible_url_end(text: &str, start: usize, mut end: usize) -> usize {
    while end > start {
        let Some(character) = text[..end].chars().next_back() else {
            break;
        };
        if matches!(character, '.' | ',' | ';' | ':' | '!' | '?' | '"' | '\'') {
            end -= character.len_utf8();
            continue;
        }
        let unbalanced = match character {
            ')' => {
                count_character(&text[start..end], '(') < count_character(&text[start..end], ')')
            }
            ']' => {
                count_character(&text[start..end], '[') < count_character(&text[start..end], ']')
            }
            '}' => {
                count_character(&text[start..end], '{') < count_character(&text[start..end], '}')
            }
            _ => false,
        };
        if !unbalanced {
            break;
        }
        end -= character.len_utf8();
    }
    end
}

fn count_character(text: &str, expected: char) -> usize {
    text.chars()
        .filter(|character| *character == expected)
        .count()
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
            output_resync_in_flight: false,
            operation: Some(TerminalSessionOperation::Starting),
            operation_started_at: Some(Instant::now()),
            running: true,
            error: None,
            columns: DEFAULT_COLUMNS,
            rows: DEFAULT_ROWS,
            emulator: TerminalEmulator::default(),
            restore_generation: 0,
            restore_pending: None,
            restore_offset: 0,
            restore_total_bytes: 0,
            restore_output_pending: Vec::new(),
        }
    }

    /// Queue a host snapshot for incremental replay so a large scrollback does
    /// not block the first useful frame of a restored terminal.
    pub fn begin_restore(&mut self, bytes: Vec<u8>) -> u64 {
        self.restore_generation = self.restore_generation.wrapping_add(1);
        self.restore_total_bytes = bytes.len();
        self.restore_offset = 0;
        self.restore_output_pending.clear();
        self.restore_pending = (!bytes.is_empty()).then_some(bytes);
        self.restore_generation
    }

    /// Preserve live PTY bytes until the snapshot has been replayed. The host
    /// can send output immediately after an attach or full resync response;
    /// applying it before the batched snapshot would reorder the terminal.
    pub fn write_output(&mut self, bytes: &[u8]) {
        if self.restore_pending.is_some() {
            self.restore_output_pending.extend_from_slice(bytes);
        } else {
            self.emulator.write(bytes);
        }
    }

    pub fn restore_generation(&self) -> u64 {
        self.restore_generation
    }

    pub fn restore_progress(&self) -> Option<(usize, usize)> {
        (self.restore_pending.is_some() && self.restore_total_bytes > 0)
            .then_some((self.restore_offset, self.restore_total_bytes))
    }

    pub fn restore_in_progress(&self) -> bool {
        self.restore_pending.is_some()
    }

    /// Apply one bounded batch. The caller schedules another batch on the
    /// next frame while this returns `true`.
    pub fn restore_next_chunk(&mut self, max_bytes: usize) -> bool {
        let Some(bytes) = self.restore_pending.as_ref() else {
            return false;
        };
        let chunk_size = max_bytes.max(1);
        let end = (self.restore_offset + chunk_size).min(bytes.len());
        self.emulator.write(&bytes[self.restore_offset..end]);
        self.restore_offset = end;
        if self.restore_offset >= bytes.len() {
            self.restore_pending = None;
            self.restore_offset = 0;
            self.restore_total_bytes = 0;
            if !self.restore_output_pending.is_empty() {
                let queued = std::mem::take(&mut self.restore_output_pending);
                self.emulator.write(&queued);
            }
            false
        } else {
            true
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
        let lines = terminal.visible_lines("Alera Dark");
        assert_eq!(lines.len(), 3);
        assert!(terminal.visible_text().contains("plain"));
        assert_eq!(lines[1].cursor_column, Some(3));
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
        assert_eq!(
            terminal.encode_key("space", None, KeyModifiers::default()),
            b" "
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

    #[test]
    fn terminal_selection_extracts_visible_text_in_both_directions() {
        let mut terminal = TerminalEmulator::new(20, 3);
        terminal.write(b"hello world\r\nsecond");
        terminal.begin_selection(
            TerminalPoint { row: 0, column: 0 },
            TerminalSelectionKind::Simple,
            None,
        );
        terminal.update_selection(TerminalPoint { row: 0, column: 4 });
        assert_eq!(terminal.selected_text().as_deref(), Some("hello"));
        terminal.begin_selection(
            TerminalPoint { row: 0, column: 4 },
            TerminalSelectionKind::Simple,
            None,
        );
        terminal.update_selection(TerminalPoint { row: 0, column: 0 });
        assert_eq!(terminal.selected_text().as_deref(), Some("hello"));
    }

    #[test]
    fn terminal_session_replays_restore_in_bounded_batches() {
        let mut session = TerminalSession::new("restore".to_owned());
        let generation = session.begin_restore(b"alpha beta".to_vec());
        assert_eq!(session.restore_generation(), generation);
        assert_eq!(session.restore_progress(), Some((0, 10)));
        assert!(session.restore_next_chunk(5));
        assert_eq!(session.restore_progress(), Some((5, 10)));
        assert!(!session.restore_next_chunk(5));
        assert_eq!(session.restore_progress(), None);
        assert!(session.emulator.visible_text().contains("alpha"));
    }

    #[test]
    fn terminal_output_waits_until_restore_snapshot_is_replayed() {
        let mut session = TerminalSession::new("restore-order".to_owned());
        session.begin_restore(b"snapshot".to_vec());
        session.write_output(b" live");

        assert!(!session.emulator.visible_text().contains("live"));
        assert!(!session.restore_next_chunk(1024));

        let visible = session.emulator.visible_text();
        assert!(visible.contains("snapshot"));
        assert!(visible.contains("live"));
        assert!(visible.find("snapshot") < visible.find("live"));
    }

    #[test]
    fn terminal_selection_trims_row_padding_and_selects_words_like_xterm() {
        let mut terminal = TerminalEmulator::new(20, 3);
        terminal.write(b"hello-world\r\nsecond row");
        terminal.begin_selection(
            TerminalPoint { row: 0, column: 0 },
            TerminalSelectionKind::Simple,
            None,
        );
        terminal.update_selection(TerminalPoint { row: 1, column: 5 });
        assert_eq!(
            terminal.selected_text().as_deref(),
            Some("hello-world\nsecond")
        );
        terminal.begin_selection(
            TerminalPoint { row: 0, column: 7 },
            TerminalSelectionKind::Semantic,
            None,
        );
        assert_eq!(terminal.selected_text().as_deref(), Some("world"));
        terminal.begin_selection(
            TerminalPoint { row: 0, column: 7 },
            TerminalSelectionKind::Semantic,
            Some("-"),
        );
        assert_eq!(terminal.selected_text().as_deref(), Some("world"));
        terminal.begin_selection(
            TerminalPoint { row: 1, column: 2 },
            TerminalSelectionKind::Lines,
            None,
        );
        assert_eq!(terminal.selected_text().as_deref(), Some("second row"));
    }

    #[test]
    fn visible_lines_map_negative_scrollback_rows_into_the_viewport() {
        let mut terminal = TerminalEmulator::new(8, 3);
        terminal.write(b"one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix");
        terminal.scroll_display(2);
        let lines = terminal.visible_lines("Alera Dark");
        let text = lines
            .iter()
            .map(|line| line.plain_text.trim_end())
            .collect::<Vec<_>>();
        assert_eq!(text, ["two", "three", "four"]);
        assert!(lines.iter().all(|line| line.cursor_column.is_none()));
    }

    #[test]
    fn redraw_sequence_keeps_prompt_on_one_row() {
        let mut terminal = TerminalEmulator::new(100, 30);
        let prompt =
            b"leynier in leynier-website on main\r\n\x1b[1;32m\xE2\x9D\xAF\x1b[0m \x1b]133;B\x07";
        let redraw = b"\r\r\x1b[A\x1b[A\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]133;A\x07leynier in leynier-website on main\r\n\x1b[1;32m\xE2\x9D\xAF\x1b[0m \x1b]133;B\x07";
        terminal.write(prompt);
        for _ in 0..8 {
            terminal.write(redraw);
        }
        let lines = terminal.visible_lines("default");
        assert_eq!(
            lines
                .iter()
                .filter(|line| line.plain_text.contains("leynier in leynier-website"))
                .count(),
            1
        );
    }

    #[test]
    fn visible_lines_preserve_grid_columns_after_resize() {
        let mut terminal = TerminalEmulator::new(12, 3);
        terminal.write(b"\x1b[5Gright");
        terminal.resize(18, 3);

        let lines = terminal.visible_lines("Alera Dark");

        assert!(lines[0].plain_text.starts_with("    right"));
        assert_eq!(lines[0].plain_text.chars().count(), 18);
    }

    #[test]
    fn selection_keeps_its_buffer_identity_while_the_viewport_moves() {
        let mut terminal = TerminalEmulator::new(8, 3);
        terminal.write(b"one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix");
        terminal.scroll_display(2);
        terminal.begin_selection(
            TerminalPoint { row: 0, column: 0 },
            TerminalSelectionKind::Simple,
            None,
        );
        terminal.update_selection(TerminalPoint { row: 0, column: 2 });

        assert_eq!(terminal.selected_text().as_deref(), Some("two"));
        assert_eq!(terminal.selection_range_for_viewport_row(0), Some((0, 3)));

        terminal.scroll_display(-2);

        assert_eq!(terminal.selected_text().as_deref(), Some("two"));
        assert_eq!(terminal.selection_range_for_viewport_row(0), None);
    }

    #[test]
    fn visible_http_links_trim_sentence_punctuation() {
        let mut terminal = TerminalEmulator::new(80, 3);
        terminal.write(b"Open https://example.com/docs?q=1.");

        let link = terminal
            .link_at(TerminalPoint { row: 0, column: 10 })
            .expect("link");

        assert_eq!(link.uri, "https://example.com/docs?q=1");
        assert_eq!(link.start_column, 5);
        assert_eq!(link.end_column, 33);
    }

    #[test]
    fn osc8_links_take_precedence_over_visible_text() {
        let mut terminal = TerminalEmulator::new(40, 3);
        terminal.write(b"\x1b]8;;https://example.com/target\x1b\\Open Docs\x1b]8;;\x1b\\");

        let link = terminal
            .link_at(TerminalPoint { row: 0, column: 3 })
            .expect("OSC 8 link");

        assert_eq!(link.uri, "https://example.com/target");
        assert_eq!(link.start_column, 0);
        assert_eq!(link.end_column, 9);
    }
}
