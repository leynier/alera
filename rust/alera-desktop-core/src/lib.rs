//! Framework-neutral building blocks shared by the experimental desktop clients.
//!
//! The GPUI client historically owned these modules directly.  They are
//! exposed from this crate first so the Freya client can be introduced in
//! parallel without creating a second runtime protocol or workbench model.

pub mod app_log {
    pub fn debug(component: &str, message: &str) {
        eprintln!("[debug] {component}: {message}");
    }

    pub fn info(component: &str, message: &str) {
        eprintln!("[info] {component}: {message}");
    }

    pub fn warning(component: &str, message: &str) {
        eprintln!("[warning] {component}: {message}");
    }
}

mod file_manager;
pub use file_manager::reveal_in_file_manager;

mod system_fonts;
pub use system_fonts::list_system_font_families;

mod workspace_path_move;
pub use workspace_path_move::replace_workspace_path_prefix;

// Keep the first extraction source-compatible with GPUI.  Subsequent phases
// can move these files here without changing the public types consumed by
// either desktop client.
#[path = "../../../experiments/alera-gpui/src/forge_api.rs"]
mod forge_api;
#[path = "../../../experiments/alera-gpui/src/forge_service.rs"]
mod forge_service;
#[path = "../../../experiments/alera-gpui/src/model.rs"]
pub mod model;
#[path = "../../../experiments/alera-gpui/src/runtime_bridge.rs"]
pub mod runtime_bridge;
#[path = "../../../experiments/alera-gpui/src/terminal_theme_catalog.rs"]
pub mod terminal_theme_catalog;
#[path = "../../../experiments/alera-gpui/src/workbench_layout_model.rs"]
mod workbench_layout_model;

pub mod terminal_model {
    use std::sync::{Arc, Mutex};

    use alacritty_terminal::event::{Event, EventListener};
    use alacritty_terminal::grid::{Dimensions, Scroll};
    use alacritty_terminal::index::{Column, Line, Point, Side};
    use alacritty_terminal::selection::{Selection, SelectionType};
    use alacritty_terminal::term::cell::Flags;
    use alacritty_terminal::term::test::TermSize;
    use alacritty_terminal::term::{Config, Term, TermMode};
    use alacritty_terminal::vte::ansi::{self, Color, NamedColor, Processor, Rgb};
    use serde::{Deserialize, Serialize};

    #[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
    pub struct Rgba {
        pub red: u8,
        pub green: u8,
        pub blue: u8,
        pub alpha: u8,
    }

    impl Rgba {
        pub const fn rgb(red: u8, green: u8, blue: u8) -> Self {
            Self {
                red,
                green,
                blue,
                alpha: 255,
            }
        }
    }

    #[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
    pub struct TerminalCellStyle {
        pub foreground: Rgba,
        pub background: Rgba,
        pub bold: bool,
        pub italic: bool,
        pub underline: bool,
        pub inverse: bool,
    }

    #[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
    pub struct TerminalCell {
        pub text: String,
        pub style: TerminalCellStyle,
    }

    #[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
    pub struct TerminalCursor {
        pub row: usize,
        pub column: usize,
        pub visible: bool,
        pub blinking: bool,
    }

    #[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
    pub struct TerminalSelection {
        pub start_row: usize,
        pub start_column: usize,
        pub end_row: usize,
        pub end_column: usize,
    }

    #[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
    pub struct TerminalFrame {
        pub rows: Vec<Vec<TerminalCell>>,
        pub cursor: TerminalCursor,
        pub selection: Option<TerminalSelection>,
        pub scroll_offset: usize,
        pub history_size: usize,
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    pub enum TerminalSelectionMode {
        Simple,
        Semantic,
        Lines,
    }

    const DEFAULT_COLUMNS: usize = 100;
    const DEFAULT_ROWS: usize = 30;
    const SCROLLBACK_LINES: usize = 10_000;

    #[derive(Clone, Default)]
    struct TerminalEventSink {
        pty_writes: Arc<Mutex<Vec<Vec<u8>>>>,
    }

