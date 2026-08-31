import 'dart:io';

void main(List<String> arguments) {
  final package = arguments.isEmpty ? '.' : arguments.single;
  var normalized = 0;
  for (final source in ['lib', 'test']) {
    final directory = Directory('$package/$source');
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File ||
          (!entity.path.endsWith('.g.dart') &&
              !entity.path.endsWith('.mapper.dart'))) {
        continue;
      }
      final content = entity.readAsStringSync();
      if (!content.contains('GENERATED CODE')) continue;
      // dart_mappable appends a newline to formatter output that already has one.
      // Its format-off directive prevents dart format from normalizing that EOF.
      final canonical = '${content.trimRight()}\n';
      if (content != canonical) {
        entity.writeAsStringSync(canonical);
        normalized++;
      }
    }
  }
  stdout.writeln('Normalized generated EOFs: $normalized in $package.');
}
