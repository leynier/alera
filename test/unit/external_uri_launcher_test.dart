import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  test('opens uri when the platform launcher succeeds', () async {
    final openedUris = <Uri>[];
    final launcher = UrlLauncherExternalUriLauncher(
      launch: (uri) async {
        openedUris.add(uri);
        return true;
      },
    );

    await launcher.open(Uri.parse('https://example.com'));

    expect(openedUris, <Uri>[Uri.parse('https://example.com')]);
  });

  test('throws when the platform launcher reports failure', () {
    final launcher = UrlLauncherExternalUriLauncher(launch: (_) async => false);

    expect(
      () => launcher.open(Uri.parse('https://example.com')),
      throwsStateError,
    );
  });

  test('default launcher delegates to url_launcher platform mode', () async {
    final previousPlatform = UrlLauncherPlatform.instance;
    final fakePlatform = _FakeUrlLauncherPlatform();
    UrlLauncherPlatform.instance = fakePlatform;
    addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);

    final launcher = UrlLauncherExternalUriLauncher();
    final uri = Uri.parse('https://example.com/docs');

    await launcher.open(uri);

    expect(fakePlatform.launchedUrls, <String>[uri.toString()]);
    expect(fakePlatform.launchCalls, hasLength(1));
    expect(fakePlatform.launchCalls.single.useSafariVC, isFalse);
    expect(fakePlatform.launchCalls.single.useWebView, isFalse);
    expect(fakePlatform.launchCalls.single.universalLinksOnly, isFalse);
  });
}

class _FakeUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launchedUrls = <String>[];
  final List<_LaunchCall> launchCalls = <_LaunchCall>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    launchCalls.add(
      _LaunchCall(
        useSafariVC: useSafariVC,
        useWebView: useWebView,
        universalLinksOnly: universalLinksOnly,
      ),
    );
    return true;
  }
}

class const _LaunchCall({
  required final bool useSafariVC,
  required final bool useWebView,
  required final bool universalLinksOnly,
});
