import 'dart:async';

// The public constructor keeps descriptive callback names while initializing
// private state fields with the corresponding values.
// ignore_for_file: prefer_initializing_formals

typedef EditorAutosaveTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

/// Schedules one trailing autosave for a dirty editor and keeps failures
/// paused until an explicit user action resumes it.
class EditorAutosaveController({
  required bool enabled,
  required Duration debounce,
  required this._isDirty,
  required this._isReady,
  required this._save,
  required this._onError,
  EditorAutosaveTimerFactory? scheduleTimer,
}) {
  this
    : _enabled = enabled,
      _debounce = debounce,
      _scheduleTimer =
          scheduleTimer ?? ((delay, callback) => Timer(delay, callback));

  bool _enabled;
  Duration _debounce;
  final bool Function() _isDirty;
  final bool Function() _isReady;
  final Future<void> Function() _save;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final EditorAutosaveTimerFactory _scheduleTimer;
  Timer? _timer;
  var _saveInFlight = false;
  var _paused = false;
  var _disposed = false;
  var _generation = 0;

  bool get isPaused => _paused;

  void updateSettings({required bool enabled, required Duration debounce}) {
    if (_disposed) {
      return;
    }
    final wasEnabled = _enabled;
    final debounceChanged = _debounce != debounce;
    _enabled = enabled;
    _debounce = debounce;
    if (!enabled) {
      _cancelTimer();
      _paused = false;
      return;
    }
    if (!wasEnabled) {
      _paused = false;
    }
    if (_paused) {
      return;
    }
    if (debounceChanged && _timer != null) {
      _scheduleIfEligible();
      return;
    }
    notifyStateChanged();
  }

  /// Starts or resets the trailing debounce after editor text changes.
  void notifyTextChanged() {
    if (_disposed || !_enabled || _paused) {
      return;
    }
    _cancelTimer();
    _scheduleIfEligible();
  }

  /// Re-evaluates a pending save after loading or another save completes.
  void notifyStateChanged() {
    if (_disposed || _timer != null || _saveInFlight) {
      return;
    }
    _scheduleIfEligible();
  }

  /// Cancels a pending timer without pausing future autosaves.
  void cancelPending() {
    if (_disposed) {
      return;
    }
    _cancelTimer();
  }

  /// Pauses automatic attempts until [resume] or a settings toggle resumes it.
  void pause() {
    if (_disposed) {
      return;
    }
    _paused = true;
    _cancelTimer();
  }

  void resume() {
    if (_disposed) {
      return;
    }
    _paused = false;
    notifyStateChanged();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleIfEligible() {
    if (_disposed ||
        !_enabled ||
        _paused ||
        _saveInFlight ||
        !_isDirty() ||
        !_isReady()) {
      return;
    }
    final generation = ++_generation;
    _timer?.cancel();
    _timer = _scheduleTimer(_debounce, () {
      if (_disposed || generation != _generation) {
        return;
      }
      _timer = null;
      if (!_isDirty() || !_isReady()) {
        return;
      }
      _saveInFlight = true;
      unawaited(_runSave());
    });
  }

  void _cancelTimer() {
    _generation += 1;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _runSave() async {
    try {
      await _save();
    } catch (error, stackTrace) {
      if (!_disposed && _enabled) {
        _paused = true;
        _cancelTimer();
        _onError(error, stackTrace);
      }
    } finally {
      _saveInFlight = false;
      if (!_disposed && !_paused) {
        notifyStateChanged();
      }
    }
  }
}
