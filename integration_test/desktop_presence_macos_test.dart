import 'dart:io';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/features/app_window/infra/window_manager_app_window_controller.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence_coordinator.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'macOS startup registers tray and badge and closing hides the window',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      await windowManager.ensureInitialized();
      final window = WindowManagerAppWindowController();
      final repository = _MemoryWindowStateRepository();
      final lifecycle = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        // A regression must fail the test instead of terminating its runner.
        closeGate: () async => false,
      );
      final backend = MethodChannelDesktopPresenceBackend();
      final presence = DesktopPresenceCoordinator(
        backend: backend,
        window: window,
        lifecycle: lifecycle,
      );
      addTearDown(() async {
        await window.show();
        await presence.destroy();
        await lifecycle.stop();
      });
      presence.start();
      lifecycle.bindHideOnClose(() => presence.trayInstalled);
      await lifecycle.start();
      await window.show();
      expect(await window.isVisible(), isTrue);

      await presence.apply(
        const DesktopPresenceSnapshot(
          trayVisible: true,
          tooltip: 'Alera desktop presence test',
          badgeCount: 3,
        ),
      );
      expect(presence.trayInstalled, isTrue);

      await window.close();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (await window.isVisible() && DateTime.now().isBefore(deadline)) {
        await Future.pause(const Duration(milliseconds: 20));
      }
      await lifecycle.waitForPendingHide();
      expect(await window.isVisible(), isFalse);
      expect(repository.state, isNotNull);
      expect(lifecycle.isQuitting, isFalse);

      // Removing the tray must restore the hidden window before removing the
      // user's way back into the app, and must clear the Dock badge.
      await presence.apply(
        const DesktopPresenceSnapshot(
          trayVisible: false,
          tooltip: '',
          badgeCount: 0,
        ),
      );
      expect(presence.trayInstalled, isFalse);
      expect(await window.isVisible(), isTrue);
    },
    skip: !Platform.isMacOS,
  );
}

class _MemoryWindowStateRepository implements AppWindowStateRepository {
  AppWindowState? state;

  @override
  Future<AppWindowState?> load() async => state;

  @override
  Future<void> save(AppWindowState state) async => this.state = state;

  @override
  Future<void> clear() async => state = null;
}
