import 'dart:async';
import 'dart:typed_data';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_session_controller.g.dart';

/// Raised into the session state when the desktop takes the viewport back
/// (`terminalDriverChanged` with a desktop driver); the tabs screen reacts by
/// leaving the terminal.
class DesktopReclaimedTerminal implements Exception {
  const DesktopReclaimedTerminal();

  @override
  String toString() => 'Desktop Took Back The Terminal';
}

/// A live attachment to one terminal tab: the session handle, the scrollback
/// snapshot to replay, and the filtered output stream.
class TerminalTabSession {
  const TerminalTabSession({
    required this.sessionId,
    required this.snapshot,
    required this.running,
    required this.output,
  });

  final String sessionId;
  final List<int> snapshot;
  final bool running;
  final Stream<Uint8List> output;
}

@riverpod
class TerminalSessionController extends _$TerminalSessionController {
  @override
  Future<TerminalTabSession> build(String hostId, String tabId) async {
    final client = await ref.watch(terminalClientProvider(hostId).future);
    // The runtime restarts exited sessions under the same handle during
    // attach, so a single attach always yields a usable session.
    final session = await client.attachTerminal(tabId);
    final sessionId = session.attachment.sessionId;
    ref.onDispose(() {
      unawaited(_detachQuietly(client, sessionId));
    });
    final driverSub = client.events.listen((event) {
      if (event.name != 'terminalDriverChanged' ||
          event.payload['sessionId'] != sessionId) {
        return;
      }
      final driver = asJsonMap(event.payload['driver']);
      if (driver['kind'] == 'desktop') {
        state = AsyncError(
          const DesktopReclaimedTerminal(),
          StackTrace.current,
        );
      }
    });
    ref.onDispose(driverSub.cancel);
    return TerminalTabSession(
      sessionId: sessionId,
      snapshot: session.attachment.snapshot,
      running: session.attachment.running,
      output: client.terminalOutput
          .where((event) => event.sessionId == sessionId)
          .map((event) => event.data),
    );
  }

  Future<void> write(List<int> bytes) async {
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    await client.writeTerminal(session.sessionId, bytes);
  }

  Future<void> resize(int cols, int rows) async {
    if (cols <= 0 || rows <= 0) {
      return;
    }
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    await client.resizeTerminal(session.sessionId, cols, rows);
  }

  Future<void> _detachQuietly(
    MobileTerminalClient client,
    String sessionId,
  ) async {
    try {
      await client.detachTerminal(sessionId);
    } on Object {
      // The socket may already be gone; leaving is best-effort.
    }
  }
}

/// Convenience for pre-resolving the session id of a tab without attaching.
String terminalSessionIdOf(WorkspaceTabSummary tab) => tab.terminalSessionId;
