import 'dart:async';

import 'package:alera/src/features/desktop_presence/application/desktop_presence_coordinator.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopPresenceCoordinator', () {
    test('applies snapshots and shows the window from the tray', () async {
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository(),
        window: window,
        saveDebounce: .zero,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 2,
        ),
      );
      expect(backend.applied.single.badgeCount, 2);

      window.visible = false;
      backend.onShow?.call();
      await Future.pause(.zero);
      expect(window.showCalls, 1);
      expect(window.focusCalls, 1);

      backend.onQuit?.call();
      await Future.pause(.zero);
      expect(window.destroyCalls, 1);
    });

    test('shows a hidden window before removing the tray', () async {
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository(),
        window: window,
        saveDebounce: .zero,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      window.visible = false;

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: false,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );

      expect(window.showCalls, 1);
      expect(window.focusCalls, 1);
      expect(window.visible, isTrue);
      expect(backend.applied, hasLength(2));
      expect(backend.applied.last.trayVisible, isFalse);
    });

    test('keeps the tray when showing a hidden window fails', () async {
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow()..showFails = true;
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository(),
        window: window,
        saveDebounce: .zero,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 1,
        ),
      );
      window.visible = false;

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: false,
          tooltip: 'Alera',
          badgeCount: 1,
        ),
      );
      expect(backend.applied, hasLength(1));
      expect(backend.applied.single.trayVisible, isTrue);
      expect(window.visible, isFalse);

      window.showFails = false;
      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: false,
          tooltip: 'Alera',
          badgeCount: 1,
        ),
      );
      expect(window.visible, isTrue);
      expect(backend.applied, hasLength(2));
      expect(backend.applied.last.trayVisible, isFalse);
    });

    test('waits for an in-flight hide before removing the tray', () async {
      final saveStarted = Completer<void>();
      final finishSave = Completer<void>();
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository()
          ..saveStarted = saveStarted
          ..saveBarrier = finishSave.future,
        window: window,
        saveDebounce: .zero,
        hideOnClose: () => true,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      expect(coordinator.trayInstalled, isTrue);

      window.emitClose();
      await saveStarted.future;
      expect(window.hideCalls, 0);
      expect(window.visible, isTrue);

      final removeTray = coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: false,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      await Future.pause(.zero);
      expect(backend.applied, hasLength(1));
      expect(window.showCalls, 0);

      finishSave.complete();
      await removeTray;

      expect(window.hideCalls, 1);
      expect(window.showCalls, 1);
      expect(window.visible, isTrue);
      expect(backend.applied, hasLength(2));
      expect(backend.applied.last.trayVisible, isFalse);
      expect(coordinator.trayInstalled, isFalse);
    });

    test('does not hide while tray removal is in progress', () async {
      final applyStarted = Completer<void>();
      final finishApply = Completer<void>();
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository(),
        window: window,
        saveDebounce: .zero,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();
      lifecycle.bindHideOnClose(() => coordinator.trayInstalled);

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      expect(coordinator.trayInstalled, isTrue);
      backend.applyStarted = applyStarted;
      backend.applyBarrier = finishApply.future;

      final removeTray = coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: false,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      await applyStarted.future;
      expect(coordinator.trayInstalled, isFalse);

      window.emitClose();
      await Future.pause(.zero);
      expect(window.hideCalls, 0);

      finishApply.complete();
      await removeTray;
      expect(window.hideCalls, 0);
      expect(coordinator.trayInstalled, isFalse);
    });

    test('shows a hidden window when tray installation is lost', () async {
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository(),
        window: window,
        saveDebounce: .zero,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      window.visible = false;
      backend.onInstallationChanged?.call(false);
      await Future.pause(.zero);

      expect(coordinator.trayInstalled, isFalse);
      expect(window.showCalls, 1);
      expect(window.visible, isTrue);
    });

    test('does not show when tray reinstall succeeds immediately', () async {
      final backend = _RecordingPresenceBackend();
      final window = _RecordingWindow();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: _MemoryWindowStateRepository(),
        window: window,
        saveDebounce: .zero,
      );
      await lifecycle.start();
      final coordinator = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      coordinator.start();

      await coordinator.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera',
          badgeCount: 0,
        ),
      );
      window.visible = false;
      backend.onInstallationChanged?.call(false);
      backend.onInstallationChanged?.call(true);
      await Future.pause(.zero);

      expect(coordinator.trayInstalled, isTrue);
      expect(window.showCalls, 0);
      expect(window.visible, isFalse);
    });
  });
}

class _RecordingPresenceBackend implements DesktopPresenceBackend {
  VoidCallback? onShow;
  VoidCallback? onQuit;
  void Function(bool installed)? onInstallationChanged;
  final List<DesktopPresenceSnapshot> applied = <DesktopPresenceSnapshot>[];
  int destroyCalls = 0;
  Completer<void>? applyStarted;
  Future<void>? applyBarrier;

  @override
  void listen({
    required VoidCallback onShow,
    required VoidCallback onQuit,
    void Function(bool installed)? onInstallationChanged,
  }) {
    this.onShow = onShow;
    this.onQuit = onQuit;
    this.onInstallationChanged = onInstallationChanged;
  }

  @override
  Future<void> apply(DesktopPresenceSnapshot snapshot) async {
    applyStarted?.complete();
    await applyBarrier;
    applied.add(snapshot);
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }
}

class _MemoryWindowStateRepository implements AppWindowStateRepository {
  AppWindowState? state;
  Completer<void>? saveStarted;
  Future<void>? saveBarrier;

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
    this.state = state;
  }
}

class _RecordingWindow implements AppWindowController {
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];
  int destroyCalls = 0;
  int showCalls = 0;
  int focusCalls = 0;
  int hideCalls = 0;
  bool visible = true;
  bool minimized = false;
  bool showFails = false;

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
  Future<void> close() async {
    for (final listener in List<AppWindowEventListener>.from(listeners)) {
      listener.onWindowClose();
    }
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }

  @override
  Future<Rect> getBounds() async => const Rect.fromLTWH(0, 0, 800, 600);

  @override
  Future<void> hide() async {
    hideCalls += 1;
    visible = false;
  }

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<void> maximize() async {}

  @override
  Future<void> restore() async {
    minimized = false;
  }

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
    showCalls += 1;
    if (showFails) {
      throw StateError('show failed');
    }
    visible = true;
  }

  @override
  Future<void> focus() async {
    focusCalls += 1;
  }
}
