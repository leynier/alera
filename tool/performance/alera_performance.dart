import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _PerformanceOptions.parse(arguments);
  final outputDirectory = Directory(options.outputDirectory);
  await outputDirectory.create(recursive: true);

  final runs = <Map<String, Object?>>[];
  for (var index = 0; index < options.runs; index += 1) {
    stdout.writeln('Alera Linux startup run ${index + 1}/${options.runs}');
    runs.add(await _captureRun(options, index + 1));
  }

  final summary = _summarize(runs);
  final budget = await _loadBudget(options.budgetPath);
  final violations = _budgetViolations(summary, budget);
  final report = <String, Object?>{
    'scenario': 'linux_startup',
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'sampleCount': runs.length,
    'runs': runs,
    'summary': summary,
    'budget': ?budget,
    'budgetViolations': violations,
  };
  final output = File('${outputDirectory.path}/startup_linux.json');
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  _printSummary(summary, violations);
  stdout.writeln('Performance report: ${output.path}');
  if (options.enforceBudget && violations.isNotEmpty) {
    exitCode = 2;
  }
}

Future<Map<String, Object?>> _captureRun(
  _PerformanceOptions options,
  int run,
) async {
  final process = await Process.start(
    options.flutterExecutable,
    <String>[
      'run',
      '--device-id',
      'linux',
      '--profile',
      '--dart-define=ALERA_PERF_TRACE=true',
    ],
    mode: ProcessStartMode.normal,
    environment: <String, String>{
      ...Platform.environment,
      'ALERA_FLAVOR': 'dev',
    },
  );

  final records = <Map<String, Object?>>[];
  final firstFrame = Completer<void>();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stdout.writeln(line);
        final record = _performanceRecord(line);
        if (record == null) {
          return;
        }
        records.add(record);
        if (record['name'] == 'first_frame_timing' && !firstFrame.isCompleted) {
          firstFrame.complete();
        }
      })
      .asFuture<void>();
  final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();

  try {
    await firstFrame.future.timeout(const Duration(minutes: 10));
    process.stdin.writeln('q');
    await process.stdin.flush();
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    throw StateError('Timed out waiting for Alera first-frame metrics.');
  }

  final processExitCode = await process.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  if (processExitCode != 0) {
    throw ProcessException(
      options.flutterExecutable,
      const <String>['run', '--device-id', 'linux', '--profile'],
      'Flutter exited with code $processExitCode.',
      processExitCode,
    );
  }
  return <String, Object?>{
    'run': run,
    'records': records,
    'metricsMicros': _metrics(records),
  };
}

Map<String, int> _metrics(List<Map<String, Object?>> records) {
  final byName = <String, Map<String, Object?>>{
    for (final record in records)
      if (record['name'] case final String name) name: record,
  };
  final firstFrame = byName['first_frame_timing'];
  final arguments = firstFrame?['arguments'];
  final timing = arguments is Map<String, dynamic>
      ? arguments
      : const <String, Object?>{};
  int elapsed(String name) => byName[name]?['elapsedMicros'] as int? ?? -1;
  int duration(String name) => timing[name] as int? ?? -1;
  final metrics = <String, int>{
    'runApp': elapsed('run_app_called'),
    'firstFramePresented': elapsed('first_frame_presented'),
    'firstFrameBuild': duration('buildMicros'),
    'firstFrameRaster': duration('rasterMicros'),
    'firstFrameTotal': duration('totalMicros'),
  };
  if (metrics.values.any((value) => value < 0)) {
    throw StateError('A performance run did not emit every required metric.');
  }
  return metrics;
}

Map<String, Object?> _summarize(List<Map<String, Object?>> runs) {
  final samples = <String, List<int>>{};
  for (final run in runs) {
    final metrics = run['metricsMicros']! as Map<String, int>;
    for (final entry in metrics.entries) {
      samples.putIfAbsent(entry.key, () => <int>[]).add(entry.value);
    }
  }
  return <String, Object?>{
    for (final entry in samples.entries) entry.key: _sampleSummary(entry.value),
  };
}

