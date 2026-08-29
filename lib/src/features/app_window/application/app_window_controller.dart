import 'dart:async';
import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:logging/logging.dart';

abstract class AppWindowEventListener {
  void onWindowClose() {}

  void onWindowMaximize() {}

  void onWindowUnmaximize() {}

  void onWindowMinimize() {}

  void onWindowRestore() {}

  void onWindowResize() {}

  void onWindowResized() {}

  void onWindowMove() {}

  void onWindowMoved() {}

  void onWindowEnterFullScreen() {}

  void onWindowLeaveFullScreen() {}
}

abstract interface class AppWindowController {
  void addListener(AppWindowEventListener listener);

  void removeListener(AppWindowEventListener listener);

  Future<void> setTitle(String title);

  Future<Rect> getBounds();

  Future<void> setBounds(Rect bounds);

  Future<bool> isMaximized();

  Future<void> maximize();

  Future<bool> isFullScreen();

  Future<void> setFullScreen(bool value);

  Future<bool> isMinimized();

  Future<void> hide();

  Future<void> show();

  Future<void> restore();

  Future<void> focus();

  Future<bool> isVisible();

  Future<void> setPreventClose(bool value);

  /// Requests a user-initiated window close (system close path).
  ///
  /// When prevent-close is enabled, this should emit the close event so the
  /// lifecycle coordinator can flush state and destroy the window.
  Future<void> close();

  Future<void> destroy();
}

abstract interface class AppWindowDisplayProvider {
  Future<List<Rect>> visibleDisplayBounds();
}

abstract interface class AppWindowCloseStrategy {
  Future<void> close(AppWindowController window);
}

final class DestroyAppWindowCloseStrategy implements AppWindowCloseStrategy {
  const DestroyAppWindowCloseStrategy();

  @override
  Future<void> close(AppWindowController window) async {
    await window.setPreventClose(false);
    await window.destroy();
  }
}

class AppWindowRestorer {
  const AppWindowRestorer({
    required AppWindowStateRepository repository,
    required AppWindowController window,
    required AppWindowDisplayProvider displays,
  }) : this._(repository: repository, window: window, displays: displays);

  const AppWindowRestorer._({
    required this._repository,
    required this._window,
    required this._displays,
  });

  final AppWindowStateRepository _repository;
  final AppWindowController _window;
  final AppWindowDisplayProvider _displays;

  Future<void> restore() async {
    final state = await _repository.load();
    if (state == null) {
      return;
    }
    final normalBounds = state.normalBounds?.toRect();
    if (normalBounds != null) {
      final clamped = clampWindowBoundsToVisibleDisplays(
        normalBounds,
        await _displays.visibleDisplayBounds(),
      );
      if (clamped != null) {
        await _window.setBounds(clamped);
      }
    }
    if (state.fullScreen) {
      await _window.setFullScreen(true);
      return;
    }
    if (state.maximized) {
      await _window.maximize();
    }
  }
}

class AppWindowLifecycleCoordinator extends AppWindowEventListener {
  AppWindowLifecycleCoordinator({
    required AppWindowStateRepository repository,
    required AppWindowController window,
    AppWindowCloseStrategy closeStrategy =
        const DestroyAppWindowCloseStrategy(),
    Duration saveDebounce = const Duration(milliseconds: 350),
    Future<bool> Function()? closeGate,
    bool Function()? hideOnClose,
    Logger? logger,
  }) : this._(
         repository: repository,
         window: window,
         closeStrategy: closeStrategy,
         saveDebounce: saveDebounce,
         closeGate: closeGate,
         hideOnClose: hideOnClose,
         logger: logger ?? Logger('AppWindowLifecycleCoordinator'),
       );

  AppWindowLifecycleCoordinator._({
    required this._repository,
    required this._window,
    required this._closeStrategy,
    required this._saveDebounce,
    required this._closeGate,
    required this._hideOnClose,
    required this._logger,
  });

  final AppWindowStateRepository _repository;
  final AppWindowController _window;
  final AppWindowCloseStrategy _closeStrategy;
  final Duration _saveDebounce;
  Future<bool> Function()? _closeGate;
  bool Function()? _hideOnClose;
  final Logger _logger;

  AppWindowState? _lastState;
  Timer? _debounceTimer;
  Future<void> _saveQueue = Future<void>.value();
  bool _started = false;
  bool _closing = false;
  bool _closeCommitted = false;
  bool _closed = false;
  bool _quitting = false;
  Future<void>? _hideFuture;

  /// Optional gate invoked before the window is destroyed. Return `false` to
  /// cancel the close (for example when the user declines force-stopping the
  /// runtime). Replaces any previous gate.
  void bindCloseGate(Future<bool> Function()? closeGate) {
    _closeGate = closeGate;
  }

  /// When this returns true, a user close hides the window instead of
  /// destroying the process. Quit still goes through [requestQuit].
  void bindHideOnClose(bool Function()? hideOnClose) {
    _hideOnClose = hideOnClose;
  }

