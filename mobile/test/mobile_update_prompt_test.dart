import 'package:alera_mobile/src/features/updater/application/mobile_update_providers.dart';
import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:alera_mobile/src/features/updater/infra/mobile_external_browser.dart';
import 'package:alera_mobile/src/features/updater/presentation/mobile_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

final MobileRelease _release = MobileRelease(
  version: const MobileVersion(0, 10, 0),
  tag: 'v0.10.0-mobile',
  apkUrl: Uri.parse(
    'https://github.com/leynier/alera/releases/download/'
    'v0.10.0-mobile/alera-0.10.0-android.apk',
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required MobileRelease? release,
  required List<String> copied,
  Future<bool> Function(Uri url)? openUrl,
}) {
  final prompt = openUrl == null
      ? MobileUpdatePrompt(
          copyLink: (link) async => copied.add(link),
          child: const Scaffold(body: Text('Home')),
        )
      : MobileUpdatePrompt(
          copyLink: (link) async => copied.add(link),
          openUrl: openUrl,
          child: const Scaffold(body: Text('Home')),
        );
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        availableMobileUpdateProvider.overrideWith((ref) async => release),
      ],
      child: MaterialApp(home: prompt),
    ),
  );
}

void main() {
  testWidgets('offers the universal apk when a newer release exists', (
    tester,
  ) async {
    final copied = <String>[];
    final opened = <Uri>[];
    await _pump(
      tester,
      release: _release,
      copied: copied,
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('0.10.0'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(opened, <Uri>[_release.apkUrl]);
  });

  testWidgets('download opens the apk in the standalone browser', (
    tester,
  ) async {
    final previousPlatform = UrlLauncherPlatform.instance;
    final fakePlatform = _RecordingUrlLauncherPlatform();
    UrlLauncherPlatform.instance = fakePlatform;
    addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);

    final opened = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(mobileExternalBrowserChannelName),
      (call) async {
        opened.add(call);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(mobileExternalBrowserChannelName),
        null,
      ),
    );

    final copied = <String>[];
    await _pump(tester, release: _release, copied: copied);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(opened, hasLength(1));
    expect(opened.single.method, 'open');
    expect(opened.single.arguments, <String, Object>{
      'url': _release.apkUrl.toString(),
    });
    expect(fakePlatform.launchedUrls, isEmpty);
  });

  testWidgets('copies the apk link without opening it', (tester) async {
    final copied = <String>[];
    final opened = <Uri>[];
    await _pump(tester, release: _release, copied: copied);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();

    expect(copied, <String>[_release.apkUrl.toString()]);
    expect(opened, isEmpty);
    expect(find.text('Download link copied.'), findsOneWidget);
  });

  testWidgets('declining opens nothing and does not ask again', (tester) async {
    final copied = <String>[];
    final opened = <Uri>[];
    await _pump(tester, release: _release, copied: copied);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    expect(opened, isEmpty);
    expect(find.text('Update available'), findsNothing);

    // A rebuild must not re-open the dialog the user just dismissed.
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('stays silent when the app is current', (tester) async {
    final copied = <String>[];
    final opened = <Uri>[];
    await _pump(tester, release: null, copied: copied);
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(copied, isEmpty);
    expect(opened, isEmpty);
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
