import 'package:alera_mobile/src/features/updater/infra/mobile_external_browser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const apkUrl =
      'https://github.com/leynier/alera/releases/download/'
      'v0.10.0-mobile/alera-0.10.0-android.apk';
  const channel = MethodChannel(mobileExternalBrowserChannelName);
  final uri = Uri.parse(apkUrl);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('asks the native channel to open https urls', () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          call = methodCall;
          return true;
        });
    final fallback = <Uri>[];

    final opened = await openMobileExternalBrowser(
      uri,
      fallback: (url) async {
        fallback.add(url);
        return false;
      },
    );

    expect(opened, isTrue);
    expect(call?.method, 'open');
    expect(call?.arguments, <String, Object>{'url': apkUrl});
    expect(fallback, isEmpty);
  });

  test('rejects non-web schemes without calling native or fallback', () async {
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          nativeCalls += 1;
          return true;
        });
    final fallback = <Uri>[];

    final opened = await openMobileExternalBrowser(
      Uri.parse('intent://github.com/leynier/alera'),
      fallback: (url) async {
        fallback.add(url);
        return true;
      },
    );

    expect(opened, isFalse);
    expect(nativeCalls, 0);
    expect(fallback, isEmpty);
  });

  test(
    'falls back to url_launcher when the native channel is missing',
    () async {
      final previousPlatform = UrlLauncherPlatform.instance;
      final fakePlatform = _RecordingUrlLauncherPlatform();
      UrlLauncherPlatform.instance = fakePlatform;
      addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);

      final opened = await openMobileExternalBrowser(uri);

      expect(opened, isTrue);
      expect(fakePlatform.launchedUrls, <String>[apkUrl]);
      expect(fakePlatform.modes, <PreferredLaunchMode>[
        PreferredLaunchMode.externalApplication,
      ]);
    },
  );

  test('falls back when the native channel reports failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    final fallback = <Uri>[];

    final opened = await openMobileExternalBrowser(
      uri,
      fallback: (url) async {
        fallback.add(url);
        return true;
      },
    );

    expect(opened, isTrue);
    expect(fallback, <Uri>[uri]);
  });
}

class _RecordingUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launchedUrls = <String>[];
  final List<PreferredLaunchMode> modes = <PreferredLaunchMode>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    modes.add(options.mode);
    return true;
  }
}
