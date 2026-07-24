/// User choice when quitting Alera while the sidecar still has work.
enum RuntimeHostQuitDecision {
  /// Stay in the app; do not close the window.
  cancel,

  /// Quit and leave the sidecar running (matches unexpected-exit default).
  leaveRuntimeOpen,

  /// Force-stop the sidecar, then quit.
  forceStop,
}
