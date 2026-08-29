import 'dart:async';
import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  group('AppWindowLifecycleCoordinator shutdown', () {
    test('resets close state before a gate failure is logged', () async {
      final repository = _RecordingStateRepository();
      final window = _RecordingWindowController();
      final logger = Logger.detached('close-gate-ordering');
      var gateCalls = 0;
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
        logger: logger,
        closeGate: () async {
          gateCalls += 1;
          if (gateCalls == 1) {
            throw StateError('quit gate failed');
          }
          return true;
        },
      );
      final subscription = logger.onRecord.listen((_) {
        window.emit((listener) => listener.onWindowClose());
      });
      addTearDown(subscription.cancel);
      await coordinator.start();

      window.emit((listener) => listener.onWindowClose());
      await _waitFor(() => window.destroyCalls == 1);

      expect(gateCalls, 2);
      expect(window.destroyCalls, 1);
      expect(window.preventCloseValues, <bool>[true, false]);
    });

    test('does not publish warnings during committed close', () async {
      final repository = _RecordingStateRepository()
        ..saveError = StateError('disk full');
      final window = _RecordingWindowController();
      final logger = Logger.detached('committed-close');
      final records = <LogRecord>[];
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
        logger: logger,
      );
      await coordinator.start();

      window.emit((listener) => listener.onWindowClose());
      await _waitFor(() => window.destroyCalls == 1);

      expect(records, isEmpty);
      expect(window.destroyCalls, 1);
      expect(window.preventCloseValues, <bool>[true, false]);
    });

    test('reports save failures while the close gate is pending', () async {
      final saveStarted = Completer<void>();
      final finishSave = Completer<void>();
      final gate = Completer<bool>();
      final repository = _RecordingStateRepository()
        ..saveStarted = saveStarted
        ..saveBarrier = finishSave.future
        ..saveError = StateError('disk full');
      final window = _RecordingWindowController();
      final logger = Logger.detached('pending-close');
      final records = <LogRecord>[];
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      var gateCalls = 0;
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
        logger: logger,
        closeGate: () {
          gateCalls += 1;
          return gate.future;
        },
      );
      await coordinator.start();

      window.emit((listener) => listener.onWindowResized());
      await saveStarted.future;
      window.emit((listener) => listener.onWindowClose());
      finishSave.complete();
      await _waitFor(() => records.isNotEmpty);
      gate.complete(false);
      await Future<void>.delayed(Duration.zero);

      expect(records.single.message, 'failed to save app window state');
      expect(window.destroyCalls, 0);
      window.emit((listener) => listener.onWindowClose());
      await _waitFor(() => gateCalls == 2);
    });

    test('hides the window when hide-on-close is bound', () async {
      final repository = _RecordingStateRepository();
      final window = _RecordingWindowController();
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
        hideOnClose: () => true,
      );
      await coordinator.start();

      window.emit((listener) => listener.onWindowClose());
      await _waitFor(() => window.hideCalls == 1);

      expect(window.destroyCalls, 0);
      expect(window.hideCalls, 1);
      expect(window.preventCloseValues, <bool>[true]);
    });

    test('requestQuit destroys even when hide-on-close is bound', () async {
      final repository = _RecordingStateRepository();
      final window = _RecordingWindowController();
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
        hideOnClose: () => true,
      );
      await coordinator.start();

      await coordinator.requestQuit();
      await _waitFor(() => window.destroyCalls == 1);

      expect(window.hideCalls, 0);
      expect(window.destroyCalls, 1);
      expect(window.preventCloseValues, <bool>[true, false]);
    });

    test(
      'requestQuit waits for an in-flight hide before the close gate',
      () async {
        final saveStarted = Completer<void>();
        final finishSave = Completer<void>();
        final gate = Completer<bool>();
        final repository = _RecordingStateRepository()
          ..saveStarted = saveStarted
          ..saveBarrier = finishSave.future;
        final window = _RecordingWindowController();
        var gateCalls = 0;
        final coordinator = AppWindowLifecycleCoordinator(
          repository: repository,
          window: window,
          saveDebounce: Duration.zero,
          hideOnClose: () => true,
          closeGate: () {
            gateCalls += 1;
            return gate.future;
          },
        );
        await coordinator.start();

        window.emit((listener) => listener.onWindowClose());
        window.emit((listener) => listener.onWindowClose());
        await saveStarted.future;
        expect(window.hideCalls, 0);
        expect(gateCalls, 0);

        final quit = coordinator.requestQuit();
        await Future<void>.delayed(Duration.zero);
        expect(gateCalls, 0);
        expect(window.hideCalls, 0);
        expect(window.destroyCalls, 0);

        finishSave.complete();
        await _waitFor(() => gateCalls == 1);
        expect(window.hideCalls, 0);

        gate.complete(false);
        await quit;
        expect(window.destroyCalls, 0);

        window.emit((listener) => listener.onWindowClose());
        await _waitFor(() => window.hideCalls == 1);
        expect(window.destroyCalls, 0);
      },
    );

    test('requestQuit finishes hide before opening the close gate', () async {
      final hideStarted = Completer<void>();
      final finishHide = Completer<void>();
      final gate = Completer<bool>();
      final window = _RecordingWindowController()
        ..hideStarted = hideStarted
        ..hideBarrier = finishHide.future;
      var gateCalls = 0;
      final coordinator = AppWindowLifecycleCoordinator(
        repository: _RecordingStateRepository(),
        window: window,
        saveDebounce: Duration.zero,
        hideOnClose: () => true,
        closeGate: () {
          gateCalls += 1;
          return gate.future;
        },
      );
      await coordinator.start();

      window.emit((listener) => listener.onWindowClose());
      await hideStarted.future;
      expect(gateCalls, 0);

      final quit = coordinator.requestQuit();
      await Future<void>.delayed(Duration.zero);
      expect(gateCalls, 0);
      expect(window.destroyCalls, 0);

      finishHide.complete();
      await _waitFor(() => gateCalls == 1);
      expect(window.hideCalls, 1);
      expect(window.visible, isFalse);

      gate.complete(false);
      await quit;
      expect(window.destroyCalls, 0);
    });

    test('closes once and ignores post-close state work', () async {
      final repository = _RecordingStateRepository();
      final window = _RecordingWindowController();
      final gate = Completer<bool>();
      var gateCalls = 0;
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
        closeGate: () {
          gateCalls += 1;
          return gate.future;
        },
      );
      await coordinator.start();

      window.emit((listener) => listener.onWindowClose());
      window.emit((listener) => listener.onWindowClose());
      gate.complete(true);
      await _waitFor(() => window.destroyCalls == 1);
      final savesAtClose = repository.saved.length;

      window.bounds = const Rect.fromLTWH(100, 120, 900, 600);
      window.emit((listener) => listener.onWindowResized());
      window.emit((listener) => listener.onWindowClose());
      await coordinator.flush();

      expect(gateCalls, 1);
      expect(window.destroyCalls, 1);
      expect(repository.saved, hasLength(savesAtClose));
      expect(window.preventCloseValues, <bool>[true, false]);
    });
  });
}

