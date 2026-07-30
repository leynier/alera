import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  test('every bundled skill has a valid manifest', () {
    final skillFiles =
        Directory('skills')
            .listSync()
            .whereType<Directory>()
            .map((directory) => File(p.join(directory.path, 'SKILL.md')))
            .where((file) => file.existsSync())
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(skillFiles, isNotEmpty);
    for (final file in skillFiles) {
      final contents = file.readAsStringSync();
      final frontmatter = RegExp(
        r'^---\r?\n(.*?)\r?\n---(?:\r?\n|$)',
        dotAll: true,
      ).firstMatch(contents);
      expect(frontmatter, isNotNull, reason: '${file.path} needs frontmatter');

      final manifest = loadYaml(frontmatter!.group(1)!, sourceUrl: file.uri);
      expect(manifest, isA<YamlMap>(), reason: file.path);
      final values = manifest as YamlMap;
      expect(
        values['name'],
        p.basename(file.parent.path),
        reason: '${file.path} must match its directory name',
      );
      expect(
        values['description'],
        isA<String>().having((value) => value.trim(), 'value', isNotEmpty),
        reason: '${file.path} needs a description',
      );
    }
  });
}
