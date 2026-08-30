import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = ResourceProfileOptions.parse(arguments);
  if (!Platform.isMacOS) {
    throw UnsupportedError('The resource profiler currently supports macOS.');
  }

  final runtimeDir = options.runtimeDirectory ?? _defaultRuntimeDirectory();
  final profiler = MacOsResourceProfiler(
    appName: options.appName,
    runtimeDirectory: runtimeDir,
    explicitAppPid: options.appPid,
  );
  final report = await profiler.capture(
    scenario: options.scenario,
    duration: options.duration,
    interval: options.interval,
    buildMode: options.buildMode,
  );

  final output = File(options.outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  _printSummary(report);
  stdout.writeln('Resource profile: ${output.path}');
}

final class MacOsResourceProfiler({
  required final String appName,
  required final String runtimeDirectory,
  final int? explicitAppPid,
}) {
  Future<Map<String, Object?>> capture({
    required String scenario,
    required Duration duration,
    required Duration interval,
    required String buildMode,
  }) async {
    final initialProcesses = await _readProcessTable();
    final appPid = explicitAppPid ?? _findAppPid(initialProcesses, appName);
    final hostPid = await _readRuntimeHostPid(runtimeDirectory);
    if (appPid == null) {
      throw StateError('Could not find the running app process for $appName.');
    }
    if (hostPid == null) {
      throw StateError(
        'Could not find runtime host metadata under $runtimeDirectory.',
      );
    }

    final samples = <Map<String, Object?>>[];
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed <= duration) {
      final processes = await _readProcessTable();
      samples.add(
        _captureSample(
          elapsed: stopwatch.elapsed,
          processes: processes,
          appPid: appPid,
          hostPid: hostPid,
        ),
      );
      final elapsedInInterval =
          stopwatch.elapsedMilliseconds % interval.inMilliseconds;
      final remaining = Duration(
        milliseconds: interval.inMilliseconds - elapsedInInterval,
      );
      if (stopwatch.elapsed + remaining > duration) {
        break;
      }
      await Future.pause(remaining);
    }
    stopwatch.stop();

    return <String, Object?>{
      'scenario': scenario,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': 'macos',
      'buildMode': buildMode,
      'durationMillis': stopwatch.elapsedMilliseconds,
      'intervalMillis': interval.inMilliseconds,
      'sampleCount': samples.length,
      'appPid': appPid,
      'runtimeHostPid': hostPid,
      'samples': samples,
      'summary': _summarize(samples),
    };
  }

  Map<String, Object?> _captureSample({
    required Duration elapsed,
    required List<ProcessRecord> processes,
    required int appPid,
    required int hostPid,
  }) {
    final byPid = <int, ProcessRecord>{
      for (final process in processes) process.pid: process,
    };
    final children = _childrenByParent(processes);
    final runtimeDescendants = _descendants(hostPid, children);
    final agentRoots = runtimeDescendants.where((pid) {
      final process = byPid[pid];
      return process != null && _isAgentCommand(process.command);
    });
    final agentPids = <int>{
      for (final root in agentRoots) root,
      for (final root in agentRoots) ..._descendants(root, children),
    };
    final terminalPids = runtimeDescendants.difference(agentPids);

    final flutterRoot = _ancestorMatching(
      appPid,
      byPid,
      (command) => command.contains('flutter_tools.snapshot run'),
    );
    final flutterPids = flutterRoot == null
        ? <int>{}
        : _descendants(flutterRoot, children)
              .followedBy(<int>[flutterRoot])
              .where((pid) => pid != appPid)
              .toSet();
    flutterPids.removeAll(runtimeDescendants);
    flutterPids.remove(hostPid);

    final buildRunnerRoots = processes
        .where((process) => process.command.contains('build_runner'))
        .map((process) => process.pid);
    final buildRunnerPids = <int>{
      for (final root in buildRunnerRoots) root,
      for (final root in buildRunnerRoots) ..._descendants(root, children),
    };

    final groups = <String, Set<int>>{
      'app': <int>{appPid},
      'runtimeHost': <int>{hostPid},
      'flutterTooling': flutterPids,
      'buildRunner': buildRunnerPids,
      'terminalProcesses': terminalPids,
      'agents': agentPids,
    };
    final trackedPids = groups.values.expand((pids) => pids).toSet();
    groups['trackedTotal'] = trackedPids;

    return <String, Object?>{
      'elapsedMillis': elapsed.inMilliseconds,
      'groups': <String, Object?>{
        for (final entry in groups.entries)
          entry.key: _measureGroup(entry.value, byPid),
      },
    };
  }
}

