import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('app menu actions', () {
    testWidgets('openAppMenuSettings opens the settings dialog', (
      tester,
    ) async {
      await _pumpActionHarness(
        tester,
        onPressed: (context, _) => openAppMenuSettings(context),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Application'), findsWidgets);
    });

    testWidgets('checkForUpdatesFromAppMenu runs check and shows toast', (
      tester,
    ) async {
      final updateController = _FakeUpdateController(
        AleraUpdateState(status: AleraUpdateStatus.idle, config: _config()),
      );
      final toastMessages = <String>[];
      final sub = AleraToast.stream.listen((data) {
        toastMessages.add(data.message);
      });
      addTearDown(sub.cancel);

      await _pumpActionHarness(
        tester,
        updateController: updateController,
        onPressed: (context, ref) => checkForUpdatesFromAppMenu(context, ref),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump();

      expect(updateController.checkForUpdatesCalls, 1);
      expect(toastMessages, <String>['Alera is up to date.']);
    });

    testWidgets('showAppMenuAbout opens the about dialog', (tester) async {
      await _pumpActionHarness(
        tester,
        onPressed: (context, _) => showAppMenuAbout(
          context,
          loadPackageInfo: () async => PackageInfo(
            appName: kAleraAppName,
            packageName: 'dev.leynier.alera',
            version: '1.2.3',
            buildNumber: '45',
          ),
        ),
      );

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(find.text(kAleraAppName), findsWidgets);
      expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('exitAppFromMenu closes the app window', (tester) async {
      final window = _FakeAppWindowController();
      await _pumpActionHarness(
        tester,
        window: window,
        onPressed: (_, ref) => exitAppFromMenu(ref),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();

      expect(window.closeCalls, 1);
    });
  });

  group('AleraAppMenuScope', () {
    testWidgets('shows Material menu bar items on Linux', (tester) async {
      await _withPlatform(TargetPlatform.linux, () async {
        await _pumpMenuScope(tester);

        expect(find.byType(MenuBar), findsOneWidget);
        expect(find.text(kAleraAppName), findsOneWidget);

        await tester.tap(find.text(kAleraAppName));
        await tester.pumpAndSettle();
        expect(find.text('Settings ...'), findsOneWidget);
        expect(find.text('Check for Updates ...'), findsOneWidget);
        expect(find.text('About $kAleraAppName'), findsOneWidget);
        expect(find.text('Exit'), findsOneWidget);
      });
    });

    testWidgets('shows Material menu bar items on Windows', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        await _pumpMenuScope(tester);

        expect(find.byType(MenuBar), findsOneWidget);
        expect(find.text('Check for Updates ...'), findsNothing);

        await tester.tap(find.text(kAleraAppName));
        await tester.pumpAndSettle();
        expect(find.text('Settings ...'), findsOneWidget);
        expect(find.text('Check for Updates ...'), findsOneWidget);
        expect(find.text('About $kAleraAppName'), findsOneWidget);
        expect(find.text('Exit'), findsOneWidget);
      });
    });

    testWidgets('uses PlatformMenuBar on macOS without in-window MenuBar', (
      tester,
    ) async {
      await _withPlatform(TargetPlatform.macOS, () async {
        await _pumpMenuScope(tester);

        expect(find.byType(PlatformMenuBar), findsOneWidget);
        expect(find.byType(MenuBar), findsNothing);
      });
    });
  });
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

Future<void> _pumpActionHarness(
  WidgetTester tester, {
  required FutureOr<void> Function(BuildContext context, WidgetRef ref)
  onPressed,
  _FakeUpdateController? updateController,
  _FakeAppWindowController? window,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraUpdateControllerProvider.overrideWith(
          () =>
              updateController ??
              _FakeUpdateController(
                AleraUpdateState(
                  status: AleraUpdateStatus.idle,
                  config: _config(),
                ),
              ),
        ),
        appWindowControllerProvider.overrideWithValue(
          window ?? _FakeAppWindowController(),
        ),
        settingsControllerProvider.overrideWith(
          () => _FakeSettingsController(AleraSettings.defaults),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              return TextButton(
                onPressed: () =>
                    unawaited(Future<void>.sync(() => onPressed(context, ref))),
                child: const Text('Run'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpMenuScope(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraUpdateControllerProvider.overrideWith(
          () => _FakeUpdateController(
            AleraUpdateState(status: AleraUpdateStatus.idle, config: _config()),
          ),
        ),
        appWindowControllerProvider.overrideWithValue(
          _FakeAppWindowController(),
        ),
        settingsControllerProvider.overrideWith(
          () => _FakeSettingsController(AleraSettings.defaults),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const AleraAppMenuScope(child: Scaffold(body: SizedBox.expand())),
      ),
    ),
  );
  await tester.pump();
}

AleraUpdateConfig _config() {
  return AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://example.com/releases'),
    channel: AleraUpdateChannel.stable,
    autoInstallEnabled: true,
    signedRelease: true,
  );
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}

class _FakeUpdateController extends AleraUpdateController {
  _FakeUpdateController(this._seed);

  final AleraUpdateState _seed;
  int checkForUpdatesCalls = 0;

  @override
  AleraUpdateState build() => _seed;

  @override
  Future<void> checkForUpdates() async {
    checkForUpdatesCalls += 1;
    state = state.copyWith(
      status: AleraUpdateStatus.notAvailable,
      message: 'Alera is up to date.',
    );
  }
}

class _FakeAppWindowController implements AppWindowController {
  int closeCalls = 0;

  @override
  void addListener(AppWindowEventListener listener) {}

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Future<void> destroy() async {}

  @override
  Future<Rect> getBounds() async => const Rect.fromLTWH(0, 0, 1280, 720);

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isMinimized() async => false;

  @override
  Future<void> maximize() async {}

  @override
  void removeListener(AppWindowEventListener listener) {}

  @override
  Future<void> setBounds(Rect bounds) async {}

  @override
  Future<void> setFullScreen(bool value) async {}

  @override
  Future<void> setPreventClose(bool value) async {}

  @override
  Future<void> setTitle(String title) async {}
}
