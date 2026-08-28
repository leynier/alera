use std::cell::RefCell;
use std::ops::Range;
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
const MAX_REFLOW_REPLAY_BYTES: usize = 10 * 1024 * 1024;

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
    suppress_restore_prompt_rows: bool,
    visible_row_map: RefCell<Vec<Option<usize>>>,
}

pub struct TerminalLine {
    pub text: StyledText,
    #[cfg_attr(not(test), allow(dead_code))]
    pub plain_text: String,
    pub highlights: Vec<(Range<usize>, HighlightStyle)>,
    pub cursor_column: Option<usize>,
    pub source_row: Option<usize>,
    shell_marker: bool,
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
    /// A bounded terminal lane can request another resync while the previous
    /// full snapshot is still being replayed. Defer that request until the
    /// current restore reaches the emulator, otherwise large scrollback can
    /// restart the restore loop indefinitely.
    pub output_resync_deferred: bool,
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
    restore_replay_bytes: Option<Vec<u8>>,
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
            suppress_restore_prompt_rows: false,
            visible_row_map: RefCell::new((0..rows.max(2)).map(Some).collect()),
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

        let mut lines = cells
            .into_iter()
            .enumerate()
            .map(|(row_index, row)| {
                let shell_marker = row
                    .iter()
                    .any(|cell| cell.c == '%' && cell.flags.contains(Flags::INVERSE));
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
                    push_terminal_highlight(&mut highlights, start..end, style);
                }
                let styled_text = StyledText::new(SharedString::from(text.clone()))
                    .with_highlights(highlights.clone());
                TerminalLine {
                    text: styled_text,
                    plain_text: text,
                    highlights,
                    cursor_column: cursor
                        .filter(|point| point.line.0 == row_index as i32)
                        .map(|point| point.column.0),
                    source_row: Some(row_index),
                    shell_marker,
                }
            })
            .collect::<Vec<_>>();
        if display_offset == 0 && self.suppress_restore_prompt_rows {
            collapse_stale_shell_prompt_rows(&mut lines);
            remove_zsh_shell_marker(&mut lines);
        }
        *self.visible_row_map.borrow_mut() = lines.iter().map(|line| line.source_row).collect();
        lines
    }

    pub fn source_row_for_rendered_row(&self, row: usize) -> Option<usize> {
        self.visible_row_map.borrow().get(row).copied().flatten()
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
        self.visible_http_link_at_wrapped(point)
            .or_else(|| visible_http_link_at(&text, point))
    }

    /// Resolve visible HTTP links across rows that the terminal wrapped. The
    /// Flutter xterm resolver works on logical lines, while a naive per-row
    /// regex loses a URL exactly at the viewport width.
    fn visible_http_link_at_wrapped(&self, point: TerminalPoint) -> Option<TerminalLink> {
        let content = self.terminal.renderable_content();
        let display_offset = content.display_offset as i32;
        let rows = self.terminal.screen_lines();
        let columns = self.terminal.columns();
        let mut cells = vec![vec![Cell::default(); columns]; rows];
        for indexed in content.display_iter {
            let row = indexed.point.line.0 + display_offset;
            let column = indexed.point.column.0;
            if row >= 0 && (row as usize) < rows && column < columns {
                cells[row as usize][column] = indexed.cell.clone();
            }
        }

        let mut logical_text = String::new();
        let mut spans = Vec::new();
        for (row, cells) in cells.iter().enumerate() {
            for (column, cell) in cells.iter().enumerate() {
                let character = if cell.flags.contains(Flags::HIDDEN) {
                    ' '
                } else {
                    cell.c
                };
                let start = logical_text.len();
                logical_text.push(character);
                spans.push((start, logical_text.len(), row, column));
                if let Some(zerowidth) = cell.zerowidth() {
                    for &character in zerowidth {
                        logical_text.push(character);
                        spans.push((start, logical_text.len(), row, column));
                    }
                }
            }

            let wrapped = cells
                .last()
                .is_some_and(|cell| cell.flags.contains(Flags::WRAPLINE));
            if !wrapped || row + 1 == rows {
                if let Some(link) = visible_http_link_in_spans(&logical_text, &spans, point) {
                    return Some(link);
                }
                logical_text.clear();
                spans.clear();
            }
        }
        None
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

    pub fn clear_restore_prompt_cleanup(&mut self) {
        self.suppress_restore_prompt_rows = false;
    }

    fn mark_restore_prompt_cleanup(&mut self, enabled: bool) {
        self.suppress_restore_prompt_rows = enabled;
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

fn push_terminal_highlight(
    highlights: &mut Vec<(Range<usize>, HighlightStyle)>,
    range: Range<usize>,
    style: HighlightStyle,
) {
    if let Some((previous_range, previous_style)) = highlights.last_mut() {
        if previous_range.end == range.start && *previous_style == style {
            previous_range.end = range.end;
            return;
        }
    }
    highlights.push((range, style));
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

fn visible_http_link_in_spans(
    text: &str,
    spans: &[(usize, usize, usize, usize)],
    point: TerminalPoint,
) -> Option<TerminalLink> {
    static URL_PATTERN: OnceLock<Regex> = OnceLock::new();
    let pattern =
        URL_PATTERN.get_or_init(|| Regex::new(r"(?i)https?://[^\s]+").expect("valid URL regex"));
    for matched in pattern.find_iter(text) {
        let end = trim_visible_url_end(text, matched.start(), matched.end());
        if end <= matched.start() {
            continue;
        }
        let matching_spans = spans
            .iter()
            .filter(|(start, _, _, _)| *start >= matched.start() && *start < end);
        let matching_spans = matching_spans.collect::<Vec<_>>();
        if !matching_spans
            .iter()
            .any(|(_, _, row, column)| *row == point.row && *column == point.column)
        {
            continue;
        }
        let row_spans = matching_spans
            .iter()
            .filter(|(_, _, row, _)| *row == point.row)
            .collect::<Vec<_>>();
        let start_column = row_spans.iter().map(|(_, _, _, column)| *column).min()?;
        let end_column = row_spans.iter().map(|(_, _, _, column)| column + 1).max()?;
        let uri = &text[matched.start()..end];
        if !supports_web_uri(uri) {
            continue;
        }
        return Some(TerminalLink {
            uri: uri.to_owned(),
            row: point.row,
            start_column,
            end_column,
        });
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

fn trim_restore_before_last_scrollback_clear(bytes: Vec<u8>) -> Vec<u8> {
    const ERASE_SAVED_LINES: &[u8] = b"\x1b[3J";
    let Some(index) = bytes
        .windows(ERASE_SAVED_LINES.len())
        .rposition(|window| window == ERASE_SAVED_LINES)
    else {
        return bytes;
    };
    bytes[index..].to_vec()
}

fn append_reflow_replay_bytes(replay: &mut Vec<u8>, bytes: &[u8]) -> bool {
    if replay.len().saturating_add(bytes.len()) > MAX_REFLOW_REPLAY_BYTES {
        return false;
    }
    const ERASE_SAVED_LINES: &[u8] = b"\x1b[3J";
    let previous_len = replay.len();
    replay.extend_from_slice(bytes);
    // The existing prefix was already trimmed to its last erase. Only the
    // appended bytes and the short sequence boundary can contain a newer one.
    let scan_start = previous_len.saturating_sub(ERASE_SAVED_LINES.len() - 1);
    if let Some(relative_index) = replay[scan_start..]
        .windows(ERASE_SAVED_LINES.len())
        .rposition(|window| window == ERASE_SAVED_LINES)
    {
        let index = scan_start + relative_index;
        if index > 0 {
            replay.drain(..index);
        }
    }
    true
}

/// Remove duplicate shell-integration prompt redraws from a restored
/// scrollback snapshot.
///
/// zsh emits a `\r\r` + cursor-up sequence around OSC 133 prompt markers when
/// the PTY is resized. A host snapshot can contain redraws produced at several
/// historical widths, so replaying those bytes at the client's current width
/// can leave every old prompt wrapped into visible rows. A contiguous redraw
/// burst keeps only its latest prompt block; command output between bursts
/// remains untouched.
#[cfg(test)]
fn normalize_restore_prompt_redraws(bytes: Vec<u8>) -> Vec<u8> {
    const PROMPT_START: &[u8] = b"\x1b]133;A\x07";
    const PROMPT_END: &[u8] = b"\x1b]133;B\x07";
    if bytes.len() < PROMPT_START.len() + PROMPT_END.len() {
        return bytes;
    }

    let mut normalized = Vec::with_capacity(bytes.len());
    let mut cursor = 0;
    let mut pending_redraw = None::<Vec<u8>>;
    while let Some(start_offset) = find_subslice(&bytes[cursor..], PROMPT_START) {
        let prompt_start = cursor + start_offset;
        let content_start = prompt_start + PROMPT_START.len();
        let Some(end_offset) = find_subslice(&bytes[content_start..], PROMPT_END) else {
            break;
        };
        let prompt_end = content_start + end_offset;
        let block_end = prompt_end + PROMPT_END.len();
        let block_prefix = &bytes[cursor..prompt_start];
        let is_redraw = find_subslice(block_prefix, b"\r\r").is_some()
            && strip_terminal_control_bytes(block_prefix).is_empty();
        if is_redraw {
            append_restore_clear_sequences(block_prefix, &mut normalized);
            // Keep only the latest redraw in a contiguous resize burst. The
            // historical cursor-up count belongs to another viewport width,
            // so canonicalize it to repaint the current row from column zero.
            let mut redraw = b"\r\x1b[2K".to_vec();
            redraw.extend_from_slice(&bytes[prompt_start..block_end]);
            let redraw_visible_len = strip_terminal_control_bytes(&redraw).len();
            let replace_pending = pending_redraw.as_ref().is_none_or(|pending| {
                redraw_visible_len >= strip_terminal_control_bytes(pending).len()
            });
            if replace_pending {
                pending_redraw = Some(redraw);
            }
        } else {
            if let Some(redraw) = pending_redraw.take() {
                normalized.extend_from_slice(&redraw);
            }
            normalized.extend_from_slice(&bytes[cursor..block_end]);
        }
        cursor = block_end;
    }
    if let Some(redraw) = pending_redraw {
        normalized.extend_from_slice(&redraw);
    }
    normalized.extend_from_slice(&bytes[cursor..]);
    normalized
}

#[cfg(test)]
fn append_restore_clear_sequences(bytes: &[u8], output: &mut Vec<u8>) {
    for sequence in [b"\x1b[3J".as_slice(), b"\x1b[H", b"\x1b[2J"] {
        if find_subslice(bytes, sequence).is_some() {
            output.extend_from_slice(sequence);
        }
    }
}

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

#[cfg(test)]
fn strip_terminal_control_bytes(bytes: &[u8]) -> Vec<u8> {
    let mut visible = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == 0x1b {
            index += 1;
            if index >= bytes.len() {
                break;
            }
            match bytes[index] {
                b']' => {
                    index += 1;
                    while index < bytes.len() {
                        let current = bytes[index];
                        index += 1;
                        if current == 0x07 {
                            break;
                        }
                        if current == 0x1b && bytes.get(index) == Some(&b'\\') {
                            index += 1;
                            break;
                        }
                    }
                }
                b'[' => {
                    index += 1;
                    while index < bytes.len() {
                        let current = bytes[index];
                        index += 1;
                        if (0x40..=0x7e).contains(&current) {
                            break;
                        }
                    }
                }
                _ => index += 1,
            }
            continue;
        }
        index += 1;
        if byte >= 0x20 {
            visible.push(byte);
        }
    }
    visible
}

fn restore_contains_shell_resize_redraw(bytes: &[u8]) -> bool {
    find_subslice(bytes, b"\r\r").is_some() && find_subslice(bytes, b"\x1b]133;A\x07").is_some()
}

fn collapse_stale_shell_prompt_rows(lines: &mut Vec<TerminalLine>) {
    // Prefer the latest prompt prefix as the anchor. The arrow can occupy a
    // wrapped row after it, and anchoring on that bare row would blank the
    // current prompt together with the stale rows before it.
    let last_bare_prompt = lines
        .iter()
        .rposition(|line| is_bare_shell_prompt(&line.plain_text));
    let Some(final_prompt_start) = last_bare_prompt
        .and_then(|index| {
            lines[..=index]
                .iter()
                .rposition(|line| is_shell_prompt_prefix(&line.plain_text))
        })
        .or_else(|| {
            lines
                .iter()
                .rposition(|line| is_shell_prompt_prefix(&line.plain_text))
        })
        .or(last_bare_prompt)
    else {
        return;
    };
    let stale_count = lines[..final_prompt_start]
        .iter()
        .filter(|line| {
            is_shell_prompt_prefix(&line.plain_text) || is_bare_shell_prompt(&line.plain_text)
        })
        .count();
    // A resize snapshot can contain a single bare `%` from zsh's redraw
    // marker before the final prompt. Once the resize signature has opted us
    // into this cleanup pass, that one row is stale as well; requiring two
    // prompt rows leaves the exact one-row artifact visible in short
    // snapshots.
    if stale_count == 0 {
        return;
    }

    let mut remove = vec![false; lines.len()];
    let mut in_stale_prompt = false;
    for (index, line) in lines.iter().enumerate().take(final_prompt_start) {
        let prefix = is_shell_prompt_prefix(&line.plain_text);
        let bare = is_bare_shell_prompt(&line.plain_text);
        let marker = line.shell_marker || is_stale_shell_marker(&line.plain_text);
        let command_line = is_shell_prompt_command_line(&line.plain_text);
        if command_line && !bare {
            // A wrapped prompt prefix may be followed by a line containing
            // the prompt symbol and the user's command. That line terminates
            // the stale prompt span; command text and subsequent output must
            // remain visible.
            in_stale_prompt = false;
        } else if prefix {
            in_stale_prompt = true;
        }
        if in_stale_prompt || bare || marker {
            remove[index] = true;
        }
        if bare {
            in_stale_prompt = false;
        }
    }
    let removed = remove.iter().filter(|remove| **remove).count();
    if removed == 0 {
        return;
    }
    let width = lines
        .first()
        .map(|line| line.plain_text.chars().count())
        .unwrap_or_default();
    let mut retained = lines
        .drain(..)
        .enumerate()
        .filter_map(|(index, line)| (!remove[index]).then_some(line))
        .collect::<Vec<_>>();
    retained.extend((0..removed).map(|_| {
        let plain_text = " ".repeat(width);
        TerminalLine {
            text: StyledText::new(SharedString::from(plain_text.clone())),
            plain_text,
            highlights: Vec::new(),
            cursor_column: None,
            source_row: None,
            shell_marker: false,
        }
    }));
    *lines = retained;
}

fn is_shell_prompt_command_line(text: &str) -> bool {
    let trimmed = text.trim_start();
    trimmed.contains('❯') || trimmed.starts_with("> ") || trimmed.starts_with("% ")
}

fn is_stale_shell_marker(text: &str) -> bool {
    let trimmed = text.trim();
    let Some(rest) = trimmed.strip_prefix('%') else {
        return false;
    };
    // zsh's shell-integration redraw paints a reverse-video `%` and then
    // clears/repaints the row. A partially replayed snapshot can leave one
    // trailing character from the prompt on that row, so accept an empty or
    // one-character remainder while leaving real command output untouched.
    rest.trim().chars().count() <= 1
}

fn remove_zsh_shell_marker(lines: &mut [TerminalLine]) {
    for line in lines {
        let trimmed = line.plain_text.trim_end();
        if !trimmed.ends_with('%') {
            continue;
        }
        let without_marker = trimmed[..trimmed.len() - '%'.len_utf8()].trim_end();
        if !without_marker.ends_with('❯') {
            continue;
        }
        let mut text = without_marker.to_owned();
        text.push(' ');
        line.plain_text = text.clone();
        line.text = StyledText::new(SharedString::from(text));
        line.highlights.clear();
        line.cursor_column = None;
    }
}

fn is_bare_shell_prompt(text: &str) -> bool {
    matches!(text.trim(), "❯" | ">" | "%")
}

fn is_shell_prompt_prefix(text: &str) -> bool {
    let text = text.trim();
    (text.contains(" on ") || text.contains(" in "))
        && (text.contains("via ") || text.contains("leynierdev@"))
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
            output_resync_deferred: false,
            operation: Some(TerminalSessionOperation::Starting),
            // The request is started after the first real terminal bounds are
            // painted. Keeping this unset distinguishes a measured attach in
            // flight from the short period where the surface is still laying
            // out and prevents a provisional 100-column emulator from
            // reinterpreting the host snapshot.
            operation_started_at: None,
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
            restore_replay_bytes: None,
        }
    }

    /// Queue a host snapshot for incremental replay so a large scrollback does
    /// not block the first useful frame of a restored terminal.
    pub fn begin_restore(&mut self, bytes: Vec<u8>) -> u64 {
        // CSI 3J invalidates every prior scrollback row. Starting replay at
        // its last occurrence prevents later resize redraws from resurrecting
        // bytes that both xterm and the shell have already discarded.
        let bytes = trim_restore_before_last_scrollback_clear(bytes);
        // From that semantic reset onward, preserve the exact VT stream. The
        // prompt renderer may emit visible segments outside OSC 133, so
        // coalescing prompt blocks can truncate the prompt itself.
        self.emulator
            .mark_restore_prompt_cleanup(restore_contains_shell_resize_redraw(&bytes));
        self.restore_generation = self.restore_generation.wrapping_add(1);
        self.restore_total_bytes = bytes.len();
        self.restore_offset = 0;
        self.restore_output_pending.clear();
        self.restore_replay_bytes = Some(bytes.clone());
        self.restore_pending = (!bytes.is_empty()).then_some(bytes);
        self.restore_generation
    }

    /// Preserve live PTY bytes until the snapshot has been replayed. The host
    /// can send output immediately after an attach or full resync response;
    /// applying it before the batched snapshot would reorder the terminal.
    pub fn write_output(&mut self, bytes: &[u8]) {
        if let Some(mut replay) = self.restore_replay_bytes.take() {
            if append_reflow_replay_bytes(&mut replay, bytes) {
                self.restore_replay_bytes = Some(replay);
            }
        }
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

    pub fn rebuild_for_dimensions(&mut self, columns: usize, rows: usize) -> Option<u64> {
        let bytes = self.restore_replay_bytes.clone()?;
        self.columns = columns.max(2);
        self.rows = rows.max(2);
        self.emulator = TerminalEmulator::new(self.columns, self.rows);
        Some(self.begin_restore(bytes))
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
    fn adjacent_terminal_cells_with_the_same_style_share_one_highlight() {
        let style = HighlightStyle {
            color: Some(gpui::rgb(0xffffff).into()),
            ..HighlightStyle::default()
        };
        let mut highlights = Vec::new();
        push_terminal_highlight(&mut highlights, 0..1, style);
        push_terminal_highlight(&mut highlights, 1..2, style);
        push_terminal_highlight(&mut highlights, 2..3, HighlightStyle::default());
        assert_eq!(highlights.len(), 2);
        assert_eq!(highlights[0].0, 0..2);
        assert_eq!(highlights[1].0, 2..3);
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
    fn reflow_replay_append_preserves_output_without_rescanning_the_prefix() {
        let mut replay = b"existing output".to_vec();
        assert!(append_reflow_replay_bytes(&mut replay, b" and new output"));
        assert_eq!(replay, b"existing output and new output");
    }

    #[test]
    fn reflow_replay_append_detects_a_scrollback_clear_across_chunks() {
        let mut replay = b"stale output\x1b[".to_vec();
        assert!(append_reflow_replay_bytes(&mut replay, b"3Jfresh output"));
        assert_eq!(replay, b"\x1b[3Jfresh output");
    }

    #[test]
    fn reflow_replay_append_stops_retaining_an_oversized_stream() {
        let mut replay = vec![b'x'; MAX_REFLOW_REPLAY_BYTES];
        assert!(!append_reflow_replay_bytes(&mut replay, b"y"));
        assert_eq!(replay.len(), MAX_REFLOW_REPLAY_BYTES);
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

        let visible = session
            .emulator
            .visible_lines("default")
            .into_iter()
            .map(|line| line.plain_text)
            .collect::<String>();
        assert!(visible.contains("snapshot"));
        assert!(visible.contains("live"));
        assert!(visible.find("snapshot") < visible.find("live"));
    }

    #[test]
    fn restore_coalesces_duplicate_shell_prompt_redraws() {
        let prompt = b"\x1b]133;A\x07prompt\x1b]133;B\x07";
        let redraw = b"\x1b[K\x1b[?2004h\r\r\x1b[A\x1b[0m\x1b[J\x1b]133;A\x07prompt\x1b]133;B\x07";
        let mut bytes = prompt.to_vec();
        bytes.extend_from_slice(redraw);
        bytes.extend_from_slice(redraw);

        let mut session = TerminalSession::new("restore-redraw".to_owned());
        session.begin_restore(bytes);
        while session.restore_next_chunk(1024) {}

        let visible_prompt_rows = session
            .emulator
            .visible_lines("default")
            .into_iter()
            .filter(|line| line.plain_text.contains("prompt"))
            .count();
        assert_eq!(visible_prompt_rows, 1);
    }

    #[test]
    fn restore_cleanup_removes_zsh_reverse_marker_after_prompt() {
        let mut lines = vec![TerminalLine {
            text: StyledText::new(SharedString::from("❯ %")),
            plain_text: "❯ %".to_owned(),
            highlights: Vec::new(),
            cursor_column: Some(2),
            source_row: Some(0),
            shell_marker: false,
        }];

        remove_zsh_shell_marker(&mut lines);

        assert_eq!(lines[0].plain_text, "❯ ");
        assert_eq!(lines[0].cursor_column, None);
    }

    #[test]
    fn restore_cleanup_recognizes_partial_zsh_marker_row() {
        assert!(is_stale_shell_marker(
            "%                                                                                 l"
        ));
        assert!(is_stale_shell_marker("%"));
        assert!(!is_stale_shell_marker("% real command output"));
    }

    #[test]
    fn restore_cleanup_preserves_command_and_output_after_wrapped_prompt() {
        let line = |text: &str| TerminalLine {
            text: StyledText::new(SharedString::from(text.to_owned())),
            plain_text: text.to_owned(),
            highlights: Vec::new(),
            cursor_column: None,
            source_row: None,
            shell_marker: false,
        };
        let mut lines = vec![
            line("leynier in workspace on main via rust"),
            line("x"),
            line("❯ printf '%s\\n' 'https://alera-parity.invalid'"),
            line("https://alera-parity.invalid"),
            line("%"),
            line("leynier in workspace on main via rust"),
            line("x"),
            line("❯"),
        ];

        collapse_stale_shell_prompt_rows(&mut lines);

        assert_eq!(lines.len(), 8);
        assert!(lines[0].plain_text.contains("printf"));
        assert_eq!(lines[1].plain_text, "https://alera-parity.invalid");
        assert!(lines[2].plain_text.contains("leynier in workspace"));
        assert_eq!(lines[4].plain_text, "❯");
        assert!(lines[5..]
            .iter()
            .all(|line| line.plain_text.trim().is_empty()));
    }

    #[test]
    fn restore_keeps_a_prompt_that_changed_between_redraws() {
        let first = b"\x1b]133;A\x07first\x1b]133;B\x07";
        let second = b"\r\r\x1b[A\x1b]133;A\x07second\x1b]133;B\x07";
        let mut bytes = first.to_vec();
        bytes.extend_from_slice(second);

        let normalized = normalize_restore_prompt_redraws(bytes);

        assert!(normalized
            .windows(first.len())
            .any(|window| window == first));
        assert!(normalized
            .windows(b"\x1b]133;A\x07second\x1b]133;B\x07".len())
            .any(|window| window == b"\x1b]133;A\x07second\x1b]133;B\x07"));
        assert!(!normalized
            .windows(b"\r\r\x1b[A".len())
            .any(|window| window == b"\r\r\x1b[A"));
    }

    #[test]
    fn restore_normalization_keeps_clear_before_resize_redraws() {
        let initial_prompt = b"old-output\r\n\x1b]133;A\x07prompt\x1b]133;B\x07";
        let clear_and_redraw = b"\x1b[3J\x1b[H\x1b[2J\r\r\x1b[A\x1b]133;A\x07prompt\x1b]133;B\x07";
        let latest_redraw = b"\r\r\x1b[A\x1b]133;A\x07prompt\x1b]133;B\x07after-clear";
        let mut bytes = initial_prompt.to_vec();
        bytes.extend_from_slice(clear_and_redraw);
        bytes.extend_from_slice(latest_redraw);

        let normalized = normalize_restore_prompt_redraws(bytes);
        let mut terminal = TerminalEmulator::new(40, 5);
        terminal.write(&normalized);
        let visible = terminal.visible_text();

        assert!(normalized.windows(4).any(|window| window == b"\x1b[3J"));
        assert!(visible.contains("after-clear"));
        assert!(!visible.contains("old-output"));
    }

    #[test]
    fn terminal_session_restore_replays_clear_stream_exactly() {
        let bytes = b"old-output\r\n\x1b]133;A\x07prompt\x1b]133;B\x07\x1b[3J\x1b[H\x1b[2J\r\r\x1b[A\x1b]133;A\x07prompt\x1b]133;B\x07\r\r\x1b[A\x1b]133;A\x07prompt\x1b]133;B\x07\xe2\x9d\xaf printf '%s\\n' 'https://alera-parity.invalid'\r\nhttps://alera-parity.invalid";
        let mut session = TerminalSession::new("restore-clear".to_owned());
        session.columns = 80;
        session.rows = 8;
        session.emulator = TerminalEmulator::new(session.columns, session.rows);
        session.begin_restore(bytes.to_vec());
        while session.restore_next_chunk(32) {}
        let visible = session
            .emulator
            .visible_lines("default")
            .into_iter()
            .map(|line| line.plain_text)
            .collect::<String>();

        assert!(visible.contains("alera-parity.invalid"));
        assert!(!visible.contains("old-output"));
    }

    #[test]
    fn terminal_session_rebuilds_restore_at_final_dimensions() {
        let bytes = b"old-output\r\n\x1b[3J\x1b[H\x1b[2Jfresh-restore";
        let mut session = TerminalSession::new("resize-restore".to_owned());
        session.columns = 12;
        session.rows = 4;
        session.emulator = TerminalEmulator::new(session.columns, session.rows);
        session.begin_restore(bytes.to_vec());
        while session.restore_next_chunk(8) {}
        session.write_output(b" live-output");

        let generation = session
            .rebuild_for_dimensions(40, 8)
            .expect("restore bytes should remain available for final resize");
        assert_eq!(session.restore_generation(), generation);
        while session.restore_next_chunk(8) {}

        let visible = session.emulator.visible_text();
        assert!(visible.contains("fresh-restore live-output"));
        assert!(!visible.contains("old-output"));
        assert_eq!((session.columns, session.rows), (40, 8));
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
    fn erase_saved_lines_removes_pre_clear_scrollback() {
        let mut terminal = TerminalEmulator::new(20, 4);
        terminal.write(b"old-one\r\nold-two\r\nold-three\r\nold-four\r\nold-five");
        terminal.write(b"\x1b[H\x1b[2J\x1b[3Jafter-clear");

        let visible = terminal
            .visible_lines("default")
            .into_iter()
            .map(|line| line.plain_text)
            .collect::<String>();
        assert!(visible.contains("after-clear"));
        assert!(!visible.contains("old-"));

        terminal.scroll_display(100);
        let scrolled = terminal
            .visible_lines("default")
            .into_iter()
            .map(|line| line.plain_text)
            .collect::<String>();
        assert!(!scrolled.contains("old-"));
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
    fn visible_http_links_continue_across_wrapped_rows() {
        let mut terminal = TerminalEmulator::new(12, 3);
        terminal.write(b"https://example.com");

        let first_row = terminal
            .link_at(TerminalPoint { row: 0, column: 5 })
            .expect("wrapped link on first row");
        let second_row = terminal
            .link_at(TerminalPoint { row: 1, column: 2 })
            .expect("wrapped link on second row");

        assert_eq!(first_row.uri, "https://example.com");
        assert_eq!(second_row.uri, first_row.uri);
        assert_eq!(second_row.start_column, 0);
        assert_eq!(second_row.end_column, 7);
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
