import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart tool/release/merge_desktop_update_indexes.dart '
      '<fragments-directory> <output-file>',
    );
    exit(64);
  }

  final fragmentsDirectory = Directory(args[0]);
  if (!fragmentsDirectory.existsSync()) {
    stderr.writeln('${fragmentsDirectory.path} does not exist.');
    exit(1);
  }
  final files =
      fragmentsDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  if (files.length != 3) {
    stderr.writeln(
      'Expected 3 desktop update index fragments, found ${files.length}.',
    );
    exit(1);
  }

  String? appName;
  final items = <Map<String, dynamic>>[];
  for (final file in files) {
    final index = _jsonObject(await file.readAsString(), file.path);
    if (index['schemaVersion'] != 3) {
      throw FormatException('${file.path} must use schemaVersion 3.');
    }
    final fragmentItems = index['items'];
    if (fragmentItems is! List || fragmentItems.length != 1) {
      throw FormatException(
        '${file.path} must contain exactly one release item.',
      );
    }
    final item = fragmentItems.single;
    if (item is! Map) {
      throw FormatException('${file.path} contains an invalid release item.');
    }
    final fragmentAppName = index['appName'];
    if (fragmentAppName is! String || fragmentAppName.trim().isEmpty) {
      throw FormatException('${file.path} must include appName.');
    }
    if (appName != null && appName != fragmentAppName) {
      throw FormatException(
        '${file.path} uses a different app name than the other fragments.',
      );
    }
    appName = fragmentAppName;
    items.add(Map<String, dynamic>.from(item));
  }

  items.sort(
    (left, right) =>
        left['platform'].toString().compareTo(right['platform'].toString()),
  );
  final platforms = items.map((item) => item['platform']).toSet();
  if (!platforms.containsAll(const <String>{'linux', 'macos', 'windows'}) ||
      platforms.length != 3) {
    throw const FormatException(
      'Desktop update fragments must cover linux, macos, and windows once.',
    );
  }

  final output = File(args[1]);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{'schemaVersion': 3, 'appName': appName, 'items': items})}\n',
  );
  stdout.writeln('Merged desktop update index: ${output.path}');
}

Map<String, dynamic> _jsonObject(String source, String path) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw FormatException('$path must contain a JSON object.');
  }
  return Map<String, dynamic>.from(decoded);
}