final class const ProcessRecord({
  required final int pid,
  required final int parentPid,
  required final double cpuPercent,
  required final int residentKilobytes,
  required final String command,
});

Future<List<ProcessRecord>> _readProcessTable() async {
  final result = await Process.run('ps', const <String>[
    '-axo',
    'pid=,ppid=,%cpu=,rss=,command=',
  ]);
  if (result.exitCode != 0) {
    throw ProcessException('ps', const <String>['-axo'], '${result.stderr}');
  }
  return const LineSplitter()
      .convert(result.stdout as String)
      .map(_parseProcessRecord)
      .whereType<ProcessRecord>()
      .toList(growable: false);
}

ProcessRecord? _parseProcessRecord(String line) {
  final match = RegExp(r'^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$')
      .firstMatch(line);
  if (match == null) {
    return null;
  }
  return ProcessRecord(
    pid: int.parse(match.group(1)!),
    parentPid: int.parse(match.group(2)!),
    cpuPercent: double.parse(match.group(3)!),
    residentKilobytes: int.parse(match.group(4)!),
    command: match.group(5)!,
  );
}

int? _findAppPid(List<ProcessRecord> processes, String appName) {
  final suffix = '/Contents/MacOS/$appName';
  final matches = processes.where(
    (process) => process.command == appName || process.command.endsWith(suffix),
  );
  if (matches.isEmpty) {
    return null;
  }
  return matches
      .reduce((left, right) => left.pid > right.pid ? left : right)
      .pid;
}

Future<int?> _readRuntimeHostPid(String runtimeDirectory) async {
  final file = File('$runtimeDirectory/host.json');
  if (!await file.exists()) {
    return null;
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    return null;
  }
  return switch (decoded['pid']) {
    final int pid => pid,
    final num pid => pid.round(),
    _ => null,
  };
}

Map<int, Set<int>> _childrenByParent(List<ProcessRecord> processes) {
  final children = <int, Set<int>>{};
  for (final process in processes) {
    children.putIfAbsent(process.parentPid, () => <int>{}).add(process.pid);
  }
  return children;
}

Set<int> _descendants(int root, Map<int, Set<int>> children) {
  final descendants = <int>{};
  final pending = <int>[...?children[root]];
  while (pending.isNotEmpty) {
    final pid = pending.removeLast();
    if (!descendants.add(pid)) {
      continue;
    }
    pending.addAll(children[pid] ?? const <int>{});
  }
  return descendants;
}

int? _ancestorMatching(
  int pid,
  Map<int, ProcessRecord> byPid,
  bool Function(String command) matches,
) {
  var current = byPid[pid];
  final visited = <int>{};
  while (current != null && visited.add(current.pid)) {
    if (matches(current.command)) {
      return current.pid;
    }
    current = byPid[current.parentPid];
  }
  return null;
}

bool _isAgentCommand(String command) {
  final executable = command.split(RegExp(r'\s+')).first.toLowerCase();
  final name = executable.split('/').last;
  return const <String>{
    'claude',
    'codex',
    'agy',
    'kimi',
    'grok',
    'antigravity',
    'minimax',
    'zai',
  }.contains(name);
}

Map<String, Object?> _measureGroup(
  Set<int> pids,
  Map<int, ProcessRecord> byPid,
) {
  final present = pids.map((pid) => byPid[pid]).whereType<ProcessRecord>();
  var cpuPercent = 0.0;
  var residentKilobytes = 0;
  var processCount = 0;
  for (final process in present) {
    cpuPercent += process.cpuPercent;
    residentKilobytes += process.residentKilobytes;
    processCount += 1;
  }
  return <String, Object?>{
    'processCount': processCount,
    'cpuPercent': _rounded(cpuPercent),
    'rssMiB': _rounded(residentKilobytes / 1024),
  };
}

