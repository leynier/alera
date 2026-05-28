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
        'session-1': _entry(state: AgentStatusState.working),
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
        'session-1': _entry(state: AgentStatusState.working),
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
        'session-1': _entry(state: AgentStatusState.waiting),
        'session-2': _entry(
          terminalSessionId: 'session-2',
          state: AgentStatusState.working,
        ),
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
        'session-1': _entry(state: AgentStatusState.working, updatedAt: base),
      });

      now = base.add(staleAfter).add(const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
        'session-1': _entry(state: AgentStatusState.working),
      });
      await service.setEnabled(false);

      expect(displayLock.states, <bool>[true, false]);
      expect(assertion.stops, contains('settings-change'));
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
  AgentStatusState state = AgentStatusState.working,
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime.utc(2026, 5, 27, 12);
  return AgentStatusEntry(
    terminalSessionId: terminalSessionId,
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: AgentType.codex,
    state: state,
    prompt: 'Run tests',
    updatedAt: time,
    stateStartedAt: time,
  );
}

class _FakeDisplayLock implements AgentAwakeDisplayLock {
  final List<bool> states = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async {
    states.add(enabled);
  }
}

class _FakeAssertion implements AgentAwakeAssertion {
  final List<String> starts = <String>[];
  final List<String> stops = <String>[];
  var disposeCount = 0;

  @override
  Future<void> start(String reason) async {
    starts.add(reason);
  }

  @override
  Future<void> stop(String reason) async {
    stops.add(reason);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}
