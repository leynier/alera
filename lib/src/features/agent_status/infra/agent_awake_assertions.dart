import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:logging/logging.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const Duration macosSystemSleepAssertionRetryDelay = Duration(seconds: 30);
const Duration linuxLidSleepAssertionRetryDelay = Duration(seconds: 30);
const int _windowsExecutionStateSystemRequired = 0x00000001;
const int _windowsExecutionStateDisplayRequired = 0x00000002;
const int _windowsExecutionStateContinuous = 0x80000000;
const int _windowsAwakeExecutionState =
    _windowsExecutionStateContinuous |
    _windowsExecutionStateSystemRequired |
    _windowsExecutionStateDisplayRequired;

typedef WindowsExecutionStateSetter = int Function(int flags);

// coverage:ignore-start
// Thin adapter to wakelock_plus. Unit tests cover AgentAwakeDisplayLock through
// injected fakes; plugin behavior belongs to desktop integration coverage.
class const WakelockAgentAwakeDisplayLock() implements AgentAwakeDisplayLock {
  @override
  Future<void> setEnabled(bool enabled) {
    return WakelockPlus.toggle(enable: enabled);
  }
}
// coverage:ignore-end

class MacosSystemSleepAssertion({
  required super.processRunner,
  super.now,
  super.logger,
  super.platform,
  super.retryDelay = macosSystemSleepAssertionRetryDelay,
}) extends _ProcessBackedAwakeAssertion {
  this
    : super(
        executable: '/usr/bin/caffeinate',
        arguments: const <String>['-i', '-s'],
        supportedPlatform: 'macos',
        label: 'macOS system sleep assertion',
      );
}

class LinuxLidSleepAssertion({
  required super.processRunner,
  int? processId,
  super.now,
  super.logger,
  super.platform,
  super.retryDelay = linuxLidSleepAssertionRetryDelay,
}) extends _ProcessBackedAwakeAssertion {
  this
    : super(
        executable: 'systemd-inhibit',
        arguments: <String>[
          '--what=sleep:handle-lid-switch',
          '--who=Alera',
          '--why=Agents are working',
          '--mode=block',
          'tail',
          '--pid=${processId ?? pid}',
          '-f',
          '/dev/null',
        ],
        supportedPlatform: 'linux',
        label: 'Linux lid sleep assertion',
        isUnavailableError: _isMissingExecutable,
        isUnavailableExitCode: (code) => code == 127,
      );
}

class WindowsSystemSleepAssertion({
  String? platform,
  WindowsExecutionStateSetter? setExecutionState,
  Logger? logger,
}) implements AgentAwakeAssertion {
  this
    : _platform = platform ?? Platform.operatingSystem,
      _setExecutionState = setExecutionState ?? _setThreadExecutionState,
      _logger = logger ?? Logger('AgentAwakeAssertion');

  final String _platform;
  final WindowsExecutionStateSetter _setExecutionState;
  final Logger _logger;
  bool _active = false;

  @override
  Future<void> start(String reason) async {
    if (_platform != 'windows' || _active) {
      return;
    }
    if (_trySetExecutionState(_windowsAwakeExecutionState, 'start', reason)) {
      _active = true;
    }
  }

  @override
  Future<void> stop(String reason) async {
    if (_platform != 'windows' || !_active) {
      return;
    }
    _active = false;
    _trySetExecutionState(_windowsExecutionStateContinuous, 'stop', reason);
  }

  @override
  Future<void> dispose() {
    return stop('dispose');
  }

  bool _trySetExecutionState(int flags, String action, String reason) {
    try {
      final previousState = _setExecutionState(flags);
      if (previousState != 0) {
        return true;
      }
      _logger.warning(
        '[agent-awake] Windows system sleep assertion returned 0 while trying to $action: $reason',
      );
    } catch (error, stackTrace) {
      _logger.warning(
        '[agent-awake] failed to $action Windows system sleep assertion: $reason',
        error,
        stackTrace,
      );
    }
    return false;
  }
}

