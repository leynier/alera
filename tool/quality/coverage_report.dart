import 'dart:io';

class CoverageRecord {
  const CoverageRecord({
    required this.file,
    required this.found,
    required this.hit,
  });

  final String file;
  final int found;
  final int hit;

  int get missed => found - hit;
  double get percent => found == 0 ? 100 : hit * 100 / found;
}

class CoverageArgs {
  const CoverageArgs({
    required this.inputs,
    required this.minLines,
    required this.worst,
    required this.expectInputs,
  });

  final List<String> inputs;
  final double minLines;
  final int worst;
  final int? expectInputs;

  static CoverageArgs parse(List<String> args) {
    final inputs = <String>[];
    var minLines = 0.0;
    var worst = 25;
    int? expectInputs;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      String requireValue() {
        if (index + 1 >= args.length) {
          throw FormatException('Missing value for $arg');
        }
        index += 1;
        return args[index];
      }

      if (arg == '--input') {
        inputs.add(requireValue());
      } else if (arg == '--input-dir') {
        inputs.addAll(_lcovFilesIn(requireValue()));
      } else if (arg == '--min-lines') {
        minLines = double.parse(requireValue());
      } else if (arg == '--worst') {
        worst = int.parse(requireValue());
      } else if (arg == '--expect-inputs') {
        expectInputs = int.parse(requireValue());
      } else if (arg == '-h' || arg == '--help') {
        _printUsage();
        exit(0);
      } else {
        throw FormatException('Unknown argument: $arg');
      }
    }

    return CoverageArgs(
      inputs: inputs.isEmpty ? const <String>['coverage/lcov.info'] : inputs,
      minLines: minLines,
      worst: worst,
      expectInputs: expectInputs,
    );
  }
}

List<String> _lcovFilesIn(String directory) {
  final target = Directory(directory);
  if (!target.existsSync()) {
    throw FormatException('Coverage directory not found: $directory');
  }
  final files =
      target
          .listSync()
          .whereType<File>()
          .map((entity) => entity.path)
          .where((path) => path.endsWith('.info'))
          .toList()
        ..sort();
  return files;
}

void main(List<String> args) {
  CoverageArgs parsed;
  try {
    parsed = CoverageArgs.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
    return;
  }

  final files = <File>[];
  for (final input in parsed.inputs) {
    final file = File(input);
    if (!file.existsSync()) {
      stderr.writeln('Coverage file not found: $input');
      exitCode = 66;
      return;
    }
    files.add(file);
  }

  // Sharded runs pass one lcov file per shard. A missing shard would otherwise
  // just shrink the totals silently, so let the caller assert how many it
  // expects.
  final expectInputs = parsed.expectInputs;
  if (expectInputs != null && files.length != expectInputs) {
    stderr.writeln(
      'Expected $expectInputs coverage inputs but found ${files.length}: '
      '${parsed.inputs.join(', ')}',
    );
    exitCode = 1;
    return;
  }

  final records = _readLcov(files);

  // Without this a lost artifact, a shard that died before writing its lcov, or
  // a mistyped path yields zero records, which reads as 100% below and turns
  // the gate into a silent pass.
  if (records.isEmpty && parsed.minLines > 0) {
    stderr.writeln(
      'No maintained domain coverage records found in: '
      '${parsed.inputs.join(', ')}',
    );
    exitCode = 1;
    return;
  }

  final totalFound = records.fold<int>(0, (sum, record) => sum + record.found);
  final totalHit = records.fold<int>(0, (sum, record) => sum + record.hit);
  final totalPercent = totalFound == 0 ? 100.0 : totalHit * 100 / totalFound;

  stdout.writeln(
    'domain lines: ${_formatPercent(totalPercent)}% '
    '($totalHit/$totalFound)',
  );
  stdout.writeln('');
  stdout.writeln('by area:');
  for (final entry
      in _areaRecords(records).entries.toList()..sort(
        (left, right) => left.value.percent.compareTo(right.value.percent),
      )) {
    final record = entry.value;
    stdout.writeln(
      '${_formatPercent(record.percent).padLeft(6)}% '
      '${'${record.hit}/${record.found}'.padLeft(12)}  ${entry.key}',
    );
  }
  stdout.writeln('');
  stdout.writeln('worst files by missed lines:');
  for (final record in _worstRecords(records, parsed.worst)) {
    stdout.writeln(
      '${record.missed.toString().padLeft(4)} missed  '
      '${_formatPercent(record.percent).padLeft(6)}%  '
      '${'${record.hit}/${record.found}'.padLeft(12)}  ${record.file}',
    );
  }

  if (totalPercent + 0.0001 < parsed.minLines) {
    stderr.writeln(
      'Coverage ${_formatPercent(totalPercent)}% is below '
      '${_formatPercent(parsed.minLines)}%.',
    );
    exitCode = 1;
  }
}

