import 'dart:async';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:logging/logging.dart';

const Duration agentAwakeStatusStaleAfter = Duration(hours: 2);

abstract interface class AgentAwakeDisplayLock {
  Future<void> setEnabled(bool enabled);
}

abstract interface class AgentAwakeAssertion {
  Future<void> start(String reason);
  Future<void> stop(String reason);
  Future<void> dispose();
}

class AgentAwakeService({
  required final AgentAwakeDisplayLock displayLock,
  required List<AgentAwakeAssertion> assertions,
  DateTime Function()? now,
  final Duration statusStaleAfter = agentAwakeStatusStaleAfter,
  Logger? logger,
}) {
  this
    : _assertions = List<AgentAwakeAssertion>.unmodifiableOf(assertions),
      _now = now ?? (() => DateTime.now().toUtc()),
      _logger = logger ?? Logger('AgentAwakeService');

  final List<AgentAwakeAssertion> _assertions;
  final DateTime Function() _now;
  final Logger _logger;

  bool _enabled = false;
  bool _displayLockEnabled = false;
  bool _disposed = false;
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _disposeFuture;
  AgentStatusHookSettings _hookSettings = .defaults;
  Map<String, AgentStatusEntry> _statuses = const <String, AgentStatusEntry>{};
  Timer? _staleTimer;

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    await _refresh('settings-change');
  }

  Future<void> setHookSettings(AgentStatusHookSettings settings) async {
    if (_hookSettings == settings) {
      return;
    }
    _hookSettings = settings;
    await _refresh('hook-settings-change');
  }

  Future<void> setStatuses(Map<String, AgentStatusEntry> statuses) async {
    _statuses = Map<String, AgentStatusEntry>.unmodifiableOf(statuses);
    await _refresh('status-change');
  }

  Future<void> dispose() async {
    final existingDispose = _disposeFuture;
    if (existingDispose != null) {
      return existingDispose;
    }
    _disposed = true;
    _clearStaleTimer();
    final disposeFuture = _enqueue(() async {
      await _setDisplayLock(false, 'dispose');
      for (final assertion in _assertions) {
        await _tryAssertion('dispose assertion', () => assertion.dispose());
      }
    });
    _disposeFuture = disposeFuture;
    await disposeFuture;
  }

  Future<void> _refresh(String reason) {
    if (_disposed) {
      return Future<void>.value();
    }
    return _enqueue(() => _performRefresh(reason));
  }

  Future<void> _performRefresh(String reason) async {
    if (_disposed) {
      return;
    }
    _scheduleStaleTimer();
    final runningStatusCount = _eligibleRunningStatusCount();
    final shouldStayAwake = _enabled && runningStatusCount > 0;
    if (shouldStayAwake) {
      await _setDisplayLock(true, reason);
      for (final assertion in _assertions) {
        await _tryAssertion('start assertion', () => assertion.start(reason));
      }
    } else {
      for (final assertion in _assertions) {
        await _tryAssertion('stop assertion', () => assertion.stop(reason));
      }
      await _setDisplayLock(false, reason);
    }
  }

  int _eligibleRunningStatusCount() {
    final now = _now();
    return _statuses.values
        .where((entry) => _isWakeEligible(entry, now))
        .length;
  }

  bool _isWakeEligible(AgentStatusEntry entry, DateTime now) {
    return entry.state == AgentStatusState.working &&
        _isAgentHookEnabled(entry.agentType) &&
        now.difference(entry.updatedAt) <= statusStaleAfter;
  }

  bool _isAgentHookEnabled(AgentType agentType) {
    return switch (agentType) {
      AgentType.codex => _hookSettings.codex,
      AgentType.claude => _hookSettings.claude,
      AgentType.copilot => _hookSettings.copilot,
      AgentType.cursor => _hookSettings.cursor,
      AgentType.agy => _hookSettings.agy,
      AgentType.opencode => _hookSettings.opencode,
      AgentType.opencode2 => _hookSettings.opencode2,
      AgentType.pi => _hookSettings.pi,
      AgentType.amp => _hookSettings.amp,
      AgentType.grok => _hookSettings.grok,
      AgentType.fx => _hookSettings.fx,
    };
  }

  void _scheduleStaleTimer() {
    _clearStaleTimer();
    if (!_enabled) {
      return;
    }
    final now = _now();
    DateTime? earliestExpiry;
    for (final entry in _statuses.values) {
      if (entry.state != AgentStatusState.working ||
          !_isAgentHookEnabled(entry.agentType)) {
        continue;
      }
      final expiry = entry.updatedAt.add(statusStaleAfter);
      if (!expiry.isAfter(now)) {
        continue;
      }
      earliestExpiry = earliestExpiry == null || expiry.isBefore(earliestExpiry)
          ? expiry
          : earliestExpiry;
    }
    if (earliestExpiry == null) {
      return;
    }
    _staleTimer = Timer(earliestExpiry.difference(now), () {
      _staleTimer = null;
      unawaited(_refresh('stale-expiry'));
    });
  }

  void _clearStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  Future<void> _setDisplayLock(bool enabled, String reason) async {
    if (_displayLockEnabled == enabled) {
      return;
    }
    try {
      await displayLock.setEnabled(enabled);
      _displayLockEnabled = enabled;
    } catch (error, stackTrace) {
      _logger.warning(
        '[agent-awake] failed to ${enabled ? 'start' : 'stop'} display lock: $reason',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _tryAssertion(
    String description,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _logger.warning(
        '[agent-awake] failed to $description',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
