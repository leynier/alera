import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_agent_activity_sort.dart';

const _warmupRuns = 2;
const _measuredRuns = 5;

void main(List<String> args) {
  final outputPath = _parseOutputPath(args);
  final report = _runBenchmark();
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  if (outputPath != null) {
    File(outputPath).writeAsStringSync('$encoded\n');
  }
  stdout.writeln(encoded);
}

Map<String, Object?> _runBenchmark() {
  final now = DateTime.utc(2026, 7, 18, 12);
  const samples = <({int workspaces, int statuses})>[
    (workspaces: 8, statuses: 24),
    (workspaces: 32, statuses: 96),
    (workspaces: 128, statuses: 384),
    (workspaces: 512, statuses: 1_536),
    (workspaces: 1_024, statuses: 4_096),
  ];
  final reports = <Map<String, Object?>>[];

  for (var sample = 0; sample < samples.length; sample++) {
    final size = samples[sample];
    final statuses = [
      for (var index = 0; index < size.statuses; index++)
        _presence(index, size.workspaces, now),
    ];
    for (var warmup = 0; warmup < _warmupRuns; warmup++) {
      final original = _runOriginal(size.workspaces, statuses, now);
      final indexed = _runIndexed(size.workspaces, statuses, now);
      if (!_sameOutputs(original.values, indexed.values)) {
        throw StateError('attention outputs differ during warmup');
      }
    }

    final originalTimes = <int>[];
    final indexedTimes = <int>[];
    var outputsEqual = true;
    var originalChecksum = 0;
    var indexedChecksum = 0;
    for (var run = 0; run < _measuredRuns; run++) {
      late _AttentionRun original;
      late _AttentionRun indexed;
      final originalWatch = Stopwatch();
      final indexedWatch = Stopwatch();
      if (run.isEven) {
        originalWatch.start();
        original = _runOriginal(size.workspaces, statuses, now);
        originalWatch.stop();
        indexedWatch.start();
        indexed = _runIndexed(size.workspaces, statuses, now);
        indexedWatch.stop();
      } else {
        indexedWatch.start();
        indexed = _runIndexed(size.workspaces, statuses, now);
        indexedWatch.stop();
        originalWatch.start();
        original = _runOriginal(size.workspaces, statuses, now);
        originalWatch.stop();
      }
      originalTimes.add(originalWatch.elapsedMicroseconds);
      indexedTimes.add(indexedWatch.elapsedMicroseconds);
      originalChecksum = original.checksum;
      indexedChecksum = indexed.checksum;
      outputsEqual &= _sameOutputs(original.values, indexed.values);
    }
    if (!outputsEqual) {
      throw StateError('attention outputs differ during measurement');
    }

    final originalInspections = size.workspaces * size.statuses;
    final indexedInspections = size.statuses;
    reports.add({
      'sample': sample + 1,
      'workspaces': size.workspaces,
      'statuses': size.statuses,
      'originalStatusInspections': originalInspections,
      'indexedStatusInspections': indexedInspections,
      'indexedWorkspaceLookups': size.workspaces,
      'indexedTotalTheoreticalOperations': indexedInspections + size.workspaces,
      'outputsEqual': outputsEqual,
      'checksumsEqual': originalChecksum == indexedChecksum,
      'originalMicroseconds': originalTimes,
      'indexedMicroseconds': indexedTimes,
      'originalMedianMicroseconds': _median(originalTimes),
      'indexedMedianMicroseconds': _median(indexedTimes),
      'originalMadMicroseconds': _mad(originalTimes),
      'indexedMadMicroseconds': _mad(indexedTimes),
    });
  }

  return <String, Object?>{
    'warmupRunsPerSample': _warmupRuns,
    'measuredRunsPerSample': _measuredRuns,
    'timingUnit': 'microseconds',
    'timingOrder': 'alternates original and indexed per run',
    'samples': reports,
  };
}

_AttentionRun _runOriginal(
  int workspaceCount,
  List<AgentPresenceSummary> statuses,
  DateTime now,
) {
  final values = <String, MobileWorkspaceAttention>{};
  for (var workspace = 0; workspace < workspaceCount; workspace++) {
    final id = 'workspace-$workspace';
    values[id] = mobileWorkspaceAttention(
      workspaceId: id,
      statuses: statuses,
      now: now,
    );
  }
  return _AttentionRun(values: values);
}

_AttentionRun _runIndexed(
  int workspaceCount,
  List<AgentPresenceSummary> statuses,
  DateTime now,
) {
  final indexed = mobileWorkspaceAttentionByWorkspace(
    statuses: statuses,
    now: now,
  );
  final values = <String, MobileWorkspaceAttention>{};
  for (var workspace = 0; workspace < workspaceCount; workspace++) {
    final id = 'workspace-$workspace';
    values[id] = indexed[id] ?? MobileWorkspaceAttention.idle;
  }
  return _AttentionRun(values: values);
}

bool _sameOutputs(
  Map<String, MobileWorkspaceAttention> original,
  Map<String, MobileWorkspaceAttention> indexed,
) {
  if (original.length != indexed.length) return false;
  for (final entry in original.entries) {
    final indexedValue = indexed[entry.key];
    if (indexedValue == null ||
        entry.value.attentionClass != indexedValue.attentionClass ||
        entry.value.at != indexedValue.at) {
      return false;
    }
  }
  return true;
}

int _median(Iterable<int> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

int _mad(List<int> values) {
  final median = _median(values);
  return _median(values.map((value) => (value - median).abs()));
}

String? _parseOutputPath(List<String> args) {
  String? outputPath;
  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--output':
        if (index + 1 >= args.length) {
          throw ArgumentError('Missing path after --output');
        }
        outputPath = args[++index];
      case '-h' || '--help':
        stdout.writeln(
          'Usage: dart run tool/mobile_attention_benchmark.dart '
          '[--output path]',
        );
        exit(0);
      default:
        throw ArgumentError('Unknown argument: ${args[index]}');
    }
  }
  return outputPath;
}

class _AttentionRun {
  _AttentionRun({required this.values}) : checksum = _attentionChecksum(values);

  final Map<String, MobileWorkspaceAttention> values;
  final int checksum;
}

int _attentionChecksum(Map<String, MobileWorkspaceAttention> values) {
  var checksum = 0;
  for (final value in values.values) {
    checksum = checksum * 31 + value.attentionClass.index;
    checksum = checksum * 31 + (value.at?.microsecondsSinceEpoch ?? 0);
  }
  return checksum;
}

AgentPresenceSummary _presence(int index, int workspaceCount, DateTime now) {
  final stateStartedAt = index % 17 == 0
      ? null
      : now.subtract(
          Duration(minutes: index % 11 == 0 ? 31 : (index % 25) + 1),
        );
  return AgentPresenceSummary(
    terminalSessionId: 'terminal-$index',
    workspaceId: 'workspace-${index % workspaceCount}',
    tabId: 'tab-$index',
    agentType: 'codex',
    state: switch (index % 5) {
      0 => 'waiting',
      1 => 'blocked',
      2 => 'done',
      3 => 'working',
      _ => 'idle',
    },
    stateStartedAt: stateStartedAt,
  );
}
