import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_snapshot_payload.dart';

/// Raised when a desktop driver takes the terminal viewport back.
class const DesktopReclaimedTerminal() implements Exception {
  @override
  String toString() => 'Desktop took back the terminal';
}

/// A live terminal attachment with its replay snapshot and filtered output.
class TerminalTabSession({
  required final String sessionId,
  required List<int> snapshot,
  required final bool running,
  required this.output,
  this.snapshotCols,
  final int? snapshotRows,
  String? snapshotBase64,
}) {
  this
    : _snapshot = _RetainedSnapshot(
        snapshotBase64 != null && snapshotBase64.isNotEmpty
            ? TerminalSnapshotPayload.base64(snapshotBase64)
            : TerminalSnapshotPayload.bytes(snapshot),
      );

  final _RetainedSnapshot _snapshot;

  /// The size the snapshot was written at, absent on a host that predates the
  /// field. The emulator replays there before taking the phone's own size.
  final int? snapshotCols;

  /// Carries full events so resync replacement stays ordered with live output.
  final Stream<MobileTerminalOutputEvent> output;

  /// Transfers the restore payload without retaining scrollback twice.
  TerminalSnapshotPayload takeSnapshot() => _snapshot.take();

  int get retainedSnapshotBytes => _snapshot.retainedBytes;
}

class _RetainedSnapshot(var TerminalSnapshotPayload? _payload) {
  int get retainedBytes => _payload?.size ?? 0;

  TerminalSnapshotPayload take() {
    final value = _payload;
    _payload = null;
    return value ?? TerminalSnapshotPayload.empty;
  }
}
