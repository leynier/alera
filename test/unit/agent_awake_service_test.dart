import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentAwakeService', () {
    test('stays idle when disabled even with a working status', () async {
      final displayLock = _FakeDisplayLock();
      final assertion = _FakeAssertion();
      final service = _service(displayLock: displayLock, assertion: assertion);

      await service.setHookSettings(const AgentStatusHookSettings(codex: true));
      await service.setStatuses(<String, AgentStatusEntry>{
        'session-1': _entry(state: .working),
      });

      expect(displayLock.states, isEmpty);
      expect(assertion.starts, isEmpty);
    });

    test('starts and stops while an enabled hook reports working', () async {
      final displayLock = _FakeDisplayLock();
      final assertion = _FakeAssertion();
      final service = _service(displayLock: displayLock, assertion: assertion);

      await service.setHookSettings(const AgentStatusHookSettings(codex: true));
      await service.setEnabled(true);
      await service.setStatuses(<String, AgentStatusEntry>{
        'session-1': _entry(state: .working),
      });
      await service.setStatuses(const <String, AgentStatusEntry>{});

      expect(displayLock.states, <bool>[true, false]);
      expect(assertion.starts, <String>['status-change']);
      expect(assertion.stops, contains('status-change'));
    });

    test('ignores non-working and disabled-hook statuses', () async {
      final displayLock = _FakeDisplayLock();
      final assertion = _FakeAssertion();
      final service = _service(displayLock: displayLock, assertion: assertion);

      await service.setEnabled(true);
      await service.setHookSettings(
        const AgentStatusHookSettings(claude: true),
      );
      await service.setStatuses(<String, AgentStatusEntry>{
        'session-1': _entry(state: .waiting),
        'session-2': _entry(terminalSessionId: 'session-2', state: .working),
      });

      expect(displayLock.states, isEmpty);
      expect(assertion.starts, isEmpty);
    });

    test('stops when the only working status becomes stale', () async {
      final displayLock = _FakeDisplayLock();
      final assertion = _FakeAssertion();
      final staleAfter = const Duration(milliseconds: 5);
      final base = DateTime.utc(2026, 5, 27, 12);
      var now = base;
      final service = _service(
        displayLock: displayLock,
        assertion: assertion,
        now: () => now,
        staleAfter: staleAfter,
      );

      await service.setHookSettings(const AgentStatusHookSettings(codex: true));
      await service.setEnabled(true);
      await service.setStatuses(<String, AgentStatusEntry>{
        'session-1': _entry(state: .working, updatedAt: base),
      });

      now = base.add(staleAfter).add(const Duration(milliseconds: 1));
      await _waitForAssertionStop(assertion, 'stale-expiry');

      expect(displayLock.states, <bool>[true, false]);
      expect(assertion.stops, contains('stale-expiry'));
      await service.dispose();
    });

    test('disabling the setting stops active assertions', () async {
      final displayLock = _FakeDisplayLock();
      final assertion = _FakeAssertion();
      final service = _service(displayLock: displayLock, assertion: assertion);

      await service.setHookSettings(const AgentStatusHookSettings(codex: true));
      await service.setEnabled(true);
      await service.setStatuses(<String, AgentStatusEntry>{
        'session-1': _entry(state: .working),
      });
      await service.setEnabled(false);

      expect(displayLock.states, <bool>[true, false]);
      expect(assertion.stops, contains('settings-change'));
    });

    test(
      'serializes a working to idle transition while start is pending',
      () async {
        final displayLock = _FakeDisplayLock();
        final assertion = _FakeAssertion()..startGate = Completer<void>();
        final service = _service(
          displayLock: displayLock,
          assertion: assertion,
        );

        await service.setHookSettings(
          const AgentStatusHookSettings(codex: true),
        );
        await service.setEnabled(true);
        final working = service.setStatuses(<String, AgentStatusEntry>{
          'session-1': _entry(state: .working),
        });
        await _waitForAssertionStarts(assertion, 1);
        final idle = service.setStatuses(const <String, AgentStatusEntry>{});
        assertion.startGate!.complete();
        await Future.wait<void>(<Future<void>>[working, idle]);

        expect(assertion.maxActiveCount, 1);
        expect(assertion.activeCount, 0);
        expect(assertion.stops, contains('status-change'));
        await service.dispose();
      },
    );

    test('treats every enabled agent hook as wake eligible', () async {
      for (final agentType in AgentType.values) {
        final displayLock = _FakeDisplayLock();
        final assertion = _FakeAssertion();
        final updatedAt = DateTime.now().toUtc();
        final service = AgentAwakeService(
          displayLock: displayLock,
          assertions: <AgentAwakeAssertion>[assertion],
        );

        await service.setHookSettings(_settingsFor(agentType));
        await service.setEnabled(true);
        await service.setStatuses(<String, AgentStatusEntry>{
          'session-${agentType.key}': _entry(
            agentType: agentType,
            updatedAt: updatedAt,
          ),
        });

        expect(displayLock.states, <bool>[true], reason: agentType.key);
        expect(assertion.starts, <String>['status-change']);
        await service.dispose();
      }
    });

    test('uses the earliest future status expiry for stale refresh', () async {
      final displayLock = _FakeDisplayLock();
      final assertion = _FakeAssertion();
      final staleAfter = const Duration(milliseconds: 20);
      final base = DateTime.utc(2026, 5, 27, 12);
      var now = base;
      final service = _service(
        displayLock: displayLock,
        assertion: assertion,
        now: () => now,
        staleAfter: staleAfter,
      );

      await service.setHookSettings(
        const AgentStatusHookSettings(codex: true, claude: true),
      );
      await service.setEnabled(true);
      await service.setStatuses(<String, AgentStatusEntry>{
        'late': _entry(
          terminalSessionId: 'late',
          agentType: .codex,
          updatedAt: base,
        ),
        'early': _entry(
          terminalSessionId: 'early',
          agentType: .claude,
          updatedAt: base.subtract(const Duration(milliseconds: 15)),
        ),
      });

      now = base.add(const Duration(milliseconds: 6));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(displayLock.states, <bool>[true]);
      expect(assertion.starts, contains('stale-expiry'));
      await service.dispose();
    });

    test('logs and continues when display lock and assertions fail', () async {
      final displayLock = _FakeDisplayLock()..throwOnSet = true;
      final assertion = _FakeAssertion()
        ..throwOnStart = true
        ..throwOnStop = true
        ..throwOnDispose = true;
      final service = _service(displayLock: displayLock, assertion: assertion);

      await service.setHookSettings(const AgentStatusHookSettings(codex: true));
      await service.setEnabled(true);
      await service.setStatuses(<String, AgentStatusEntry>{
        'session-1': _entry(),
      });
      await service.setStatuses(const <String, AgentStatusEntry>{});
      await service.dispose();
      await service.dispose();

      expect(displayLock.states, <bool>[true]);
      expect(assertion.starts, <String>['status-change']);
      expect(assertion.stops, contains('status-change'));
      expect(assertion.disposeCount, 1);
    });
  });
}

