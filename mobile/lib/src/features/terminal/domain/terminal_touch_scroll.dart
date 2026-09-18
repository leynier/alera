/// Lines of finger travel that become one wheel report when a full-screen
/// agent TUI (alternate screen or mouse reporting) owns the scroll.
///
/// A mouse notch is one report and those TUIs move more than one line per
/// report, so one report per line made the transcript outrun the finger. Two
/// keeps a drag close to 1:1 with what moves under it without feeling stuck on
/// an application that scrolls a single line per report.
const int mobileTouchScrollLinesPerWheelEvent = 2;

/// How far above the live screen, in lines, the reader has to be before the
/// Jump To Latest control appears. Under this the bottom is a flick away and
/// the control would only cover output.
const int terminalJumpToLatestThresholdLines = 2;
