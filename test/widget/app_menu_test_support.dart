// Shared harness for the app-menu widget suites.
import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/app_menu/infra/native_app_menu_channel.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> withPlatform(
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

Future<void> pumpActionHarness(
  WidgetTester tester, {
  required FutureOr<void> Function(BuildContext context, WidgetRef ref)
  onPressed,
  FakeUpdateController? updateController,
  FakeAppWindowController? window,
}) async {
  final resolvedWindow = window ?? FakeAppWindowController();
  final lifecycle = AppWindowLifecycleCoordinator(
    repository: MemoryAppWindowStateRepository(),
    window: resolvedWindow,
    saveDebounce: Duration.zero,
  );
  await lifecycle.start();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraUpdateControllerProvider.overrideWith(
          () =>
              updateController ??
              FakeUpdateController(
                AleraUpdateState(
                  status: AleraUpdateStatus.idle,
                  config: updateConfig(),
                ),
              ),
        ),
        appWindowControllerProvider.overrideWithValue(resolvedWindow),
        appWindowLifecycleCoordinatorProvider.overrideWithValue(lifecycle),
        settingsControllerProvider.overrideWith(
          () => FakeSettingsController(AleraSettings.defaults),
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

Future<void> pumpMenuScope(
  WidgetTester tester, {
  FakeUpdateController? updateController,
  FakeAppWindowController? window,
  Widget? child,
}) async {
  final resolvedWindow = window ?? FakeAppWindowController();
  final lifecycle = AppWindowLifecycleCoordinator(
    repository: MemoryAppWindowStateRepository(),
    window: resolvedWindow,
    saveDebounce: Duration.zero,
  );
  await lifecycle.start();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraUpdateControllerProvider.overrideWith(
          () =>
              updateController ??
              FakeUpdateController(
                AleraUpdateState(
                  status: AleraUpdateStatus.idle,
                  config: updateConfig(),
                ),
              ),
        ),
        appWindowControllerProvider.overrideWithValue(resolvedWindow),
        appWindowLifecycleCoordinatorProvider.overrideWithValue(lifecycle),
        settingsControllerProvider.overrideWith(
          () => FakeSettingsController(AleraSettings.defaults),
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
Future<void> invokeNativeMenuMethod(WidgetTester tester, String method) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        nativeAppMenuChannelName,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
}

void mockPackageInfo(WidgetTester tester) {
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
void mockClipboard() {
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

AleraUpdateConfig updateConfig() {
  return AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://example.com/releases'),
    channel: AleraUpdateChannel.stable,
    autoInstallEnabled: true,
    signedRelease: true,
  );
}

class FakeSettingsController extends SettingsController {
  FakeSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}

class FakeUpdateController extends AleraUpdateController {
  FakeUpdateController(this._seed);

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

class MemoryAppWindowStateRepository implements AppWindowStateRepository {
  AppWindowState? state;

  @override
  Future<void> clear() async {
    state = null;
  }

  @override
  Future<AppWindowState?> load() async => state;

  @override
  Future<void> save(AppWindowState state) async {
    this.state = state;
  }
}

class FakeAppWindowController implements AppWindowController {
  int closeCalls = 0;
  int destroyCalls = 0;
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];
  bool preventClose = false;

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
    closeCalls += 1;
    for (final listener in List<AppWindowEventListener>.from(listeners)) {
      listener.onWindowClose();
    }
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }

  @override
  Future<Rect> getBounds() async => const Rect.fromLTWH(0, 0, 1280, 720);

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
  Future<void> setPreventClose(bool value) async {
    preventClose = value;
  }

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> show() async {}

  @override
  Future<void> focus() async {}
}
