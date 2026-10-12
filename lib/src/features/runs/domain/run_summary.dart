import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'run_summary.mapper.dart';

/// Where a run sits on the board: needs a person, still moving, or done.
@MappableEnum()
enum RunBucket { attention, active, history }

/// Resumes `runs.board` after the last row of a page.
@MappableClass()
class RunBoardCursor with RunBoardCursorMappable {
  const RunBoardCursor({
    required this.createdAt,
    required this.id,
    required this.revision,
  });

  final String createdAt;
  final String id;
  final int revision;
}

class RunBoardQuery {
  const RunBoardQuery({
    this.projectId,
    this.workspaceId,
    this.search,
    this.bucket,
    this.cursor,
    this.limit = 50,
  });

  final String? projectId;
  final String? workspaceId;
  final String? search;
  final RunBucket? bucket;
  final RunBoardCursor? cursor;
  final int limit;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': ?projectId,
    'workspaceId': ?workspaceId,
    'search': ?search,
    'bucket': ?bucket?.name,
    'cursor': ?cursor?.toMap(),
    'limit': limit,
  };
}

/// A due gate named on a board row, newest first, so a click can open it
/// without reading the run's gates.
@MappableClass()
class RunPendingGateRef with RunPendingGateRefMappable {
  const RunPendingGateRef({required this.id, required this.kind, this.taskId});

  final String id;
  final RunGateKind kind;
  final String? taskId;
}

@MappableClass()
class RunBoardCounts with RunBoardCountsMappable {
  const RunBoardCounts({this.attention = 0, this.active = 0, this.history = 0});

  final int attention;
  final int active;
  final int history;
}

/// One row of `runs.board`, also the `run` of a snapshot.
@MappableClass()
class RunSummary with RunSummaryMappable {
  const RunSummary({
    required this.id,
    required this.objective,
    required this.status,
    required this.bucket,
    required this.workspaceId,
    this.workspaceName,
    this.projectId,
    this.projectName,
    required this.createdAt,
    required this.lastActivityAt,
    this.completedAt,
    this.planGatePending = false,
    this.isolation = 'shared',
    this.approvalRequired = false,
    this.planRevision,
    this.attentionReason,
    this.coordinatorState = 'none',
    this.pausedBy,
    this.controlSequence = 0,
    this.pendingGateKinds = const <String>[],
    this.taskCount = 0,
    this.completedCount = 0,
    this.runningCount = 0,
    this.failedCount = 0,
    this.stalledCount = 0,
    this.blockedCount = 0,
    this.pendingGateCount = 0,
    this.cleanupAttention = false,
    this.cleanupApplying = false,
    this.pendingGates = const <RunPendingGateRef>[],
  });

  static RunSummary fromJson(Map<String, Object?> json) =>
      RunSummaryMapper.fromMap(json);

  final String id;
  final String objective;
  final String status;
  final RunBucket bucket;
  final String workspaceId;
  final String? workspaceName;
  final String? projectId;
  final String? projectName;
  final String createdAt;
  final String lastActivityAt;
  final String? completedAt;
  final bool planGatePending;
  final String isolation;
  final bool approvalRequired;
  final int? planRevision;
  final String? attentionReason;
  final String coordinatorState;
  final String? pausedBy;
  final int controlSequence;
  final List<String> pendingGateKinds;
  final int taskCount;
  final int completedCount;
  final int runningCount;
  final int failedCount;
  final int stalledCount;
  final int blockedCount;
  final int pendingGateCount;
  final bool cleanupAttention;
  final bool cleanupApplying;

  /// At most five; absent from older hosts.
  final List<RunPendingGateRef> pendingGates;

  bool get isolated => isolation == 'isolated';

  bool get finished =>
      status == 'completed' || status == 'failed' || status == 'cancelled';
}

/// One page of `runs.board`.
@MappableClass()
class RunBoardPage with RunBoardPageMappable {
  const RunBoardPage({
    required this.revision,
    this.counts = const RunBoardCounts(),
    this.items = const <RunSummary>[],
    this.nextCursor,
  });

  static RunBoardPage fromJson(Map<String, Object?> json) =>
      RunBoardPageMapper.fromMap(json);

  final int revision;
  final RunBoardCounts counts;
  final List<RunSummary> items;
  final RunBoardCursor? nextCursor;
}

/// The runtime stamps rows with SQLite `datetime('now')`, UTC without a zone
/// (`2026-09-30 14:10:00`); ISO strings with a zone pass through.
DateTime? parseRunTimestamp(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final zoned = trimmed.contains('T')
      ? trimmed
      : '${trimmed.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(zoned);
}

Map<String, Object?> runJsonObject(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Runs payload must be an object.');
  }
  return Map<String, Object?>.from(payload);
}
