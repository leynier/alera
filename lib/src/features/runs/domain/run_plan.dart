import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'run_plan.mapper.dart';

@MappableClass()
class RunPlanStage with RunPlanStageMappable {
  const RunPlanStage({
    required this.id,
    this.title = '',
    this.roleIds = const <String>[],
    this.dependsOn = const <String>[],
    this.profile,
    this.fallbacks = const <String>[],
    this.gate = false,
    this.gateKind,
  });

  final String id;
  final String title;
  final List<String> roleIds;
  final List<String> dependsOn;
  final String? profile;
  final List<String> fallbacks;
  final bool gate;

  /// `foundation` or `product` for recipe stage gates.
  final String? gateKind;

  String get label => title.isEmpty ? id : title;
}

@MappableClass()
class RunPlanTask with RunPlanTaskMappable {
  const RunPlanTask({
    required this.id,
    this.taskId,
    required this.title,
    this.spec = '',
    required this.stageId,
    this.roleId,
    this.dependsOn = const <String>[],
    this.inputs,
    this.correctsTaskId,
    this.profileId,
    this.status,
  });

  final String id;
  final String? taskId;
  final String title;
  final String spec;
  final String stageId;
  final String? roleId;
  final List<String> dependsOn;

  /// The frozen contract inputs, as the coordinator proposed them.
  final Object? inputs;
  final String? correctsTaskId;
  final String? profileId;
  final String? status;
}

/// `runs.plan` and the plan embedded in a plan gate's detail.
@MappableClass()
class RunPlanView with RunPlanViewMappable {
  const RunPlanView({
    required this.runId,
    required this.revision,
    this.currentRevision,
    this.isolation = 'shared',
    this.runStatus = '',
    this.approvalRequired = false,
    this.stallPolicy = 'ask',
    this.maxConcurrent = 1,
    this.objective = '',
    this.sourceSha,
    this.digest = '',
    this.previousRevision,
    this.changeReason,
    this.changeTaskIds = const <String>[],
    this.placeholder = false,
    this.recipe,
    this.coordinatorProfileId,
    this.roleProfiles = const <String, String>{},
    this.stages = const <RunPlanStage>[],
    this.tasks = const <RunPlanTask>[],
    this.planGate,
  });

  static RunPlanView fromJson(Map<String, Object?> json) =>
      RunPlanViewMapper.fromMap(json);

  final String runId;
  final int revision;
  final int? currentRevision;
  final String isolation;
  final String runStatus;
  final bool approvalRequired;
  final String stallPolicy;
  final int maxConcurrent;
  final String objective;
  final String? sourceSha;
  final String digest;
  final int? previousRevision;
  final String? changeReason;
  final List<String> changeTaskIds;
  final bool placeholder;

  /// `{source, id, name, revision, digest}` of the frozen recipe.
  final Map<String, Object?>? recipe;
  final String? coordinatorProfileId;
  final Map<String, String> roleProfiles;
  final List<RunPlanStage> stages;
  final List<RunPlanTask> tasks;
  final RunGate? planGate;

  String? get recipeName => recipe?['name'] as String?;
}
