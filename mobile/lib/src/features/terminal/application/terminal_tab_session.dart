import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';

/// Raised when a desktop driver takes the terminal viewport back.
class DesktopReclaimedTerminal implements Exception {
  const DesktopReclaimedTerminal();

  @override
  String toString() => 'Desktop took back the terminal';
}

/// A live terminal attachment with its replay snapshot and filtered output.
class TerminalTabSession {
  TerminalTabSession({
    required this.sessionId,
    required List<int> snapshot,
    required this.running,
    required this.output,
    this.snapshotCols,
    this.snapshotRows,
  }) : _snapshot = _TerminalSnapshotPayload(snapshot);

  final String sessionId;
  final bool running;
  final _TerminalSnapshotPayload _snapshot;

  /// The size the snapshot was written at, absent on a host that predates the
  /// field. The emulator replays there before taking the phone's own size.
  final int? snapshotCols;
  final int? snapshotRows;

  /// Carries full events so resync replacement stays ordered with live output.
  final Stream<MobileTerminalOutputEvent> output;

  /// Transfers restore bytes without retaining rendered scrollback twice.
  List<int> takeSnapshot() => _snapshot.take();

  int get retainedSnapshotBytes => _snapshot.retainedBytes;
}

class _TerminalSnapshotPayload {
  _TerminalSnapshotPayload(this._bytes);

  List<int>? _bytes;

  int get retainedBytes => _bytes?.length ?? 0;

  List<int> take() {
    final value = _bytes;
    _bytes = null;
    return value ?? const <int>[];
  }
}
