/// Adjacent PTY size used to force a full-screen agent TUI to redraw.
///
/// Same one-column pulse as desktop `TerminalHostPtySession.refreshViewport`:
/// apply this size, then restore the measured size. Two ordinary `resize`
/// calls, no new protocol verb. A later Refresh-track change may widen the
/// bump; keep the size policy here so those call sites stay compatible.
(int cols, int rows) terminalViewportPulseSize(int cols, int rows) {
  if (cols <= 0 || rows <= 0) {
    return (cols, rows);
  }
  return (cols > 1 ? cols - 1 : cols + 1, rows);
}