AgentAwakeService _service({
  required _FakeDisplayLock displayLock,
  required _FakeAssertion assertion,
  DateTime Function()? now,
  Duration staleAfter = const Duration(hours: 2),
}) {
  return AgentAwakeService(
    displayLock: displayLock,
    assertions: <AgentAwakeAssertion>[assertion],
    now: now ?? () => DateTime.utc(2026, 5, 27, 12),
    statusStaleAfter: staleAfter,
  );
}

AgentStatusEntry _entry({
  String terminalSessionId = 'session-1',
  AgentType agentType = AgentType.codex,
  AgentStatusState state = AgentStatusState.working,
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime.utc(2026, 5, 27, 12);
  return AgentStatusEntry(
    terminalSessionId: terminalSessionId,
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: agentType,
    state: state,
    prompt: 'Run tests',
    updatedAt: time,
    stateStartedAt: time,
  );
}

AgentStatusHookSettings _settingsFor(AgentType agentType) {
  return switch (agentType) {
    AgentType.codex => const AgentStatusHookSettings(codex: true),
    AgentType.claude => const AgentStatusHookSettings(claude: true),
    AgentType.copilot => const AgentStatusHookSettings(copilot: true),
    AgentType.cursor => const AgentStatusHookSettings(cursor: true),
    AgentType.agy => const AgentStatusHookSettings(agy: true),
    AgentType.opencode => const AgentStatusHookSettings(opencode: true),
    AgentType.opencode2 => const AgentStatusHookSettings(opencode2: true),
    AgentType.pi => const AgentStatusHookSettings(pi: true),
    AgentType.amp => const AgentStatusHookSettings(amp: true),
    AgentType.grok => const AgentStatusHookSettings(grok: true),
    AgentType.fx => const AgentStatusHookSettings(fx: true),
  };
}

class _FakeDisplayLock implements AgentAwakeDisplayLock {
  final List<bool> states = <bool>[];
  var throwOnSet = false;

  @override
  Future<void> setEnabled(bool enabled) async {
    states.add(enabled);
    if (throwOnSet) {
      throw StateError('display lock failed');
    }
  }
}

Future<void> _waitForAssertionStarts(
  _FakeAssertion assertion,
  int count, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (assertion.starts.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Expected at least $count assertion starts.');
}

Future<void> _waitForAssertionStop(
  _FakeAssertion assertion,
  String reason, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (assertion.stops.contains(reason)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Expected an assertion stop for $reason.');
}

class _FakeAssertion implements AgentAwakeAssertion {
  final List<String> starts = <String>[];
  final List<String> stops = <String>[];
  var disposeCount = 0;
  var throwOnStart = false;
  var throwOnStop = false;
  var throwOnDispose = false;
  Completer<void>? startGate;
  var activeCount = 0;
  var maxActiveCount = 0;

  @override
  Future<void> start(String reason) async {
    starts.add(reason);
    activeCount++;
    if (activeCount > maxActiveCount) {
      maxActiveCount = activeCount;
    }
    await startGate?.future;
    if (throwOnStart) {
      throw StateError('start failed');
    }
  }

  @override
  Future<void> stop(String reason) async {
    stops.add(reason);
    if (activeCount > 0) {
      activeCount--;
    }
    if (throwOnStop) {
      throw StateError('stop failed');
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (throwOnDispose) {
      throw StateError('dispose failed');
    }
  }
}
