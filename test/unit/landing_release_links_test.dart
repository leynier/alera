import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _dataPath = 'landing/src/data/releases.json';
const String _downloadPage = 'landing/src/pages/download.astro';
const String _workflow = '.github/workflows/release-cut.yml';
const String _updateScript = 'tool/release/update_landing_release_links.dart';

void main() {
  group('landing release links', () {
    test('pins a stable version and a matching tag per product', () {
      final data =
          jsonDecode(File(_dataPath).readAsStringSync())
              as Map<String, dynamic>;

      final desktop = data['desktop'] as Map<String, dynamic>;
      final mobile = data['mobile'] as Map<String, dynamic>;
      final stableCore = RegExp(r'^\d+\.\d+\.\d+$');

      expect(desktop['version'] as String, matches(stableCore));
      expect(mobile['version'] as String, matches(stableCore));
      // The tag is what the asset URL path uses, so a tag that does not carry
      // its own version would build a download link to another release.
      expect(desktop['tag'], 'v${desktop['version']}');
      expect(mobile['tag'], 'v${mobile['version']}-mobile');
    });

    test('builds asset names the release workflow actually produces', () {
      // The landing composes these names itself, so a rename in CI would
      // silently turn every download button into a 404.
      final page = File(_downloadPage).readAsStringSync();
      final workflow = File(_workflow).readAsStringSync();

      expect(page, contains(r'alera-${releases.desktop.version}-macos.tar.gz'));
      expect(
        page,
        contains(r'alera-${releases.desktop.version}-windows.tar.gz'),
      );
      expect(page, contains(r'alera-${releases.mobile.version}-android.apk'));

      expect(
        workflow,
        contains(r'release-assets/alera-${RELEASE_VERSION}-macos.tar.gz'),
      );
      expect(
        workflow,
        contains(r'release-assets/alera-$env:RELEASE_VERSION-windows.tar.gz'),
      );
    });

    test('points at the release download path, not a listing', () {
      final page = File(_downloadPage).readAsStringSync();

      expect(
        page,
        contains(
          r'https://github.com/leynier/alera/releases/download/${tag}/${file}',
        ),
      );
    });

    test('the release commit rewrites the pin for stable cuts', () {
      // A cut that bumps the version without moving this file leaves the
      // download page serving the previous release's assets.
      final workflow = File(_workflow).readAsStringSync();

      expect(workflow, contains('dart $_updateScript'));
      expect(workflow, contains('git add $_dataPath'));
      expect(
        workflow,
        contains(r'if [[ "$CHANNEL" == "stable" ]]; then'),
        reason: 'an rc must not become the landing download',
      );
    });
  });
}
