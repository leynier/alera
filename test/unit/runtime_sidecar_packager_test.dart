import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/package_runtime_sidecars.dart';

const _nativeArchitectures = <String, String>{
  'macos': 'arm64',
  'windows': 'x64',
  'linux': 'x64',
};

void main() {
  group('runtime sidecar packager', () {
    test('creates deterministic archives for all six runtimes', () async {
      final fixture = await _RuntimeFixture.create();
      addTearDown(fixture.dispose);

      packageRuntimeSidecars(
        version: '1.2.3',
        inputDirectory: fixture.input,
        outputDirectory: fixture.output,
      );
      final firstBytes = <String, List<int>>{
        for (final file in fixture.output.listSync().whereType<File>())
          p.basename(file.path): file.readAsBytesSync(),
      };
      packageRuntimeSidecars(
        version: '1.2.3',
        inputDirectory: fixture.input,
        outputDirectory: fixture.output,
      );

      final archives = fixture.output
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.tar.gz'))
          .toList();
      expect(archives, hasLength(6));
      expect(fixture.output.listSync().whereType<File>(), hasLength(12));

      for (final platform in _nativeArchitectures.keys) {
        for (final architecture in <String>['x64', 'arm64']) {
          final assetName =
              'alera-runtime-1.2.3-$platform-$architecture.tar.gz';
          final asset = File(p.join(fixture.output.path, assetName));
          final checksum = File('${asset.path}.sha256');
          expect(asset.existsSync(), isTrue);
          expect(
            checksum.readAsStringSync(),
            '${sha256.convert(asset.readAsBytesSync())}  $assetName\n',
          );
          expect(asset.readAsBytesSync(), firstBytes[assetName]);

          final archive = TarDecoder().decodeBytes(
            GZipDecoder().decodeBytes(asset.readAsBytesSync()),
          );
          final entries = <String, ArchiveFile>{
            for (final entry in archive) entry.name: entry,
          };
          final binaryName = platform == 'windows' ? 'alera.exe' : 'alera';
          expect(entries.keys, contains(binaryName));
          expect(entries[binaryName]!.unixPermissions, 0x1ed);
          expect(entries.keys, contains('runtime-manifest.json'));
          expect(entries.keys, isNot(contains('emulator/manifest.json')));

          final manifest = jsonDecode(
            utf8.decode(entries['runtime-manifest.json']!.content),
          ) as Map<String, Object?>;
          expect(manifest, <String, Object?>{
            'name': 'alera-runtime',
            'version': '1.2.3',
            'platform': platform,
            'arch': architecture,
            'entrypoint': binaryName,
          });
          expect(entries['runtime-manifest.json']!.unixPermissions, 0x1a4);
        }
      }
    });

    test('rejects a missing architecture', () async {
      final fixture = await _RuntimeFixture.create();
      addTearDown(fixture.dispose);
      Directory(p.join(fixture.input.path, 'linux', 'arm64'))
          .deleteSync(recursive: true);

      expect(
        () => packageRuntimeSidecars(
          version: '1.2.3',
          inputDirectory: fixture.input,
          outputDirectory: fixture.output,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Missing runtime architectures for linux: arm64'),
          ),
        ),
      );
    });

    test('rejects unsupported platforms and architectures', () async {
      final fixture = await _RuntimeFixture.create();
      addTearDown(fixture.dispose);
      Directory(p.join(fixture.input.path, 'freebsd', 'x64'))
          .createSync(recursive: true);

      expect(
        () => packageRuntimeSidecars(
          version: '1.2.3',
          inputDirectory: fixture.input,
          outputDirectory: fixture.output,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Unsupported runtime platforms: freebsd'),
          ),
        ),
      );
    });

    test('rejects an absent runtime binary', () async {
      final fixture = await _RuntimeFixture.create();
      addTearDown(fixture.dispose);
      File(p.join(fixture.input.path, 'windows', 'arm64', 'alera.exe'))
          .deleteSync();

      expect(
        () => packageRuntimeSidecars(
          version: '1.2.3',
          inputDirectory: fixture.input,
          outputDirectory: fixture.output,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Missing runtime binary for windows/arm64'),
          ),
        ),
      );
    });
  });
}

final class const _RuntimeFixture({
  required final Directory root,
  required final Directory input,
  required final Directory output,
}) {
  static Future<_RuntimeFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'alera-runtime-packager-',
    );
    final input = Directory(p.join(root.path, 'input'));
    final output = Directory(p.join(root.path, 'output'));
    for (final platform in _nativeArchitectures.keys) {
      for (final architecture in <String>['x64', 'arm64']) {
        final directory = Directory(p.join(input.path, platform, architecture))
          ..createSync(recursive: true);
        final binaryName = platform == 'windows' ? 'alera.exe' : 'alera';
        File(p.join(directory.path, binaryName))
            .writeAsStringSync('$platform/$architecture');
      }
    }
    return _RuntimeFixture(root: root, input: input, output: output);
  }

  Future<void> dispose() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}
