/// DEC private modes that should not leak from an exited TUI into a new shell.
///
/// Replayed snapshots can retain cursor/keypad/focus modes, an alternate
/// screen, mouse reporting, or bracketed paste even though the replacement
/// process did not. Restore a normal shell state after remint/exit.
const String terminalInteractionModeReset =
    '\x1b[?1l\x1b[?25h\x1b[?47l\x1b[?1047l\x1b[?1049l\x1b[?1004l\x1b>'
    '\x1b[?9l\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1005l\x1b[?1006l'
    '\x1b[?1015l\x1b[?1016l\x1b[?2004l';
