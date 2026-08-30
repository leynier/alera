import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/render_package_manifests.dart' as render;

/// Renders every template the way the release workflow does, so the assertions
/// below read the same bytes that would be pushed to the tap, the bucket, and
/// chocolatey.org.
Map<String, String> _renderAll({
  String version = '1.2.3',
  String tag = 'v1.2.3',
  String macosSha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String windowsSha256 =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
}) {
  final values = render.packageManifestValues(
    version: version,
    tag: tag,
    macosSha256: macosSha256,
    windowsSha256: windowsSha256,
  );
  return <String, String>{
    for (final entry in render.packageManifestOutputs.entries)
      entry.value: render.renderPackageTemplate(
        File('packaging/${entry.key}').readAsStringSync(),
        values,
        source: entry.key,
      ),
  };
}

void main() {
  group('package manifest rendering', () {
    test('renders every template without leaving a placeholder behind', () {
      final rendered = _renderAll();

      expect(
        rendered.keys,
        containsAll(<String>[
          'homebrew/Casks/alera.rb',
          'scoop/bucket/alera.json',
          'chocolatey/alera.nuspec',
          'chocolatey/tools/chocolateyinstall.ps1',
        ]),
      );
      for (final entry in rendered.entries) {
        expect(entry.value, isNot(contains('{{')), reason: entry.key);
      }
    });

    test('fails loudly rather than shipping an unsubstituted placeholder', () {
      expect(
        () => render.renderPackageTemplate(
          'url {{VERSION}} and {{UNKNOWN}}',
          <String, String>{'VERSION': '1.2.3'},
          source: 'fixture',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('carries the release version and checksums into each package', () {
      final rendered = _renderAll();

      expect(rendered['homebrew/Casks/alera.rb'], contains('version "1.2.3"'));
      expect(
        rendered['homebrew/Casks/alera.rb'],
        contains(
          'sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
        ),
      );

      final scoop = jsonDecode(
        rendered['scoop/bucket/alera.json']!,
      ) as Map<String, dynamic>;
      expect(scoop['version'], '1.2.3');
      final scoop64 =
          (scoop['architecture'] as Map<String, dynamic>)['64bit']
              as Map<String, dynamic>;
      expect(
        scoop64['hash'],
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );

      expect(rendered['chocolatey/alera.nuspec'], contains('<version>1.2.3<'));
      expect(
        rendered['chocolatey/tools/chocolateyinstall.ps1'],
        contains(
          "-Checksum64 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
          "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'",
        ),
      );
    });

    // The packages download straight from the GitHub release, so a rename in
    // the workflow has to fail here rather than turn every install into a 404.
    test('points at the exact assets the release workflow uploads', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();

      expect(
        workflow,
        contains(r'release-assets/alera-${RELEASE_VERSION}-macos.tar.gz'),
      );
      expect(
        workflow,
        contains(r'release-assets/alera-$env:RELEASE_VERSION-windows.zip'),
      );

      final rendered = _renderAll();
      // The cask interpolates the version, which is what brew audit expects, so
      // compare against the asset name with the same interpolation applied.
      expect(
        rendered['homebrew/Casks/alera.rb'],
        contains(
          render
              .macosPackageAssetName('1.2.3')
              .replaceFirst('1.2.3', r'#{version}'),
        ),
      );
      final scoop = jsonDecode(
        rendered['scoop/bucket/alera.json']!,
      ) as Map<String, dynamic>;
      final scoop64 =
          (scoop['architecture'] as Map<String, dynamic>)['64bit']
              as Map<String, dynamic>;
      expect(
        scoop64['url'],
        'https://github.com/leynier/alera/releases/download/v1.2.3/'
        '${render.windowsPackageAssetName('1.2.3')}',
      );
      expect(
        rendered['chocolatey/tools/chocolateyinstall.ps1'],
        contains(render.windowsPackageAssetName('1.2.3')),
      );
    });

    test('publishes the windows updater through the schema 3 manifest', () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync();

      expect(workflow, contains('dart run desktop_updater:release publish'));
      expect(workflow, contains(r'pages/updates/$CHANNEL/app-archive.json'));
      expect(
        workflow,
        isNot(contains(r'if [[ "$name" == *-windows.zip ]]; then')),
      );
    });

    test('declares only the architectures CI actually builds', () {
      final rendered = _renderAll();

      expect(
        rendered['homebrew/Casks/alera.rb'],
        contains('depends_on arch: :arm64'),
      );
      expect(
        rendered['homebrew/Casks/alera.rb'],
        contains('depends_on macos: :sonoma'),
      );
      expect(
        rendered['homebrew/Casks/alera.rb'],
        isNot(contains('depends_on macos: ">=')),
      );
      final scoop = jsonDecode(
        rendered['scoop/bucket/alera.json']!,
      ) as Map<String, dynamic>;
      expect((scoop['architecture'] as Map<String, dynamic>).keys, <String>[
        '64bit',
      ]);
    });

    // The macOS build is not notarized, and Homebrew quarantines what it
    // downloads, so without this the cask installs an app Gatekeeper refuses.
    test('clears the quarantine attribute the unsigned macOS build needs', () {
      expect(
        _renderAll()['homebrew/Casks/alera.rb'],
        contains('com.apple.quarantine'),
      );
    });

    test('does not shim the sidecar under the app own name', () {
      final install = _renderAll()['chocolatey/tools/chocolateyinstall.ps1']!;

      expect(install, contains('Alera.exe.gui'));
      expect(install, contains('.ignore'));
    });
  });

  group('package manifest options', () {
    test('requires a stable tag that matches the version', () {
      expect(
        () => render.parsePackageManifestOptions(<String>[
          '--version',
          '1.2.3',
          '--tag',
          'v1.2.3-rc.1',
          '--macos-sha256',
          'a' * 64,
          '--windows-sha256',
          'b' * 64,
          '--out',
          'out',
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a checksum that is not a lowercase hex sha256', () {
      expect(
        () => render.parsePackageManifestOptions(<String>[
          '--version',
          '1.2.3',
          '--tag',
          'v1.2.3',
          '--macos-sha256',
          'A' * 64,
          '--windows-sha256',
          'b' * 64,
          '--out',
          'out',
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing required option', () {
      expect(
        () => render.parsePackageManifestOptions(<String>[
          '--version',
          '1.2.3',
          '--tag',
          'v1.2.3',
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a complete stable invocation', () {
      final options = render.parsePackageManifestOptions(<String>[
        '--version',
        '1.2.3',
        '--tag',
        'v1.2.3',
        '--macos-sha256',
        'a' * 64,
        '--windows-sha256',
        'b' * 64,
        '--out',
        'build/packaging',
      ]);

      expect(options['out'], 'build/packaging');
    });
  });
}
