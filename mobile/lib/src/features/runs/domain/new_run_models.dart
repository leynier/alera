import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';

/// Where a recipe comes from; sent back to the runtime exactly as listed.
class const RecipeSource(final Map<String, Object?> json) {
  /// The built-in single-stage template isolated runs default to.
  static const RecipeSource freeform = RecipeSource(<String, Object?>{
    'origin': 'builtIn',
    'id': 'freeform',
  });

  String get origin => json.optionalString('origin') ?? '';

  String get key =>
      '$origin:${json.optionalString('id') ?? json.optionalString('path') ?? ''}';

  String get originLabel => switch (origin) {
    'builtIn' => 'Built-in',
    'personal' => 'Personal',
    'project' => 'Project',
    _ => origin,
  };
}

/// One template of `recipes.catalog`.
class const RecipeSummary({
  required final RecipeSource source,
  required final String name,
  final String? description,
  final String? error,
}) {
  factory fromJson(Map<String, Object?> json) {
    final source = RecipeSource(asJsonMap(json['source']));
    return RecipeSummary(
      source: source,
      name:
          json.optionalString('name') ??
          source.json.optionalString('id') ??
          source.json.optionalString('path') ??
          'Recipe',
      description: json.optionalString('description'),
      error: json.optionalString('error'),
    );
  }

  /// `Freeform (Built-in)`.
  String get label => '$name (${source.originLabel})';
}

class const RecipeCatalog({
  final List<RecipeSummary> entries = const <RecipeSummary>[],
  final String? projectError,
}) {
  factory fromJson(Map<String, Object?> json) => RecipeCatalog(
    entries: <RecipeSummary>[
      for (final item in json.objectList('entries'))
        if (asJsonMap(asJsonMap(item)['source']).isNotEmpty)
          RecipeSummary.fromJson(asJsonMap(item)),
    ],
    projectError: json.optionalString('projectError'),
  );

  /// Templates that compiled and can start a run.
  List<RecipeSummary> get usable => <RecipeSummary>[
    for (final entry in entries)
      if (entry.error == null) entry,
  ];
}

/// `runs.source`: the commit an isolated run would start from.
class const RunSourceSnapshot({
  required final String sha,
  final bool hasUncommittedChanges = false,
}) {
  factory fromJson(Map<String, Object?> json) => RunSourceSnapshot(
    sha: json.optionalString('sha') ?? '',
    hasUncommittedChanges: json['hasUncommittedChanges'] == true,
  );
}

/// The `runs.create` payload. A shared run never names a recipe: the runtime
/// rejects one.
class const NewRunRequest({
  required final String requestId,
  required final String workspaceId,
  required final String objective,
  required final RunIsolation isolation,
  required final String coordinatorProfileId,
  final RecipeSource? recipeSource,
  final String? workerProfileId,
  final int? maxConcurrent,
  final bool approvalRequired = false,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'workspaceId': workspaceId,
    'objective': objective.trim(),
    'isolation': isolation.name,
    'coordinatorProfileId': coordinatorProfileId,
    if (isolation == RunIsolation.isolated) 'recipeSource': ?recipeSource?.json,
    'workerProfileId': ?workerProfileId,
    'maxConcurrent': ?maxConcurrent,
    'approvalRequired': approvalRequired,
  };
}

/// What `runs.create` reports: the new run and how its coordinator started.
class const NewRunResult({
  required final String runId,
  final String? coordinatorStatus,
  final String? coordinatorError,
}) {
  factory fromJson(Map<String, Object?> json) {
    final run = json.mapValue('run');
    final coordinator = asJsonMap(json['coordinator']);
    return NewRunResult(
      runId: run.requiredString('runId'),
      coordinatorStatus: coordinator.optionalString('status'),
      coordinatorError: coordinator.optionalString('error'),
    );
  }
}
