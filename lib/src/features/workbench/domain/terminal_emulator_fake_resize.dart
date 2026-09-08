import 'dart:math' as math;

/// Scale applied to emulator cols/rows during a Refresh fake-resize.
const double terminalEmulatorFakeResizeScale = 1.3;

/// Adjacent emulator size used to force a stuck agent TUI to relayout.
///
/// About 30% larger than [cols]x[rows], and at least one cell larger on each
/// positive axis so a 1x1 view still changes. Non-positive sizes are returned
/// unchanged so a bad viewport is never sent.
(int cols, int rows) terminalEmulatorFakeResizeSize(int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    return (cols, rows);
  }
  return (_bumpAxis(cols), _bumpAxis(rows));
}

/// Applies the bump, then restores [cols]x[rows], through [resize] only.
///
/// Callers that own a PTY must not forward these sizes to it. A no-op when
/// the size cannot change.
void pulseTerminalEmulatorSize({
  required int cols,
  required int rows,
  required void Function(int cols, int rows) resize,
}) {
  final bumped = terminalEmulatorFakeResizeSize(cols, rows);
  if (bumped.$1 == cols && bumped.$2 == rows) {
    return;
  }
  resize(bumped.$1, bumped.$2);
  resize(cols, rows);
}

int _bumpAxis(int value) {
  final scaled = (value * terminalEmulatorFakeResizeScale).round();
  return math.max(value + 1, scaled);
}
