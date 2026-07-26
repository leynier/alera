import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

/// The sidecar configuration implied by the user's terminal settings.
///
/// Shared by the workbench warmup and the runtime-host lifecycle service: both
/// send `configure`, and a host that got two different configurations
/// depending on which one ran last would behave differently between launches.
TerminalHostConfig terminalHostConfigFor(TerminalSettings settings) {
  return TerminalHostConfig(
    emptyShutdownDelaySeconds: settings.hostEmptyShutdownDelaySeconds,
    detachedSessionShutdownDelaySeconds:
        settings.hostDetachedSessionShutdownDelaySeconds,
    scrollbackBytes: settings.hostScrollbackBytes,
    restoreSnapshotBytes: restoreSnapshotBytesFor(settings),
    loginShell: settings.resolvedLoginShell,
  );
}

/// How much scrollback the host may replay into a fresh emulator.
///
/// Distinct from `hostScrollbackBytes`, which is what the host *retains* so
/// `terminal.read` and checkpoints can page back through it. Replaying all of
/// that costs a VT parse per byte on the UI isolate for history the emulator
/// drops on the floor: it only keeps `scrollbackLines` lines. 256 bytes per
/// line is a generous allowance for escape-heavy agent output, and the floor
/// keeps a small scrollback setting from restoring less than a viewport.
int restoreSnapshotBytesFor(TerminalSettings settings) {
  const bytesPerLine = 256;
  const floorBytes = 256 * 1024;
  final budget = settings.scrollbackLines * bytesPerLine;
  final wanted = budget < floorBytes ? floorBytes : budget;
  // Never above what the host actually keeps; asking for more is meaningless.
  return wanted < settings.hostScrollbackBytes
      ? wanted
      : settings.hostScrollbackBytes;
}