Map<String, Object?> _sampleSummary(List<int> values) {
  final sorted = List<int>.from(values)..sort();
  final median = _percentile(sorted, 0.5);
  final deviations =
      sorted.map((value) => (value - median).abs().round()).toList()..sort();
  return <String, Object?>{
    'samplesMicros': sorted,
    'medianMicros': median.round(),
    'p95Micros': _percentile(sorted, 0.95).round(),
    'p99Micros': _percentile(sorted, 0.99).round(),
    'madMicros': _percentile(deviations, 0.5).round(),
  };
}

double _percentile(List<int> sorted, double percentile) {
  if (sorted.length == 1) {
    return sorted.single.toDouble();
  }
  final position = percentile * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) {
    return sorted[lower].toDouble();
  }
  final fraction = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

Future<Map<String, Object?>?> _loadBudget(String? path) async {
  if (path == null) {
    return null;
  }
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('Performance budget does not exist: $path');
  }
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Performance budget must be a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _budgetViolations(
  Map<String, Object?> summary,
  Map<String, Object?>? budget,
) {
  if (budget == null) {
    return const <Map<String, Object?>>[];
  }
  final violations = <Map<String, Object?>>[];
  for (final entry in budget.entries) {
    final limit = entry.value;
    final metric = summary[entry.key];
    if (limit is! num || metric is! Map<String, Object?>) {
      continue;
    }
    final actual = metric['p95Micros']! as int;
    if (actual > limit) {
      violations.add(<String, Object?>{
        'metric': entry.key,
        'p95Micros': actual,
        'maxP95Micros': limit.round(),
      });
    }
  }
  return violations;
}

void _printSummary(
  Map<String, Object?> summary,
  List<Map<String, Object?>> violations,
) {
  for (final entry in summary.entries) {
    final metric = entry.value! as Map<String, Object?>;
    stdout.writeln(
      '${entry.key}: median ${metric['medianMicros']} µs, '
      'p95 ${metric['p95Micros']} µs, p99 ${metric['p99Micros']} µs, '
      'MAD ${metric['madMicros']} µs',
    );
  }
  for (final violation in violations) {
    stderr.writeln(
      'Budget exceeded for ${violation['metric']}: '
      '${violation['p95Micros']} > ${violation['maxP95Micros']} µs',
    );
  }
}

Map<String, Object?>? _performanceRecord(String line) {
  const marker = 'ALERA_PERF ';
  final markerIndex = line.indexOf(marker);
  if (markerIndex < 0) {
    return null;
  }
  final jsonStart = markerIndex + marker.length;
  try {
    final decoded = jsonDecode(line.substring(jsonStart));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

class _PerformanceOptions {
  const _PerformanceOptions({
    required this.flutterExecutable,
    required this.outputDirectory,
    required this.runs,
    required this.budgetPath,
    required this.enforceBudget,
  });

  final String flutterExecutable;
  final String outputDirectory;
  final int runs;
  final String? budgetPath;
  final bool enforceBudget;

  static _PerformanceOptions parse(List<String> arguments) {
    var flutterExecutable = 'flutter';
    var outputDirectory = '.dart_tool/performance';
    var runs = 5;
    String? budgetPath = 'tool/performance/linux_startup_budget.json';
    var enforceBudget = false;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--flutter' && index + 1 < arguments.length) {
        flutterExecutable = arguments[++index];
      } else if (argument == '--output' && index + 1 < arguments.length) {
        outputDirectory = arguments[++index];
      } else if (argument == '--runs' && index + 1 < arguments.length) {
        runs = int.parse(arguments[++index]);
      } else if (argument == '--budget' && index + 1 < arguments.length) {
        budgetPath = arguments[++index];
      } else if (argument == '--no-budget') {
        budgetPath = null;
      } else if (argument == '--enforce') {
        enforceBudget = true;
      } else {
        throw FormatException('Unknown or incomplete option: $argument');
      }
    }
    if (runs < 1 || runs > 20) {
      throw RangeError.range(runs, 1, 20, 'runs');
    }
    return _PerformanceOptions(
      flutterExecutable: flutterExecutable,
      outputDirectory: outputDirectory,
      runs: runs,
      budgetPath: budgetPath,
      enforceBudget: enforceBudget,
    );
  }
}