Map<String, Object?> _summarize(List<Map<String, Object?>> samples) {
  final values = <String, Map<String, List<double>>>{};
  for (final sample in samples) {
    final groups = sample['groups']! as Map<String, Object?>;
    for (final groupEntry in groups.entries) {
      final metrics = groupEntry.value! as Map<String, Object?>;
      final groupValues = values.putIfAbsent(
        groupEntry.key,
        () => <String, List<double>>{},
      );
      for (final metric in const <String>[
        'processCount',
        'cpuPercent',
        'rssMiB',
      ]) {
        groupValues
            .putIfAbsent(metric, () => <double>[])
            .add((metrics[metric]! as num).toDouble());
      }
    }
  }
  return <String, Object?>{
    for (final groupEntry in values.entries)
      groupEntry.key: <String, Object?>{
        for (final metricEntry in groupEntry.value.entries)
          metricEntry.key: _sampleSummary(metricEntry.value),
      },
  };
}

Map<String, Object?> _sampleSummary(List<double> values) {
  final sorted = List<double>.from(values)..sort();
  return <String, Object?>{
    'median': _rounded(_percentile(sorted, 0.5)),
    'p95': _rounded(_percentile(sorted, 0.95)),
    'max': _rounded(sorted.last),
  };
}

double _percentile(List<double> sorted, double percentile) {
  if (sorted.length == 1) {
    return sorted.single;
  }
  final position = percentile * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final fraction = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

double _rounded(double value) => (value * 100).round() / 100;

String _defaultRuntimeDirectory() {
  final configured = Platform.environment['ALERA_RUNTIME_DIR'];
  if (configured != null && configured.trim().isNotEmpty) {
    return configured;
  }
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is required when --runtime-dir is omitted.');
  }
  return '$home/Library/Application Support/dev.leynier.alera.dev/terminal_host';
}

void _printSummary(Map<String, Object?> report) {
  final summary = report['summary']! as Map<String, Object?>;
  for (final entry in summary.entries) {
    final metrics = entry.value! as Map<String, Object?>;
    final cpu = metrics['cpuPercent']! as Map<String, Object?>;
    final rss = metrics['rssMiB']! as Map<String, Object?>;
    final count = metrics['processCount']! as Map<String, Object?>;
    stdout.writeln(
      '${entry.key}: CPU median ${cpu['median']}%, p95 ${cpu['p95']}%, '
      'max ${cpu['max']}%; RSS median ${rss['median']} MiB, '
      'p95 ${rss['p95']} MiB, max ${rss['max']} MiB; '
      'processes max ${count['max']}',
    );
  }
}

final class const ResourceProfileOptions({
  required final String scenario,
  required final String outputPath,
  required final Duration duration,
  required final Duration interval,
  required final String appName,
  required final String buildMode,
  final int? appPid,
  final String? runtimeDirectory,
}) {
  static ResourceProfileOptions parse(List<String> arguments) {
    var scenario = 'idle';
    var outputPath = '.dart_tool/performance/resources_idle.json';
    var duration = const Duration(seconds: 30);
    var interval = const Duration(seconds: 1);
    var appName = 'Alera Dev';
    var buildMode = 'debug';
    int? appPid;
    String? runtimeDirectory;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      String value() {
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value for $argument.');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--scenario':
          scenario = value();
        case '--output':
          outputPath = value();
        case '--duration-seconds':
          duration = Duration(seconds: int.parse(value()));
        case '--interval-ms':
          interval = Duration(milliseconds: int.parse(value()));
        case '--app-name':
          appName = value();
        case '--app-pid':
          appPid = int.parse(value());
        case '--build-mode':
          buildMode = value();
        case '--runtime-dir':
          runtimeDirectory = value();
        default:
          throw FormatException('Unknown option: $argument');
      }
    }
    if (duration < const Duration(seconds: 5)) {
      throw RangeError('duration must be at least 5 seconds');
    }
    if (interval < const Duration(milliseconds: 250)) {
      throw RangeError('interval must be at least 250 milliseconds');
    }
    final maximumSamples = duration.inMilliseconds / interval.inMilliseconds;
    if (maximumSamples > 3600) {
      throw RangeError('resource profiles are limited to 3600 samples');
    }
    return ResourceProfileOptions(
      scenario: scenario,
      outputPath: outputPath,
      duration: duration,
      interval: interval,
      appName: appName,
      buildMode: buildMode,
      appPid: appPid,
      runtimeDirectory: runtimeDirectory,
    );
  }
}
