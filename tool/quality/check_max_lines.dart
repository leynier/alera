import 'dart:io';

import 'package:path/path.dart' as p;

/// Ratchet check for AGENTS.md file-length guidance (default 500 lines).
///
/// Fails when a scanned source file exceeds [maxLines] **and** either:
/// - it is not listed in the baseline, or
/// - its line count is greater than the baseline allowance for that path.
///
/// Generate/update baseline:
///   dart run tool/quality/check_max_lines.dart --write-baseline
void main(List<String> args) {
  final config = _Args.parse(args);
  final repoRoot = _findRepoRoot();
  final baselinePath = File(
    config.baseline == null
        ? '${repoRoot.path}/tool/quality/max_lines_baseline.txt'
        : config.baseline!,
  );
  final baseline = baselinePath.existsSync()
      ? _readBaseline(baselinePath)
      : <String, int>{};

  final offenders = <_FileLines>[];
  final oversized = <_FileLines>[];

  for (final root in config.roots) {
    final dir = Directory('${repoRoot.path}/$root');
    if (!dir.existsSync()) {
      continue;
    }
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relative = _posixRelative(repoRoot, entity);
      if (!_shouldScan(relative)) {
        continue;
      }
      final lines = _countLines(entity);
      final record = _FileLines(relative, lines);
      if (lines <= config.maxLines) {
        continue;
      }
      oversized.add(record);
      final allowed = baseline[relative];
      if (allowed == null || lines > allowed) {
        offenders.add(record);
      }
    }
  }

  oversized.sort((a, b) => b.lines.compareTo(a.lines));

  if (config.writeBaseline) {
    final lines = oversized.map((e) => '${e.lines}\t${e.path}').toList()
      ..sort();
    baselinePath.writeAsStringSync('${lines.join('\n')}\n');
    stderr.writeln(
      'Wrote ${oversized.length} oversized files to ${baselinePath.path}',
    );
    exit(0);
  }

  if (config.listOversized) {
    for (final file in oversized) {
      final allowed = baseline[file.path];
      final tag = allowed == null
          ? 'new'
          : (file.lines > allowed ? 'grew' : 'baseline');
      stdout.writeln('${file.lines}\t$tag\t${file.path}');
    }
    exit(0);
  }

  if (offenders.isEmpty) {
    stdout.writeln(
      'max-lines ratchet ok (threshold ${config.maxLines}, '
      '${oversized.length} baseline-oversized files).',
    );
    exit(0);
  }

  stderr.writeln(
    'max-lines ratchet failed: ${offenders.length} file(s) over '
    '${config.maxLines} lines without baseline room:',
  );
  for (final file in offenders.take(50)) {
    final allowed = baseline[file.path];
    final note = allowed == null
        ? 'new oversize'
        : 'grew from baseline $allowed';
    stderr.writeln('  ${file.lines}\t${file.path}\t($note)');
  }
  if (offenders.length > 50) {
    stderr.writeln('  ... ${offenders.length - 50} more');
  }
  stderr.writeln(
    'Split the file, or refresh baseline with '
    '`dart run tool/quality/check_max_lines.dart --write-baseline` '
    'only when intentionally accepting debt.',
  );
  exit(1);
}

class const _FileLines(final String path, final int lines);

class const _Args({
  required final int maxLines,
  required final List<String> roots,
  required final String? baseline,
  required final bool writeBaseline,
  required final bool listOversized,
}) {
  static _Args parse(List<String> args) {
    var maxLines = 500;
    var roots = <String>[
      'lib',
      'mobile/lib',
      'mobile/test',
      'rust/src',
      'rust/alera-cli/src',
      'rust/alera-cli/tests',
      'rust/alera-core/src',
      'test',
      'integration_test',
      'tool',
    ];
    String? baseline;
    var writeBaseline = false;
    var listOversized = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String value() {
        if (i + 1 >= args.length) {
          throw FormatException('Missing value for $arg');
        }
        return args[++i];
      }

      switch (arg) {
        case '--max-lines':
          maxLines = int.parse(value());
        case '--roots':
          roots = value().split(',').map((s) => s.trim()).toList();
        case '--baseline':
          baseline = value();
        case '--write-baseline':
          writeBaseline = true;
        case '--list-oversized':
          listOversized = true;
        case '-h' || '--help':
          stderr.writeln(
            'Usage: dart run tool/quality/check_max_lines.dart '
            '[--max-lines 500] [--write-baseline] [--list-oversized]',
          );
          exit(0);
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }

    return _Args(
      maxLines: maxLines,
      roots: roots,
      baseline: baseline,
      writeBaseline: writeBaseline,
      listOversized: listOversized,
    );
  }
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/AGENTS.md').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return Directory.current;
    }
    dir = parent;
  }
}

Map<String, int> _readBaseline(File file) {
  final map = <String, int>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final tab = trimmed.indexOf('\t');
    if (tab <= 0) {
      continue;
    }
    final lines = int.tryParse(trimmed.substring(0, tab));
    final path = trimmed.substring(tab + 1).trim();
    if (lines == null || path.isEmpty) {
      continue;
    }
    map[path] = lines;
  }
  return map;
}

bool _shouldScan(String relativePath) {
  final lower = relativePath.toLowerCase();
  if (lower.startsWith('lib/src/rust/api/') ||
      lower.endsWith('.g.dart') ||
      lower.endsWith('.freezed.dart') ||
      lower.endsWith('.mapper.dart') ||
      lower.contains('frb_generated') ||
      lower.endsWith('.pb.dart') ||
      lower.endsWith('.pbenum.dart') ||
      lower.endsWith('.pbjson.dart')) {
    return false;
  }
  return lower.endsWith('.dart') || lower.endsWith('.rs');
}

int _countLines(File file) {
  var count = 0;
  for (final _ in file.readAsLinesSync()) {
    count += 1;
  }
  return count;
}

String _posixRelative(Directory root, File file) {
  final relative = p.relative(file.absolute.path, from: root.absolute.path);
  return relative.replaceAll(r'\', '/');
}
