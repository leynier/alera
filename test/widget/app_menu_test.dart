import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/app_menu/infra/native_app_menu_channel.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    for (final platform in <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      group('on $platform (native runner menu)', () {
        testWidgets('renders no in-window menu bar', (tester) async {
          await _withPlatform(platform, () async {
            await _pumpMenuScope(tester);

            expect(find.byType(MenuBar), findsNothing);
            expect(find.byType(PlatformMenuBar), findsNothing);
          });
        });

        testWidgets('native channel opens the settings dialog', (tester) async {
          await _withPlatform(platform, () async {
            await _pumpMenuScope(tester);

            await _invokeNativeMenuMethod(
              tester,
              NativeAppMenuMethod.openSettings,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            expect(find.text('Application'), findsWidgets);
          });
        });

        testWidgets('native channel runs the update check', (tester) async {
          await _withPlatform(platform, () async {
            final updateController = _FakeUpdateController(
              AleraUpdateState(status: AleraUpdateStatus.idle, config: _config()),
            );
            final toastMessages = <String>[];
            final sub = AleraToast.stream.listen((data) {
              toastMessages.add(data.message);
            });
            addTearDown(sub.cancel);

            await _pumpMenuScope(tester, updateController: updateController);

            await _invokeNativeMenuMethod(
              tester,
              NativeAppMenuMethod.checkForUpdates,
            );
            await tester.pump();
            await tester.pump();

            expect(updateController.checkForUpdatesCalls, 1);
            expect(toastMessages, <String>['Alera is up to date.']);
          });
        });

        testWidgets('native channel shows the about dialog', (tester) async {
          await _withPlatform(platform, () async {
            _mockPackageInfo(tester);

            await _pumpMenuScope(tester);

            await _invokeNativeMenuMethod(tester, NativeAppMenuMethod.showAbout);
            await tester.pumpAndSettle();

            expect(find.text(kAleraAppName), findsWidgets);
            expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
          });
        });

        testWidgets('native channel closes the app window', (tester) async {
          await _withPlatform(platform, () async {
            final window = _FakeAppWindowController();
            await _pumpMenuScope(tester, window: window);

            await _invokeNativeMenuMethod(tester, NativeAppMenuMethod.exitApp);
            await tester.pump();

            expect(window.closeCalls, 1);
          });
        });

        testWidgets('native channel edit methods act on the focused text field', (
          tester,
        ) async {
          await _withPlatform(platform, () async {
            final controller = TextEditingController();
            addTearDown(controller.dispose);
            _mockClipboard();
            await _pumpMenuScope(
              tester,
              child: Scaffold(
                body: Center(child: TextField(controller: controller)),
              ),
            );

            await tester.tap(find.byType(TextField));
            await tester.pump();
            await tester.enterText(find.byType(TextField), 'hello');
            await tester.pump();

            await _invokeNativeMenuMethod(
              tester,
              NativeAppMenuMethod.selectAll,
            );
            await tester.pump();
            expect(
              controller.selection,
              const TextSelection(baseOffset: 0, extentOffset: 5),
            );

            await _invokeNativeMenuMethod(tester, NativeAppMenuMethod.cut);
            await tester.pump();
            expect(controller.text, isEmpty);
            final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
            expect(clipboard?.text, 'hello');

            await _invokeNativeMenuMethod(tester, NativeAppMenuMethod.paste);
            await tester.pump();
            expect(controller.text, 'hello');
          });
        });
      });
    }

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

Future<void> _pumpMenuScope(
  WidgetTester tester, {
  _FakeUpdateController? updateController,
  _FakeAppWindowController? window,
  Widget? child,
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
        home: AleraAppMenuScope(
          child: child ?? const Scaffold(body: SizedBox.expand()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Simulates a native (GTK/Win32) menu activation arriving over the app-menu
/// channel.
Future<void> _invokeNativeMenuMethod(WidgetTester tester, String method) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        nativeAppMenuChannelName,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
}

void _mockPackageInfo(WidgetTester tester) {
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return <String, String>{
          'appName': kAleraAppName,
          'packageName': 'dev.leynier.alera',
          'version': '1.2.3',
          'buildNumber': '45',
        };
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

/// The test binding does not answer clipboard platform messages, so the edit
/// menu intents would hang without an in-memory mock.
void _mockClipboard() {
  String? clipboardText;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.getData':
        final text = clipboardText;
        return text == null ? null : <String, dynamic>{'text': text};
      case 'Clipboard.setData':
        clipboardText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
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