class _RecordingStateRepository implements AppWindowStateRepository {
  AppWindowState? state;
  Object? saveError;
  Completer<void>? saveStarted;
  Future<void>? saveBarrier;
  final List<AppWindowState> saved = <AppWindowState>[];

  @override
  Future<void> clear() async {
    state = null;
  }

  @override
  Future<AppWindowState?> load() async => state;

  @override
  Future<void> save(AppWindowState state) async {
    saveStarted?.complete();
    await saveBarrier;
    final error = saveError;
    if (error != null) {
      throw error;
    }
    this.state = state;
    saved.add(state);
  }
}

class _RecordingWindowController implements AppWindowController {
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];
  final List<bool> preventCloseValues = <bool>[];
  Rect bounds = const Rect.fromLTWH(20, 30, 800, 500);
  int destroyCalls = 0;
  int hideCalls = 0;
  int showCalls = 0;
  int focusCalls = 0;
  int restoreCalls = 0;
  bool visible = true;
  bool minimized = false;
  Completer<void>? hideStarted;
  Future<void>? hideBarrier;

  void emit(void Function(AppWindowEventListener listener) notify) {
    for (final listener in List<AppWindowEventListener>.from(listeners)) {
      notify(listener);
    }
  }

  @override
  void addListener(AppWindowEventListener listener) {
    listeners.add(listener);
  }

  @override
  Future<void> close() async {
    emit((listener) => listener.onWindowClose());
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }

  @override
  Future<void> hide() async {
    hideStarted?.complete();
    await hideBarrier;
    hideCalls += 1;
    visible = false;
  }

  @override
  Future<void> show() async {
    showCalls += 1;
    visible = true;
  }

  @override
  Future<void> restore() async {
    restoreCalls += 1;
    minimized = false;
  }

  @override
  Future<void> focus() async {
    focusCalls += 1;
  }

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<void> maximize() async {}

  @override
  void removeListener(AppWindowEventListener listener) {
    listeners.remove(listener);
  }

  @override
  Future<void> setBounds(Rect bounds) async {
    this.bounds = bounds;
  }

  @override
  Future<void> setFullScreen(bool value) async {}

  @override
  Future<void> setPreventClose(bool value) async {
    preventCloseValues.add(value);
  }

  @override
  Future<void> setTitle(String title) async {}
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not reached');
    }
    await Future<void>.delayed(Duration.zero);
  }
}
