import 'package:dart_mappable/dart_mappable.dart';

part 'run_create_request.mapper.dart';

/// `isolated`: every task gets its own worktree and branch and integrates as
/// a squash commit. `shared`: workers share the run's workspace.
@MappableEnum()
enum RunIsolation { isolated, shared }

/// The `runs.create` payload. [requestId] makes a retried create idempotent.
@MappableClass()
class RunCreateRequest with RunCreateRequestMappable {
  const RunCreateRequest({
    required this.requestId,
    required this.workspaceId,
    required this.objective,
    this.recipeSource,
    this.isolation = RunIsolation.isolated,
    required this.coordinatorProfileId,
    this.roleProfiles = const <String, String>{},
    this.workerProfileId,
    this.maxConcurrent,
    this.approvalRequired = false,
  });

  final String requestId;
  final String workspaceId;
  final String objective;
  final Map<String, Object?>? recipeSource;
  final RunIsolation isolation;
  final String coordinatorProfileId;
  final Map<String, String> roleProfiles;
  final String? workerProfileId;
  final int? maxConcurrent;
  final bool approvalRequired;

  /// Shared runs take no recipe and no role bindings.
  Map<String, Object?> toPayload() => <String, Object?>{
    'requestId': requestId,
    'workspaceId': workspaceId,
    'objective': objective,
    'isolation': isolation.name,
    'coordinatorProfileId': coordinatorProfileId,
    if (isolation == RunIsolation.isolated) ...<String, Object?>{
      'recipeSource': ?recipeSource,
      if (roleProfiles.isNotEmpty) 'roleProfiles': roleProfiles,
    },
    'workerProfileId': ?workerProfileId,
    'maxConcurrent': ?maxConcurrent,
    'approvalRequired': approvalRequired,
  };
}

@MappableClass()
class RunCreated with RunCreatedMappable {
  const RunCreated({
    required this.runId,
    required this.status,
    this.isolation = RunIsolation.isolated,
    this.coordinatorTabId,
    this.coordinatorProfileId,
  });

  final String runId;
  final String status;
  final RunIsolation isolation;
  final String? coordinatorTabId;
  final String? coordinatorProfileId;
}

/// `runs.create` response: the run and, when the runtime launched it, the
/// coordinator terminal.
@MappableClass()
class RunCreateResult with RunCreateResultMappable {
  const RunCreateResult({required this.run, this.coordinator});

  static RunCreateResult fromJson(Map<String, Object?> json) =>
      RunCreateResultMapper.fromMap(json);

  final RunCreated run;
  final Map<String, Object?>? coordinator;

  String? get coordinatorError => coordinator?['error'] as String?;
}

/// `runs.source`: the commit a new run starts from.
@MappableClass()
class RunSource with RunSourceMappable {
  const RunSource({
    this.workspace = const <String, Object?>{},
    required this.sha,
    this.hasUncommittedChanges = false,
  });

  static RunSource fromJson(Map<String, Object?> json) =>
      RunSourceMapper.fromMap(json);

  final Map<String, Object?> workspace;
  final String sha;
  final bool hasUncommittedChanges;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

@MappableEnum()
enum RunControlAction { cancel, pause, resume, replan }

/// `runs.control` and `runs.retryCancellation` response.
@MappableClass()
class RunControlReceipt with RunControlReceiptMappable {
  const RunControlReceipt({
    required this.requestId,
    required this.runId,
    required this.action,
    this.sequence = 0,
    this.status = '',
    this.planRevision,
    this.changesRequested = false,
    this.coordinatorAction = 'none',
  });

  static RunControlReceipt fromJson(Map<String, Object?> json) =>
      RunControlReceiptMapper.fromMap(json);

  final String requestId;
  final String runId;
  final String action;
  final int sequence;
  final String status;
  final int? planRevision;
  final bool changesRequested;
  final String coordinatorAction;
}