/// Merges any number of lcov files into one record per source file.
///
/// Sharded test runs each report only the files their shard loaded, and a file
/// loaded by two shards appears in both with different hit counts. Summing the
/// per-record `LF:`/`LH:` summaries would therefore count shared files twice,
/// so hits are unioned per line via `DA:` instead. Flutter collects coverage
/// with `forceCompile`, so every shard that loads a file reports the same line
/// set and the union is exact rather than approximate.
List<CoverageRecord> _readLcov(List<File> files) {
  final hitsByFile = <String, Map<int, int>>{};
  final summaryByFile = <String, List<int>>{};

  for (final file in files) {
    String? currentFile;
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('SF:')) {
        currentFile = _normalizePath(line.substring(3));
        hitsByFile.putIfAbsent(currentFile, () => <int, int>{});
        continue;
      }
      if (currentFile == null) {
        continue;
      }
      if (line.startsWith('DA:')) {
        final separator = line.indexOf(',');
        if (separator < 0) {
          continue;
        }
        final lineNumber = int.parse(line.substring(3, separator));
        final hits = int.parse(line.substring(separator + 1));
        final lineHits = hitsByFile[currentFile]!;
        lineHits[lineNumber] = (lineHits[lineNumber] ?? 0) + hits;
        continue;
      }
      // Fallback for producers that emit only the summary lines: without it
      // such a record would silently report zero lines found.
      if (line.startsWith('LF:')) {
        final summary = summaryByFile.putIfAbsent(
          currentFile,
          () => <int>[0, 0],
        );
        summary[0] = int.parse(line.substring(3));
        continue;
      }
      if (line.startsWith('LH:')) {
        final summary = summaryByFile.putIfAbsent(
          currentFile,
          () => <int>[0, 0],
        );
        summary[1] = int.parse(line.substring(3));
        continue;
      }
      if (line == 'end_of_record') {
        currentFile = null;
      }
    }
  }

  final records = <CoverageRecord>[];
  for (final entry in hitsByFile.entries) {
    if (!_includeInCoverage(entry.key)) {
      continue;
    }
    if (entry.value.isEmpty) {
      final summary = summaryByFile[entry.key];
      if (summary != null) {
        records.add(
          CoverageRecord(file: entry.key, found: summary[0], hit: summary[1]),
        );
      }
      continue;
    }
    records.add(
      CoverageRecord(
        file: entry.key,
        found: entry.value.length,
        hit: entry.value.values.where((hits) => hits > 0).length,
      ),
    );
  }
  return records;
}

/// Guards the `_includeInCoverage` prefix match: a Windows-style or absolute
/// path would match nothing, leaving zero records and a vacuously passing gate.
String _normalizePath(String file) {
  var path = file.replaceAll(r'\', '/');
  final root = '${Directory.current.path.replaceAll(r'\', '/')}/';
  if (path.startsWith(root)) {
    path = path.substring(root.length);
  }
  if (path.startsWith('./')) {
    path = path.substring(2);
  }
  return path;
}

bool _includeInCoverage(String file) {
  return file.startsWith('lib/src/features/') &&
      file.contains('/domain/') &&
      !file.endsWith('.g.dart') &&
      !file.endsWith('.mapper.dart');
}

Map<String, CoverageRecord> _areaRecords(List<CoverageRecord> records) {
  final foundByArea = <String, int>{};
  final hitByArea = <String, int>{};
  for (final record in records) {
    final area = _areaFor(record.file);
    foundByArea[area] = (foundByArea[area] ?? 0) + record.found;
    hitByArea[area] = (hitByArea[area] ?? 0) + record.hit;
  }
  return <String, CoverageRecord>{
    for (final area in foundByArea.keys)
      area: CoverageRecord(
        file: area,
        found: foundByArea[area]!,
        hit: hitByArea[area] ?? 0,
      ),
  };
}

String _areaFor(String file) {
  final path = file.startsWith('lib/src/')
      ? file.substring('lib/src/'.length)
      : file;
  final parts = path.split('/');
  if (parts.length >= 2 && parts.first == 'features') {
    return '${parts[0]}/${parts[1]}';
  }
  if (parts.isEmpty || parts.first.isEmpty) {
    return '(unknown)';
  }
  return parts.first;
}

List<CoverageRecord> _worstRecords(List<CoverageRecord> records, int count) {
  final sorted = records.where((record) => record.found > 0).toList()
    ..sort((left, right) {
      final missed = right.missed.compareTo(left.missed);
      if (missed != 0) {
        return missed;
      }
      return left.percent.compareTo(right.percent);
    });
  return sorted.take(count).toList(growable: false);
}

String _formatPercent(double value) => value.toStringAsFixed(2);

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/quality/coverage_report.dart '
    '[--input coverage/lcov.info] [--input-dir coverage-shards] '
    '[--expect-inputs 4] [--min-lines 100] [--worst 25]\n'
    '\n'
    '--input may be repeated, and --input-dir adds every *.info file in a '
    'directory. Multiple inputs are merged per source line, so a file covered '
    'by more than one shard is counted once.',
  );
}
