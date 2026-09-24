import 'dart:async';
import 'dart:ui';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence_coordinator.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence_providers.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:alera/src/features/settings/application/runtime_settings_changes.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_providers.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disposing desktop presence sync unbinds the hide notice', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    final warnings = <String>[];
    final logger = Logger('DesktopPresenceSyncDisposeTest');
    final subscription = logger.onRecord.listen((record) {
      if (record.level >= Level.WARNING) {
        warnings.add(record.message);
      }
    });
    addTearDown(subscription.cancel);

    final window = _RecordingWindow();
    final lifecycle = AppWindowLifecycleCoordinator(
      repository: _MemoryWindowStateRepository(),
      window: window,
      saveDebounce: Duration.zero,
      logger: logger,
    );
    final backend = _RecordingPresenceBackend();
    final coordinator = DesktopPresenceCoordinator(
      backend: backend,
      window: window,
      lifecycle: lifecycle,
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          _MemorySettingsRepository(),
        ),
        runtimeSettingsChangesProvider.overrideWith(
          (ref) => const Stream<void>.empty(),
        ),
        workbenchControllerProvider.overrideWithValue(const WorkbenchState()),
        agentStatusControllerProvider.overrideWithValue(
          const <String, AgentStatusEntry>{},
        ),
        appWindowLifecycleCoordinatorProvider.overrideWithValue(lifecycle),
        desktopPresenceCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );

    container.read(desktopPresenceSyncProvider);
    await lifecycle.start();
    await _waitUntil(() => coordinator.trayInstalled);

    window.emitClose();
    await lifecycle.waitForPendingHide();
    await _waitUntil(
      () =>
          backend.notices.length == 1 &&
          container
              .read(settingsControllerProvider)
              .general
              .trayHideNoticeShown,
    );

    container.dispose();

    window.emitClose();
    await lifecycle.waitForPendingHide();
    await Future.pause(const Duration(milliseconds: 1));

    expect(backend.notices, hasLength(1));
    expect(backend.notices.single.title, trayHideNoticeTitle);
    expect(window.hideCalls, 2);
    expect(window.destroyCalls, 0);
    expect(warnings, isEmpty);
  });
}

Future<void> _waitUntil(bool Function() ready) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (ready()) {
      return;
    }
    await Future.pause(const Duration(milliseconds: 1));
  }
  fail('timed out waiting for desktop presence sync');
}

final class _MemorySettingsRepository implements SettingsRepository {
  AleraSettings stored = AleraSettings.defaults;

  @override
  Future<AleraSettings> load() async => stored;

  @override
  Future<void> save(AleraSettings settings) async {
    stored = settings;
  }
}

final class _MemoryWindowStateRepository implements AppWindowStateRepository {
  @override
  Future<void> clear() async {}

  @override
  Future<AppWindowState?> load() async => null;

  @override
  Future<void> save(AppWindowState state) async {}
}

final class _RecordingWindow implements AppWindowController {
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];
  int destroyCalls = 0;
  int hideCalls = 0;
  bool visible = true;

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
  Future<void> focus() async {}

  @override
  Future<Rect> getBounds() async => const .fromLTWH(0, 0, 800, 600);

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
  Future<bool> isMinimized() async => false;

  @override
  Future<bool> isVisible() async => visible;

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

final class _Notice {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;
}

final class _RecordingPresenceBackend implements DesktopPresenceBackend {
  final List<_Notice> notices = <_Notice>[];

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
  }) async {
    notices.add(_Notice(title: title, message: message));
    return true;
  }
}
