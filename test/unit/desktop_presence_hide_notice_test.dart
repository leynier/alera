import 'dart:async';
import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence_coordinator.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tray hide notice', () {
    test('shows the notice once and marks it shown', () async {
      final backend = _RecordingPresenceBackend();
      final coordinator = _coordinator(backend);
      await _installTray(coordinator);
      var marks = 0;

      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );
      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );

      expect(backend.notices, hasLength(1));
      expect(backend.notices.single.title, trayHideNoticeTitle);
      expect(backend.notices.single.message, trayHideNoticeMessage);
      expect(marks, 1);
    });

    test('skips when already shown', () async {
      final backend = _RecordingPresenceBackend();
      final coordinator = _coordinator(backend);
      await _installTray(coordinator);
      var marks = 0;

      await coordinator.announceHiddenToTray(
        alreadyShown: true,
        markShown: () async {
          marks += 1;
        },
      );

      expect(backend.notices, isEmpty);
      expect(marks, 0);
    });

    test('skips when the tray is not installed', () async {
      final backend = _RecordingPresenceBackend();
      final coordinator = _coordinator(backend);
      var marks = 0;

      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );

      expect(backend.notices, isEmpty);
      expect(marks, 0);
    });

    test('does not mark when the shell refuses', () async {
      final backend = _RecordingPresenceBackend()..result = false;
      final coordinator = _coordinator(backend);
      await _installTray(coordinator);
      var marks = 0;

      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );
      expect(marks, 0);
      expect(backend.notices, hasLength(1));

      backend.result = true;
      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );

      expect(marks, 1);
      expect(backend.notices, hasLength(2));
    });

    test('logs and retries after a backend error', () async {
      final backend = _RecordingPresenceBackend()
        ..error = StateError('shell refused');
      final logger = Logger.detached('hide-notice');
      final records = <LogRecord>[];
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final coordinator = _coordinator(backend, logger: logger);
      await _installTray(coordinator);
      var marks = 0;

      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );

      expect(marks, 0);
      expect(records.single.message, 'failed to show tray notice');

      backend.error = null;
      await coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );

      expect(marks, 1);
      expect(backend.notices, hasLength(2));
    });

    test('ignores a second close while the first notice is pending', () async {
      final gate = Completer<bool>();
      final backend = _RecordingPresenceBackend()..pending = gate.future;
      final coordinator = _coordinator(backend);
      await _installTray(coordinator);
      var marks = 0;

      final first = coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );
      final second = coordinator.announceHiddenToTray(
        alreadyShown: false,
        markShown: () async {
          marks += 1;
        },
      );
      await Future.pause(.zero);

      expect(backend.notices, hasLength(1));
      gate.complete(true);
      await Future.wait(<Future<void>>[first, second]);

      expect(marks, 1);
      expect(backend.notices, hasLength(1));
    });
  });
}

Future<void> _installTray(DesktopPresenceCoordinator coordinator) {
  return coordinator.apply(
    const DesktopPresenceSnapshot(
      trayVisible: true,
      tooltip: 'Alera',
      badgeCount: 0,
    ),
  );
}

DesktopPresenceCoordinator _coordinator(
  _RecordingPresenceBackend backend, {
  Logger? logger,
}) {
  final window = _IdleWindow();
  return DesktopPresenceCoordinator(
    backend: backend,
    window: window,
    lifecycle: AppWindowLifecycleCoordinator(
      repository: _MemoryWindowStateRepository(),
      window: window,
      saveDebounce: .zero,
    ),
    logger: logger,
  );
}

class _Notice {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;
}

class _RecordingPresenceBackend implements DesktopPresenceBackend {
  final List<_Notice> notices = <_Notice>[];
  bool result = true;
  Object? error;
  Future<bool>? pending;

  @override
  void listen({
    required VoidCallback onShow,
    required VoidCallback onQuit,
    void Function(bool installed)? onInstallationChanged,
  }) {}

  @override
  Future<void> apply(DesktopPresenceSnapshot snapshot) async {}

  @override
  Future<void> destroy() async {}

  @override
  Future<bool> showTrayNotice({
    required String title,
    required String message,
  }) {
    notices.add(_Notice(title: title, message: message));
    final failure = error;
    if (failure != null) {
      return Future<bool>.error(failure);
    }
    return pending ?? Future<bool>.value(result);
  }
}

class _MemoryWindowStateRepository implements AppWindowStateRepository {
  @override
  Future<void> clear() async {}

  @override
  Future<AppWindowState?> load() async => null;

  @override
  Future<void> save(AppWindowState state) async {}
}

class _IdleWindow implements AppWindowController {
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];

  @override
  void addListener(AppWindowEventListener listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(AppWindowEventListener listener) {
    listeners.remove(listener);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> destroy() async {}

  @override
  Future<void> focus() async {}

  @override
  Future<Rect> getBounds() async => const .fromLTWH(0, 0, 800, 600);

  @override
  Future<void> hide() async {}

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isMinimized() async => false;

  @override
  Future<bool> isVisible() async => true;

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
  Future<void> show() async {}
}