    impl EventListener for TerminalEventSink {
        fn send_event(&self, event: Event) {
            if let Event::PtyWrite(text) = event {
                if let Ok(mut writes) = self.pty_writes.lock() {
                    writes.push(text.into_bytes());
                }
            }
        }
    }

    /// ANSI terminal state shared by GPUI and Freya renderers.
    ///
    /// The renderer only consumes the neutral [`TerminalFrame`]. Parsing and
    /// cursor/scrollback semantics remain here so both clients cannot drift.
    pub struct TerminalEmulator {
        terminal: Term<TerminalEventSink>,
        parser: Processor,
        event_sink: TerminalEventSink,
    }

    impl TerminalEmulator {
        pub fn new(columns: usize, rows: usize) -> Self {
            let event_sink = TerminalEventSink::default();
            let terminal = Term::new(
                Config {
                    scrolling_history: SCROLLBACK_LINES,
                    ..Config::default()
                },
                &TermSize::new(columns.max(2), rows.max(2)),
                event_sink.clone(),
            );
            Self {
                terminal,
                parser: Processor::new(),
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

        pub fn start_selection(&mut self, row: f32, column: f32, mode: TerminalSelectionMode) {
            let (point, side) = self.selection_point(row, column);
            let selection_type = match mode {
                TerminalSelectionMode::Simple => SelectionType::Simple,
                TerminalSelectionMode::Semantic => SelectionType::Semantic,
                TerminalSelectionMode::Lines => SelectionType::Lines,
            };
            self.terminal.selection = Some(Selection::new(selection_type, point, side));
        }

        pub fn update_selection(&mut self, row: f32, column: f32) {
            let (point, side) = self.selection_point(row, column);
            if let Some(selection) = self.terminal.selection.as_mut() {
                selection.update(point, side);
            }
        }

        pub fn clear_selection(&mut self) {
            self.terminal.selection = None;
        }

        pub fn selected_text(&self) -> Option<String> {
            self.terminal.selection_to_string()
        }

        pub fn take_pty_writes(&self) -> Vec<Vec<u8>> {
            self.event_sink
                .pty_writes
                .lock()
                .map(|mut writes| std::mem::take(&mut *writes))
                .unwrap_or_default()
        }

        pub fn frame(&self) -> TerminalFrame {
            let content = self.terminal.renderable_content();
            let display_offset = content.display_offset as i32;
            let selection = content.selection.map(|range| TerminalSelection {
                start_row: (range.start.line.0 + display_offset).max(0) as usize,
                start_column: range.start.column.0,
                end_row: (range.end.line.0 + display_offset).max(0) as usize,
                end_column: range.end.column.0,
            });
            let rows = self.terminal.screen_lines();
            let columns = self.terminal.columns();
            let mut cells = vec![vec![TerminalCell::default(); columns]; rows];

            for indexed in content.display_iter {
                let row = indexed.point.line.0 + display_offset;
                if row < 0 || row as usize >= rows || indexed.point.column.0 >= columns {
                    continue;
                }
                let cell = indexed.cell;
                let mut text = String::new();
                if !cell.flags.contains(Flags::WIDE_CHAR_SPACER)
                    && !cell.flags.contains(Flags::HIDDEN)
                {
                    text.push(cell.c);
                    if let Some(zerowidth) = cell.zerowidth() {
                        text.extend(zerowidth);
                    }
                }
                cells[row as usize][indexed.point.column.0] = TerminalCell {
                    text,
                    style: TerminalCellStyle {
                        foreground: resolve_color(cell.fg),
                        background: resolve_color(cell.bg),
                        bold: cell.flags.contains(Flags::BOLD),
                        italic: cell.flags.contains(Flags::ITALIC),
                        underline: cell.flags.intersects(Flags::UNDERLINE),
                        inverse: cell.flags.contains(Flags::INVERSE),
                    },
                };
            }

            let cursor = content.cursor;
            TerminalFrame {
                rows: cells,
                cursor: TerminalCursor {
                    row: cursor.point.line.0.max(0) as usize,
                    column: cursor.point.column.0,
                    visible: display_offset == 0
                        && !matches!(cursor.shape, ansi::CursorShape::Hidden),
                    blinking: true,
                },
                selection,
                scroll_offset: content.display_offset,
                history_size: self.terminal.history_size(),
            }
        }

        fn selection_point(&self, row: f32, column: f32) -> (Point, Side) {
            let row = (row.max(0.) as usize).min(self.terminal.screen_lines().saturating_sub(1));
            let column = column.max(0.);
            let grid_column = (column as usize).min(self.terminal.columns().saturating_sub(1));
            let line = row as i32 - self.terminal.grid().display_offset() as i32;
            let side = if column.fract() < 0.5 {
                Side::Left
            } else {
                Side::Right
            };
            (Point::new(Line(line), Column(grid_column)), side)
        }

        pub fn visible_text(&self) -> String {
            self.frame()
                .rows
                .into_iter()
                .map(|row| row.into_iter().map(|cell| cell.text).collect::<String>())
                .collect::<Vec<_>>()
                .join("\n")
        }

        pub fn encode_key(
            &self,
            key: &str,
            text: Option<&str>,
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
                _ => None,
            };
            if let Some(sequence) = sequence {
                return with_alt_prefix(sequence, modifiers.alt);
            }
            if modifiers.control {
                if let Some(character) = key.chars().next() {
                    if character.is_ascii() {
                        return with_alt_prefix(
                            &[(character.to_ascii_uppercase() as u8) & 0x1f],
                            modifiers.alt,
                        );
                    }
                }
            }
            if modifiers.platform || modifiers.function {
                return Vec::new();
            }
            text.or_else(|| (key.chars().count() == 1).then_some(key))
                .map(|value| with_alt_prefix(value.as_bytes(), modifiers.alt))
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

        pub fn scroll_metrics(&self) -> (usize, usize, usize) {
            (
                self.terminal.renderable_content().display_offset,
                self.terminal.grid().history_size(),
                self.terminal.screen_lines(),
            )
        }
    }

    impl Default for TerminalEmulator {
        fn default() -> Self {
            Self::new(DEFAULT_COLUMNS, DEFAULT_ROWS)
        }
    }

    #[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
    pub struct KeyModifiers {
        pub control: bool,
        pub alt: bool,
        pub shift: bool,
        pub platform: bool,
        pub function: bool,
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

    fn resolve_color(color: Color) -> Rgba {
        match color {
            Color::Spec(Rgb { r, g, b }) => Rgba::rgb(r, g, b),
            Color::Indexed(index) => indexed_color(index),
            Color::Named(named) => named_color(named),
        }
    }

    fn indexed_color(index: u8) -> Rgba {
        match index {
            0..=15 => {
                let colors = [
                    (0, 0, 0),
                    (205, 0, 0),
                    (0, 205, 0),
                    (205, 205, 0),
                    (0, 0, 238),
                    (205, 0, 205),
                    (0, 205, 205),
                    (229, 229, 229),
                    (127, 127, 127),
                    (255, 0, 0),
                    (0, 255, 0),
                    (255, 255, 0),
                    (92, 92, 255),
                    (255, 0, 255),
                    (0, 255, 255),
                    (255, 255, 255),
                ];
                let (red, green, blue) = colors[index as usize];
                Rgba::rgb(red, green, blue)
            }
            16..=231 => {
                let value = index - 16;
                let channel = |value: u8| if value == 0 { 0 } else { 55 + value * 40 };
                Rgba::rgb(
                    channel(value / 36),
                    channel((value / 6) % 6),
                    channel(value % 6),
                )
            }
            232..=255 => {
                let gray = 8 + (index - 232) * 10;
                Rgba::rgb(gray, gray, gray)
            }
        }
    }

    fn named_color(color: NamedColor) -> Rgba {
        match color {
            NamedColor::Black | NamedColor::Background => Rgba::rgb(16, 16, 16),
            NamedColor::Red => Rgba::rgb(205, 0, 0),
            NamedColor::Green => Rgba::rgb(0, 205, 0),
            NamedColor::Yellow => Rgba::rgb(205, 205, 0),
            NamedColor::Blue => Rgba::rgb(0, 0, 238),
            NamedColor::Magenta => Rgba::rgb(205, 0, 205),
            NamedColor::Cyan => Rgba::rgb(0, 205, 205),
            NamedColor::White | NamedColor::Foreground => Rgba::rgb(229, 229, 229),
            NamedColor::BrightBlack => Rgba::rgb(127, 127, 127),
            NamedColor::BrightRed => Rgba::rgb(255, 0, 0),
            NamedColor::BrightGreen => Rgba::rgb(0, 255, 0),
            NamedColor::BrightYellow => Rgba::rgb(255, 255, 0),
            NamedColor::BrightBlue => Rgba::rgb(92, 92, 255),
            NamedColor::BrightMagenta => Rgba::rgb(255, 0, 255),
            NamedColor::BrightCyan => Rgba::rgb(0, 255, 255),
            NamedColor::BrightWhite | NamedColor::Cursor => Rgba::rgb(255, 255, 255),
            _ => Rgba::rgb(229, 229, 229),
        }
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
        fn ansi_frames_preserve_utf8_text_and_cursor() {
            let mut terminal = TerminalEmulator::new(20, 3);
            terminal.write("á".as_bytes());
            terminal.write(b"\r\nnext");
            let frame = terminal.frame();
            assert_eq!(
                terminal.visible_text().lines().next().map(str::trim_end),
                Some("á")
            );
            assert_eq!(frame.cursor.row, 1);
            assert_eq!(frame.cursor.column, 4);
            assert!(frame.cursor.visible);
        }

        #[test]
        fn key_encoding_and_bracketed_paste_match_terminal_protocol() {
            let mut terminal = TerminalEmulator::new(20, 3);
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
            terminal.write(b"\x1b[?2004h");
            assert_eq!(
                terminal.encode_paste("a\x1b[201~b"),
                b"\x1b[200~ab\x1b[201~"
            );
        }

        #[test]
        fn resize_scrollback_and_selection_stay_in_the_neutral_model() {
            let mut terminal = TerminalEmulator::new(10, 2);
            terminal.write(b"hello\r\nsecond\r\nthird");
            assert!(terminal.frame().history_size > 0);
            terminal.scroll_display(1);
            assert!(terminal.frame().scroll_offset > 0);
            terminal.scroll_display(-1);
            terminal.resize(12, 3);
            assert_eq!(terminal.frame().rows.len(), 3);

            terminal.start_selection(1., 0., TerminalSelectionMode::Simple);
            terminal.update_selection(1., 4.9);
            let frame = terminal.frame();
            assert_eq!(
                frame.selection,
                Some(TerminalSelection {
                    start_row: 1,
                    start_column: 0,
                    end_row: 1,
                    end_column: 4,
                })
            );
            assert!(terminal.selected_text().is_some());
            terminal.clear_selection();
            assert!(terminal.frame().selection.is_none());
        }

        #[test]
        fn ansi_frames_keep_background_and_inverse_attributes() {
            let mut terminal = TerminalEmulator::new(10, 2);
            terminal.write(b"\x1b[31;44mA\x1b[7mB");
            let frame = terminal.frame();
            assert_eq!(frame.rows[0][0].style.foreground, Rgba::rgb(205, 0, 0));
            assert_eq!(frame.rows[0][0].style.background, Rgba::rgb(0, 0, 238));
            assert!(frame.rows[0][1].style.inverse);
        }
    }
}

pub use forge_api::{
    ForgeAction, ForgeAuthStatus, ForgeCheck, ForgeComment, ForgeIdentity, ForgeReview,
    ForgeService, ForgeSnapshot, ForgeUnavailableReason, MergeMethod,
};
pub use forge_service::{github_identity, unavailable_snapshot};
pub use model::{
    Project, WorkbenchDropZone, WorkbenchLayout, WorkbenchLayoutNode, WorkbenchPaneGroup,
    WorkbenchSnapshot, WorkbenchSplitAxis, WorkbenchSplitDirection, Workspace, WorkspaceRelation,
    WorkspaceTab, WorkspaceTag,
};
pub use runtime_bridge::{BridgeEvent, RuntimeBridge, RuntimeHostStartConfig};
pub use terminal_model::{
    KeyModifiers, TerminalCell, TerminalCursor, TerminalEmulator, TerminalFrame, TerminalSelection,
    TerminalSelectionMode, TerminalSession,
};
