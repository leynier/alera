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
    required this.input,
    required this.minLines,
    required this.worst,
  });

  final String input;
  final double minLines;
  final int worst;

  static CoverageArgs parse(List<String> args) {
    var input = 'coverage/lcov.info';
    var minLines = 0.0;
    var worst = 25;

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
        input = requireValue();
      } else if (arg == '--min-lines') {
        minLines = double.parse(requireValue());
      } else if (arg == '--worst') {
        worst = int.parse(requireValue());
      } else if (arg == '-h' || arg == '--help') {
        _printUsage();
        exit(0);
      } else {
        throw FormatException('Unknown argument: $arg');
      }
    }

    return CoverageArgs(input: input, minLines: minLines, worst: worst);
  }
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

  final file = File(parsed.input);
  if (!file.existsSync()) {
    stderr.writeln('Coverage file not found: ${parsed.input}');
    exitCode = 66;
    return;
  }

  final records = _readLcov(file);
  final totalFound = records.fold<int>(0, (sum, record) => sum + record.found);
  final totalHit = records.fold<int>(0, (sum, record) => sum + record.hit);
  final totalPercent = totalFound == 0 ? 100.0 : totalHit * 100 / totalFound;

  stdout.writeln(
    'total lines: ${_formatPercent(totalPercent)}% '
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

List<CoverageRecord> _readLcov(File file) {
  final records = <CoverageRecord>[];
  String? currentFile;
  var found = 0;
  var hit = 0;

  void flush() {
    final file = currentFile;
    if (file == null) {
      return;
    }
    if (_includeInCoverage(file)) {
      records.add(CoverageRecord(file: file, found: found, hit: hit));
    }
    currentFile = null;
    found = 0;
    hit = 0;
  }

  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      continue;
    }
    if (line.startsWith('LF:')) {
      found = int.parse(line.substring(3));
      continue;
    }
    if (line.startsWith('LH:')) {
      hit = int.parse(line.substring(3));
      continue;
    }
    if (line == 'end_of_record') {
      flush();
    }
  }
  flush();
  return records;
}

bool _includeInCoverage(String file) {
  return !(file.endsWith('.g.dart') || file.endsWith('.mapper.dart'));
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
    '[--input coverage/lcov.info] [--min-lines 65] [--worst 25]',
  );
}
