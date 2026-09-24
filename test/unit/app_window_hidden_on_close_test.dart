import 'dart:async';
import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hidden on close', () {
    test('notifies hidden-on-close after a successful hide', () async {
      final window = _RecordingWindow();
      final coordinator = _coordinator(window);
      var notices = 0;
      coordinator.bindHiddenOnClose(() => notices += 1);
      await coordinator.start();

      window.emitClose();
      await coordinator.waitForPendingHide();

      expect(notices, 1);
      expect(window.hideCalls, 1);
      expect(window.destroyCalls, 0);
    });

    test('does not notify hidden-on-close when hide fails', () async {
      final window = _RecordingWindow()..hideError = StateError('hide failed');
      final coordinator = _coordinator(window);
      var notices = 0;
      coordinator.bindHiddenOnClose(() => notices += 1);
      await coordinator.start();

      window.emitClose();
      await coordinator.waitForPendingHide();

      expect(notices, 0);
      expect(window.destroyCalls, 0);
    });

    test(
      'does not notify hidden-on-close when a quit starts during the hide',
      () async {
        final hideStarted = Completer<void>();
        final finishHide = Completer<void>();
        final window = _RecordingWindow()
          ..hideStarted = hideStarted
          ..hideBarrier = finishHide.future;
        final coordinator = _coordinator(window);
        var notices = 0;
        coordinator.bindHiddenOnClose(() => notices += 1);
        await coordinator.start();

        window.emitClose();
        await hideStarted.future;

        final quit = coordinator.requestQuit();
        await Future.pause(.zero);
        finishHide.complete();
        await quit;

        expect(notices, 0);
      },
    );

    test('requestQuit never notifies hidden-on-close', () async {
      final window = _RecordingWindow();
      final coordinator = _coordinator(window);
      var notices = 0;
      coordinator.bindHiddenOnClose(() => notices += 1);
      await coordinator.start();

      await coordinator.requestQuit();

      expect(notices, 0);
      expect(window.destroyCalls, 1);
      expect(window.hideCalls, 0);
    });
  });
}

AppWindowLifecycleCoordinator _coordinator(_RecordingWindow window) {
  return AppWindowLifecycleCoordinator(
    repository: _MemoryWindowStateRepository(),
    window: window,
    saveDebounce: .zero,
    hideOnClose: () => true,
  );
}

class _MemoryWindowStateRepository implements AppWindowStateRepository {
  @override
  Future<void> clear() async {}

  @override
  Future<AppWindowState?> load() async => null;

  @override
  Future<void> save(AppWindowState state) async {}
}

class _RecordingWindow implements AppWindowController {
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];
  int destroyCalls = 0;
  int hideCalls = 0;
  bool visible = true;
  Object? hideError;
  Completer<void>? hideStarted;
  Future<void>? hideBarrier;

  void emitClose() {
    for (final listener in List<AppWindowEventListener>.from(listeners)) {
      listener.onWindowClose();
    }
  }

  @override
  void addListener(AppWindowEventListener listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(AppWindowEventListener listener) {
    listeners.remove(listener);
  }

  @override
  Future<void> close() async => emitClose();

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }

  @override
  Future<Rect> getBounds() async => const .fromLTWH(0, 0, 800, 600);

  @override
  Future<void> hide() async {
    hideStarted?.complete();
    await hideBarrier;
    if (hideError != null) {
      throw hideError!;
    }
    hideCalls += 1;
    visible = false;
  }

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isMinimized() async => false;

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<void> focus() async {}

  @override
  Future<void> maximize() async {}

  @override
  Future<void> restore() async {}

  @override
  Future<void> setBounds(Rect bounds) async {}

  @override
  Future<void> setFullScreen(bool value) async {}

  @override
  Future<void> setPreventClose(bool value) async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> show() async {
    visible = true;
  }
}
