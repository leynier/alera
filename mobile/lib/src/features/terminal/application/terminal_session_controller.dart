import 'dart:async';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
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

  /// Carries the full event, not just the bytes, so a resync answer that
  /// replaces the scrollback stays ordered against the live output around it.
  final Stream<MobileTerminalOutputEvent> output;
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
      output: client.terminalOutput.where(
        (event) => event.sessionId == sessionId,
      ),
    );
  }

  /// Raw keystrokes: the accessory bar and direct mode. These must never be
  /// pasted or deferred, since each one is already a single key.
  Future<void> write(List<int> bytes) async {
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    await client.writeTerminal(session.sessionId, bytes);
  }

  /// Compose-mode send. The prompt and its Enter become separate PTY writes
  /// when the host supports it, because an agent TUI reads a CR arriving inside
  /// an input burst as a literal newline instead of a submit.
  Future<void> sendComposedText(String text, {required bool withEnter}) async {
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    final delivery = TerminalComposeDelivery.forText(
      text,
      withEnter: withEnter,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    await client.writeTerminal(
      session.sessionId,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
      deferredEnter: delivery.deferredEnter,
    );
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
