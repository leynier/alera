import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical video runtime pins are lowercase SHA-256 digests', () {
    final manifest = jsonDecode(
      File('tool/native_helpers/video_runtime_assets.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final windows = manifest['windows']! as Map<String, Object?>;
    final sha256 = RegExp(r'^[0-9a-f]{64}$');

    for (final source
        in (windows['sources']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
      expect(source['sha256'], matches(sha256));
    }
    for (final file
        in (windows['requiredFiles']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
      expect(
        file['sha256'],
        matches(sha256),
        reason: '${file['relativePath']} must have a valid SHA-256 pin.',
      );
    }
  });
}
