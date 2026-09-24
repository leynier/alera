/// How long a later viewport change waits before pulsing.
///
/// Matches the desktop PTY resize debounce. The first measured size pulses
/// immediately; rotation and keyboard-driven resizes settle first so a TUI
/// is not redrawn at every intermediate geometry.
const Duration terminalViewportPulseDebounce = Duration(milliseconds: 150);

/// Fraction of the measured viewport subtracted during an explicit Refresh.
///
/// One column is easy for a full-screen agent TUI to ignore. About 30% is
/// large enough to force a relayout, then the measured size is restored so
/// the PTY does not stay at the fake geometry.
const double terminalViewportRefreshBumpFraction = 0.3;

/// Adjacent PTY size used after first layout and settled rotation/keyboard.
///
/// One-column pair, then restore. Two ordinary `resize` calls, no new
/// protocol verb. Explicit Refresh uses [terminalViewportRefreshPulseSize]
/// instead: a 30% bump on every keyboard or rotation flash would redraw the
/// TUI twice extra.
(int cols, int rows) terminalViewportPulseSize(int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    return (cols, rows);
  }
  return (cols > 1 ? cols - 1 : cols + 1, rows);
}

/// ~30% PTY size used by Refresh so a stuck TUI cannot ignore a 1-cell change.
///
/// Shrinks both axes when there is room, otherwise grows the 1-cell edge
/// case. Apply this size, then restore the measured size.
(int cols, int rows) terminalViewportRefreshPulseSize(int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    return (cols, rows);
  }
  return (_refreshPulseDimension(cols), _refreshPulseDimension(rows));
}

int _refreshPulseDimension(int size) {
  var delta = (size * terminalViewportRefreshBumpFraction).round();
  if (delta < 1) {
    delta = 1;
  }
  final smaller = size - delta;
  return smaller >= 1 ? smaller : size + delta;
}
