import 'dart:async';

import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_driver_presence_controller.g.dart';

/// Mirror of the runtime's terminal driver map (session id -> driver), fed by
/// `terminalDriverChanged` events and bootstrapped from `terminal.driver.list`
/// so overlay state survives app restarts while a phone keeps driving.
@Riverpod(keepAlive: true)
class TerminalDriverPresenceController
    extends _$TerminalDriverPresenceController {
  @override
  Map<String, TerminalSessionDriver> build() {
    final client = ref.watch(terminalHostClientProvider);
    final subscription = client.events.listen((event) {
      if (event is TerminalHostDriverChangedEvent) {
        final next = Map<String, TerminalSessionDriver>.of(state);
        if (event.driver.isMobile) {
          next[event.sessionId] = event.driver;
        } else {
          next.remove(event.sessionId);
        }
        state = next;
      }
    });
    ref.onDispose(subscription.cancel);
    unawaited(_bootstrap(client));
    return const <String, TerminalSessionDriver>{};
  }

  Future<void> _bootstrap(TerminalHostClient client) async {
    try {
      final drivers = await client.listTerminalDrivers();
      final mobileDriven = <String, TerminalSessionDriver>{
        for (final entry in drivers.entries)
          if (entry.value.isMobile) entry.key: entry.value,
      };
      // Events that raced the bootstrap win; only fill unknown sessions.
      state = <String, TerminalSessionDriver>{...mobileDriven, ...state};
    } on Object {
      // An older sidecar without driver presence simply reports nothing.
    }
  }

  /// Desktop "Take Back": restores the desktop dims for one session.
  Future<void> reclaim(String sessionId) async {
    final client = ref.read(terminalHostClientProvider);
    await client.reclaimTerminal(sessionId);
  }

  /// "Take Back All": reclaims every mobile-driven session.
  Future<void> reclaimAll() async {
    final sessionIds = state.keys.toList(growable: false);
    for (final sessionId in sessionIds) {
      await reclaim(sessionId);
    }
  }
}