  /// True while a committed quit is in progress, so hide-on-close cannot
  /// swallow a tray or app-menu Quit.
  bool get isQuitting => _quitting;

  Future<void> start() async {
    if (_started || _closed) {
      return;
    }
    _started = true;
    _window.addListener(this);
    await _window.setPreventClose(true);
    _lastState = await _repository.load();
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _window.removeListener(this);
    _started = false;
    if (!_closing && !_closed) {
      await _window.setPreventClose(false);
    }
  }

  Future<void> flush() async {
    if (_closed) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _saveCurrentState();
  }

  @override
  void onWindowClose() {
    if (_closing || _closed) {
      return;
    }
    if (!_quitting && (_hideOnClose?.call() ?? false)) {
      _hideFuture ??= _hideInsteadOfDestroy();
      return;
    }
    _closing = true;
    unawaited(_flushAndDestroy());
  }

  /// Commits a real process exit even when hide-on-close is enabled.
  Future<void> requestQuit() async {
    if (_closing || _closed || _quitting) {
      return;
    }
    _quitting = true;
    _closing = true;
    final hide = _hideFuture;
    if (hide != null) {
      await hide;
    }
    if (_closed) {
      return;
    }
    await _flushAndDestroy();
  }

  Future<void> _hideInsteadOfDestroy() async {
    try {
      await flush();
      if (_quitting || _closing) {
        return;
      }
      try {
        await _window.hide();
      } catch (error, stackTrace) {
        _logWarningIfActive('failed to hide app window', error, stackTrace);
      }
    } catch (error, stackTrace) {
      _logWarningIfActive(
        'failed to flush app window state on hide',
        error,
        stackTrace,
      );
    } finally {
      _hideFuture = null;
    }
  }

  void _resetQuitAttempt() {
    _closing = false;
    _quitting = false;
    _hideFuture = null;
  }

  @override
  void onWindowMaximize() => _saveSoon(immediate: true);

  @override
  void onWindowUnmaximize() => _saveSoon(immediate: true);

  @override
  void onWindowMinimize() => _saveSoon();

  @override
  void onWindowRestore() => _saveSoon(immediate: true);

  @override
  void onWindowResize() => _saveSoon();

  @override
  void onWindowResized() => _saveSoon(immediate: true);

  @override
  void onWindowMove() => _saveSoon();

  @override
  void onWindowMoved() => _saveSoon(immediate: true);

  @override
  void onWindowEnterFullScreen() => _saveSoon(immediate: true);

  @override
  void onWindowLeaveFullScreen() => _saveSoon(immediate: true);

  void _saveSoon({bool immediate = false}) {
    if (!_started || _closing || _closed) {
      return;
    }
    _debounceTimer?.cancel();
    if (immediate) {
      unawaited(_saveCurrentState());
      return;
    }
    _debounceTimer = Timer(_saveDebounce, () {
      _debounceTimer = null;
      unawaited(_saveCurrentState());
    });
  }

  Future<void> _flushAndDestroy() async {
    try {
      final gate = _closeGate;
      if (gate != null) {
        final allowClose = await gate();
        if (!allowClose) {
          _resetQuitAttempt();
          return;
        }
      }
    } catch (error, stackTrace) {
      // Logging listeners are synchronous and may request another close.
      _resetQuitAttempt();
      _logWarningIfActive('app window close gate failed', error, stackTrace);
      return;
    }
    _closeCommitted = true;
    try {
      await flush();
    } catch (error, stackTrace) {
      _logWarningIfActive(
        'failed to flush app window state on close',
        error,
        stackTrace,
      );
    } finally {
      await _finishClose();
    }
  }

  /// Marks teardown complete and destroys the window at most once.
  Future<void> _finishClose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _closing = true;
    _started = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _window.removeListener(this);
    await _closeStrategy.close(_window);
  }

  void _logWarningIfActive(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    // Desktop stdio may already be invalid once a committed close starts.
    if (_closeCommitted || _closed) {
      return;
    }
    _logger.warning(message, error, stackTrace);
  }

  Future<void> _saveCurrentState() {
    _saveQueue = _saveQueue
        .then((_) async {
          if (_closed) {
            return;
          }
          final state = await _captureCurrentState();
          if (state == null || state == _lastState) {
            return;
          }
          _lastState = state;
          await _repository.save(state);
        })
        .catchError((Object error, StackTrace stackTrace) {
          _logWarningIfActive(
            'failed to save app window state',
            error,
            stackTrace,
          );
        });
    return _saveQueue;
  }

  Future<AppWindowState?> _captureCurrentState() async {
    if (await _window.isMinimized()) {
      return null;
    }
    final fullScreen = await _window.isFullScreen();
    final maximized = fullScreen ? false : await _window.isMaximized();
    final previousBounds = _lastState?.normalBounds;
    final normalBounds = maximized || fullScreen
        ? previousBounds
        : AppWindowBounds.fromRect(await _window.getBounds());
    return AppWindowState(
      normalBounds: normalBounds,
      maximized: maximized,
      fullScreen: fullScreen,
    );
  }
}
