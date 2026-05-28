part of 'codex_runtime_home_service.dart';

String _escapeTomlString(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\b', r'\b')
      .replaceAll('\f', r'\f')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

String _unescapeTomlString(String escaped) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < escaped.length) {
    final char = escaped[index];
    if (char == r'\' && index + 1 < escaped.length) {
      final next = escaped[index + 1];
      buffer.write(switch (next) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        'b' => '\b',
        'f' => '\f',
        '"' => '"',
        r'\' => r'\',
        _ => '\\$next',
      });
      index += 2;
      continue;
    }
    buffer.write(char);
    index += 1;
  }
  return buffer.toString();
}

String _readTextFile(String path) {
  final raw = File(path).readAsStringSync();
  return raw.isNotEmpty && raw.codeUnitAt(0) == 0xfeff ? raw.substring(1) : raw;
}

void _writeTextAtomically(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  if (file.existsSync() && file.readAsStringSync() == contents) {
    return;
  }
  if (file.existsSync()) {
    file.copySync('$path.bak');
  }
  final tmp = File(
    p.join(file.parent.path, '.${DateTime.now().microsecondsSinceEpoch}.tmp'),
  )..writeAsStringSync(contents);
  tmp.renameSync(path);
}
