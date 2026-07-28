import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:alera_mobile/src/features/updater/infra/github_mobile_release_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> _release(
  String tag, {
  List<String> assets = const <String>[],
  bool draft = false,
  bool prerelease = false,
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'draft': draft,
    'prerelease': prerelease,
    'assets': <Map<String, dynamic>>[
      for (final name in assets)
        <String, dynamic>{
          'name': name,
          'browser_download_url':
              'https://github.com/leynier/alera/releases/download/$tag/$name',
        },
    ],
  };
}

void main() {
  group('MobileVersion', () {
    test('parses a pubspec version with a build suffix', () {
      expect(MobileVersion.tryParse('0.9.0+63'), const MobileVersion(0, 9, 0));
      expect(MobileVersion.tryParse('1.2.3'), const MobileVersion(1, 2, 3));
      expect(MobileVersion.tryParse('nonsense'), isNull);
    });

    test('only accepts stable mobile tags', () {
      expect(
        MobileVersion.tryParseTag('v0.9.0-mobile'),
        const MobileVersion(0, 9, 0),
      );
      // A desktop tag and an rc must never drive the mobile upgrade path.
      expect(MobileVersion.tryParseTag('v0.34.0'), isNull);
      expect(MobileVersion.tryParseTag('v0.10.0-rc.1-mobile'), isNull);
    });

    test('orders by major, then minor, then patch', () {
      expect(
        const MobileVersion(0, 10, 0).isNewerThan(const MobileVersion(0, 9, 9)),
        isTrue,
      );
      expect(
        const MobileVersion(1, 0, 0).isNewerThan(const MobileVersion(0, 99, 9)),
        isTrue,
      );
      expect(
        const MobileVersion(0, 9, 0).isNewerThan(const MobileVersion(0, 9, 0)),
        isFalse,
      );
    });
  });

  group('latestMobileRelease', () {
    test('picks the newest stable mobile tag with a universal apk', () {
      final release = latestMobileRelease(<dynamic>[
        _release('v0.9.0-mobile', assets: <String>['alera-0.9.0-android.apk']),
        _release(
          'v0.10.0-mobile',
          assets: <String>[
            'alera-0.10.0-android.apk',
            'alera-0.10.0-android-arm64-v8a.apk',
          ],
        ),
        _release('v0.34.0', assets: <String>['alera-0.34.0-macos.tar.gz']),
      ]);

      expect(release, isNotNull);
      expect(release!.version, const MobileVersion(0, 10, 0));
      expect(release.tag, 'v0.10.0-mobile');
      expect(release.apkUrl.path, endsWith('/alera-0.10.0-android.apk'));
    });

    test('never offers a per-abi apk', () {
      // Resolving the device ABI is a guess that fails on a device reporting
      // several, so a release without the universal build is skipped entirely.
      final release = latestMobileRelease(<dynamic>[
        _release(
          'v0.10.0-mobile',
          assets: <String>[
            'alera-0.10.0-android-arm64-v8a.apk',
            'alera-0.10.0-android-x86_64.apk',
          ],
        ),
        _release('v0.9.0-mobile', assets: <String>['alera-0.9.0-android.apk']),
      ]);

      expect(release!.version, const MobileVersion(0, 9, 0));
    });

    test('skips drafts and prereleases', () {
      // The release commit reaches main before the draft is published, so a
      // phone can see a listing whose newest entry still 404s on its assets.
      final release = latestMobileRelease(<dynamic>[
        _release(
          'v0.11.0-mobile',
          assets: <String>['alera-0.11.0-android.apk'],
          draft: true,
        ),
        _release(
          'v0.10.0-mobile',
          assets: <String>['alera-0.10.0-android.apk'],
          prerelease: true,
        ),
        _release('v0.9.0-mobile', assets: <String>['alera-0.9.0-android.apk']),
      ]);

      expect(release!.version, const MobileVersion(0, 9, 0));
    });

    test('returns null when nothing qualifies', () {
      expect(latestMobileRelease(<dynamic>[]), isNull);
      expect(latestMobileRelease(<dynamic>[_release('v0.34.0')]), isNull);
    });
  });

  group('GitHubMobileReleaseSource', () {
    test('reads the release listing over http', () async {
      final server = await _serve(
        200,
        jsonEncode(<dynamic>[
          _release(
            'v0.10.0-mobile',
            assets: <String>['alera-0.10.0-android.apk'],
          ),
        ]),
      );
      addTearDown(() => server.close());

      final source = GitHubMobileReleaseSource(releasesUrl: server.url);
      addTearDown(source.dispose);

      final release = await source.latestRelease();

      expect(release!.version, const MobileVersion(0, 10, 0));
    });

    test('reports a non-200 rather than treating it as up to date', () async {
      final server = await _serve(403, 'rate limited');
      addTearDown(() => server.close());

      final source = GitHubMobileReleaseSource(releasesUrl: server.url);
      addTearDown(source.dispose);

      await expectLater(
        source.latestRelease(),
        throwsA(isA<http.ClientException>()),
      );
    });
  });
}

Future<_StubServer> _serve(int statusCode, String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  });
  return _StubServer(server);
}

class _StubServer {
  _StubServer(this._server);

  final HttpServer _server;

  Uri get url =>
      Uri.parse('http://${_server.address.address}:${_server.port}/releases');

  Future<void> close() => _server.close(force: true);
}
