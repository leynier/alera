import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
