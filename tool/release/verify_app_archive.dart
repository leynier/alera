import 'dart:convert';
import 'dart:io';

const _requiredPlatforms = <String>{'macos', 'windows', 'linux'};

void main(List<String> args) {
  final path = args.isEmpty ? 'public/app-archive.json' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path does not exist.');
    exit(1);
  }

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('$path must contain a JSON object.');
    exit(1);
  }

  final items = decoded['items'];
  if (items is! List || items.isEmpty) {
    stderr.writeln('$path must contain a non-empty items array.');
    exit(1);
  }

  final platforms = <String>{};
  for (final item in items) {
    if (item is! Map<String, Object?>) {
      stderr.writeln('Every item must be a JSON object.');
      exit(1);
    }
    _requireString(item, 'version');
    _requireString(item, 'date');
    _requireString(item, 'url');
    final platform = _requireString(item, 'platform');
    platforms.add(platform);
    if (item['shortVersion'] is! int) {
      stderr.writeln('shortVersion must be an integer for $platform.');
      exit(1);
    }
    if (item['mandatory'] is! bool) {
      stderr.writeln('mandatory must be a boolean for $platform.');
      exit(1);
    }
    if (item['changes'] is! List || (item['changes'] as List).isEmpty) {
      stderr.writeln('changes must be a non-empty array for $platform.');
      exit(1);
    }
  }

  final missing = _requiredPlatforms.difference(platforms);
  if (missing.isNotEmpty) {
    stderr.writeln('Missing platforms: ${missing.join(', ')}');
    exit(1);
  }

  stdout.writeln('Verified $path for ${platforms.length} platforms.');
}

String _requireString(Map<String, Object?> item, String key) {
  final value = item[key];
  if (value is! String || value.trim().isEmpty) {
    stderr.writeln('$key must be a non-empty string.');
    exit(1);
  }
  return value;
}
