import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_stager.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DesktopUpdateStager', () {
    for (final fixture in <({String platform, String executable})>[
      (platform: 'macos', executable: 'Alera.app/Contents/MacOS/Alera'),
      (platform: 'windows', executable: 'Alera.exe'),
    ]) {
      test(
        'downloads, verifies, and extracts ${fixture.platform} tarballs',
        () async {
          final artifact = _tarGzip(<String, String>{
            fixture.executable: 'updated executable',
            'data/flutter_assets/version.json': '{"build_number":"2"}',
          });
          final stager = DesktopUpdateStager(
            client: MockClient(
              (_) async => http.Response.bytes(artifact, HttpStatus.ok),
            ),
            platform: fixture.platform,
          );
          final progress = <double>[];

          final staged = await stager.stage(
            _update(
              platform: fixture.platform,
              artifact: artifact,
              installerKind: 'tar.gz',
            ),
            onProgress: progress.add,
          );
          addTearDown(staged.delete);

          final executablePath = fixture.platform == 'macos'
              ? p.join(staged.payloadPath!, 'Contents', 'MacOS', 'Alera')
              : p.join(staged.payloadPath!, p.basename(fixture.executable));
          expect(
            await File(executablePath).readAsString(),
            'updated executable',
          );
          expect(progress, isNotEmpty);
          expect(progress.last, 1);
          expect(progress, orderedEquals(<double>[...progress]..sort()));
        },
      );
    }

    for (final installerKind in <String>['deb', 'rpm', 'tar.gz']) {
      test(
        'rejects Linux $installerKind automatic updates before download',
        () async {
          var requests = 0;
          final stager = DesktopUpdateStager(
            client: MockClient((_) async {
              requests += 1;
              return http.Response('', HttpStatus.ok);
            }),
            platform: 'linux',
          );

          await expectLater(
            stager.stage(
              _update(
                platform: 'linux',
                artifact: const <int>[1],
                installerKind: installerKind,
              ),
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('apt, dnf'),
              ),
            ),
          );

          expect(requests, 0);
        },
      );
    }

    test('rejects incomplete and tampered downloads', () async {
      final bytes = <int>[1, 2, 3];
      final incomplete = DesktopUpdateStager(
        client: MockClient(
          (_) async => http.Response.bytes(bytes, HttpStatus.ok),
        ),
        platform: 'windows',
      );
      final tampered = DesktopUpdateStager(
        client: MockClient(
          (_) async => http.Response.bytes(bytes, HttpStatus.ok),
        ),
        platform: 'windows',
      );

      await expectLater(
        incomplete.stage(
          _update(
            platform: 'windows',
            artifact: <int>[...bytes, 4],
            installerKind: 'tar.gz',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('size'),
          ),
        ),
      );
      await expectLater(
        tampered.stage(
          _update(
            platform: 'windows',
            artifact: bytes,
            installerKind: 'tar.gz',
            sha256Override:
                '0000000000000000000000000000000000000000000000000000000000000000',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('SHA-256'),
          ),
        ),
      );
    });

    test('rejects artifacts for a different platform', () async {
      final stager = DesktopUpdateStager(
        client: MockClient((_) async => http.Response('', HttpStatus.ok)),
        platform: 'windows',
      );

      await expectLater(
        stager.stage(
          _update(
            platform: 'macos',
            artifact: const <int>[1],
            installerKind: 'tar.gz',
          ),
        ),
        throwsStateError,
      );
    });
  });
}

AleraUpdateInfo _update({
  required String platform,
  required List<int> artifact,
  required String installerKind,
  String? sha256Override,
}) {
  return AleraUpdateInfo(
    version: '1.2.3',
    shortVersion: 2,
    date: '2026-07-27',
    mandatory: false,
    url: Uri.parse('https://example.com/alera.$installerKind'),
    platform: platform,
    changes: const <String>['Update Alera'],
    installerKind: installerKind,
    sha256: sha256Override ?? sha256.convert(artifact).toString(),
    size: artifact.length,
  );
}

List<int> _tarGzip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = entry.value.codeUnits;
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final tar = TarEncoder().encode(archive);
  return GZipEncoder().encode(tar);
}