class _ProcessBackedAwakeAssertion({
  required final ProcessRunner processRunner,
  required final String executable,
  required final List<String> arguments,
  required final String supportedPlatform,
  required final String label,
  required final Duration retryDelay,
  DateTime Function()? now,
  Logger? logger,
  String? platform,
  bool Function(Object error)? isUnavailableError,
  bool Function(int exitCode)? isUnavailableExitCode,
}) implements AgentAwakeAssertion {
  this
    : _now = now ?? (() => DateTime.now().toUtc()),
      _logger = logger ?? Logger('AgentAwakeAssertion'),
      _platform = platform ?? Platform.operatingSystem,
      _isUnavailableError = isUnavailableError ?? ((_) => false),
      _isUnavailableExitCode = isUnavailableExitCode ?? ((_) => false);

  final DateTime Function() _now;
  final Logger _logger;
  final String _platform;
  final bool Function(Object error) _isUnavailableError;
  final bool Function(int exitCode) _isUnavailableExitCode;

  StartedProcess? _child;
  DateTime? _retryNotBefore;
  Timer? _retryTimer;
  bool _unavailable = false;
  bool _desiredActive = false;
  bool _disposed = false;
  Future<void> _operationTail = Future<void>.value();
  String? _lastFailureKey;
  bool _warnedForLastFailure = false;
  final Set<StartedProcess> _intentionalStops = <StartedProcess>{};
  final Set<StartedProcess> _reportedFailures = <StartedProcess>{};

  @override
  Future<void> start(String reason) {
    if (_platform != supportedPlatform || _disposed) {
      return Future<void>.value();
    }
    _desiredActive = true;
    return _enqueue(() => _startNow(reason));
  }

  Future<void> _startNow(String reason) async {
    if (!_desiredActive || _disposed || _child != null || _unavailable) {
      return;
    }
    final retryNotBefore = _retryNotBefore;
    if (retryNotBefore != null && _now().isBefore(retryNotBefore)) {
      _scheduleRetry();
      return;
    }

    final StartedProcess child;
    try {
      child = await processRunner.start(executable, arguments);
    } catch (error) {
      _handleFailure('spawn-error', reason, error, 'spawn-error');
      return;
    }

    unawaited(child.stdout.drain<void>());
    unawaited(child.stderr.drain<void>());
    unawaited(
      child.exitCode
          .then<void>((exitCode) {
            _handleChildExit(child, exitCode, reason);
          })
          .catchError((Object error, StackTrace stackTrace) {
            _handleChildFailure(
              child,
              'exit-error:${error.runtimeType}',
              'exit-error',
              reason,
              error,
            );
          }),
    );
    if (!_desiredActive || _disposed) {
      _intentionalStops.add(child);
      _killChild(child, reason);
      return;
    }
    _child = child;
    _resetRetrySuppression();
    _resetFailureStreak();
  }

  @override
  Future<void> stop(String reason) {
    _desiredActive = false;
    _resetRetrySuppression();
    _resetFailureStreak();
    return _enqueue(() async => _stopNow(reason));
  }

  void _stopNow(String reason) {
    final child = _child;
    if (child == null) {
      return;
    }
    _child = null;
    _intentionalStops.add(child);
    _killChild(child, reason);
  }

  void _killChild(StartedProcess child, String reason) {
    try {
      child.kill();
    } catch (error, stackTrace) {
      _logger.warning(
        '[agent-awake] failed to stop $label: $reason',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() {
    if (_disposed) {
      return _operationTail;
    }
    _disposed = true;
    _desiredActive = false;
    _resetRetrySuppression();
    _resetFailureStreak();
    return _enqueue(() async => _stopNow('dispose'));
  }

  void _handleChildExit(StartedProcess child, int exitCode, String reason) {
    _handleChildFailure(
      child,
      'exit:$exitCode',
      'exit',
      reason,
      <String, Object?>{'exitCode': exitCode},
      exitCode: exitCode,
    );
  }

  void _handleChildFailure(
    StartedProcess child,
    String failureKey,
    String failureType,
    String reason,
    Object details, {
    int? exitCode,
  }) {
    if (_intentionalStops.remove(child)) {
      return;
    }
    if (!_reportedFailures.add(child)) {
      return;
    }
    if (identical(_child, child)) {
      _child = null;
    }
    _handleFailure(
      failureKey,
      reason,
      details,
      failureType,
      exitCode: exitCode,
    );
  }

  void _handleFailure(
    String failureKey,
    String reason,
    Object details,
    String failureType, {
    int? exitCode,
  }) {
    if (_isUnavailable(details, exitCode)) {
      _unavailable = true;
      _resetRetrySuppression();
      _logFailure('unavailable', reason, details, failureType);
      return;
    }
    _logFailure(failureKey, reason, details, failureType);
    if (!_desiredActive || _disposed) {
      return;
    }
    _retryNotBefore = _now().add(retryDelay);
    _scheduleRetry();
  }

  bool _isUnavailable(Object details, int? exitCode) {
    return _isUnavailableError(details) ||
        (exitCode != null && _isUnavailableExitCode(exitCode));
  }

  void _logFailure(
    String failureKey,
    String reason,
    Object details,
    String failureType,
  ) {
    final message =
        '[agent-awake] $label failed: reason=$reason failureType=$failureType details=$details';
    if (_lastFailureKey == failureKey && _warnedForLastFailure) {
      _logger.fine(message);
      return;
    }
    _lastFailureKey = failureKey;
    _warnedForLastFailure = true;
    _logger.warning(message);
  }

  void _scheduleRetry() {
    final retryNotBefore = _retryNotBefore;
    if (!_desiredActive ||
        _disposed ||
        retryNotBefore == null ||
        _retryTimer != null) {
      return;
    }
    final delay = retryNotBefore.difference(_now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _retryTimer = null;
      unawaited(start('$label retry'));
    });
  }

  void _resetRetrySuppression() {
    _retryNotBefore = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _resetFailureStreak() {
    _lastFailureKey = null;
    _warnedForLastFailure = false;
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

bool _isMissingExecutable(Object error) {
  return error is ProcessException && error.errorCode == 2;
}

// coverage:ignore-start
// Windows FFI binding cannot be exercised on non-Windows CI. The injectable
// WindowsExecutionStateSetter covers flag selection and failure handling.
int _setThreadExecutionState(int flags) {
  return _setThreadExecutionStateFunction(flags);
}

final _SetThreadExecutionStateDart _setThreadExecutionStateFunction =
    ffi.DynamicLibrary.open('kernel32.dll').lookupFunction<
      _SetThreadExecutionStateNative,
      _SetThreadExecutionStateDart
    >('SetThreadExecutionState');

typedef _SetThreadExecutionStateNative = ffi.Uint32 Function(ffi.Uint32 flags);
typedef _SetThreadExecutionStateDart = int Function(int flags);
// coverage:ignore-end
