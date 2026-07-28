import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/native_helpers/video_runtime_verifier.dart';

void main() {
  test('accepts package pins from a CRLF lockfile', () async {
    final temp = await Directory.systemTemp.createTemp(
      'alera-video-runtime-lock-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));

    final payload = utf8.encode('video runtime');
    File(p.join(temp.path, 'libmpv-2.dll')).writeAsBytesSync(payload);
    final manifest = File(p.join(temp.path, 'video.json'))
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'dartPackages': <String, Object?>{'media_kit': '1.2.6'},
          'windows': <String, Object?>{
            'gplEnabled': false,
            'sources': <Object?>[
              <String, Object?>{'sha256': List<String>.filled(64, '1').join()},
              <String, Object?>{'sha256': List<String>.filled(64, '2').join()},
            ],
            'requiredFiles': <Object?>[
              <String, Object?>{
                'relativePath': 'libmpv-2.dll',
                'sha256': sha256.convert(payload).toString(),
              },
            ],
          },
        }),
      );
    final lockFile = File(p.join(temp.path, 'pubspec.lock'))
      ..writeAsStringSync(
        <String>[
          'packages:',
          '  media_kit:',
          '    dependency: "direct main"',
          '    description:',
          '      name: media_kit',
          '    source: hosted',
          '    version: "1.2.6"',
          '',
        ].join('\r\n'),
      );

    await verifyVideoRuntimeBundle(
      platform: 'windows',
      bundle: temp,
      manifestFile: manifest,
      lockFile: lockFile,
    );
  });
}
