import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/new_run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'mobile_new_run_form.g.dart';

/// Choices for Concurrent Workers.
const List<int> newRunConcurrencyChoices = <int>[1, 2, 3, 4, 6, 8];

/// What New Run has collected so far. [requestId] changes with every edit:
/// a retry of the same form replays the runtime's receipt instead of
/// creating a second run, and an edited form never reuses an old id.
class const NewRunDraft({
  required final String requestId,
  final String objective = '',
  final String? workspaceId,
  final RunIsolation isolation = RunIsolation.isolated,
  final RecipeSource? recipe,
  final String? coordinatorProfileId,
  final String? workerProfileId,
  final int maxConcurrent = 4,
  final bool approvalRequired = false,
  final bool submitting = false,
}) {
  bool get canSubmit =>
      !submitting &&
      objective.trim().isNotEmpty &&
      workspaceId != null &&
      coordinatorProfileId != null;

  NewRunRequest toRequest() => NewRunRequest(
    requestId: requestId,
    workspaceId: workspaceId!,
    objective: objective,
    isolation: isolation,
    coordinatorProfileId: coordinatorProfileId!,
    recipeSource: isolation == RunIsolation.isolated
        ? recipe ?? RecipeSource.freeform
        : null,
    workerProfileId: workerProfileId ?? coordinatorProfileId,
    maxConcurrent: maxConcurrent,
    approvalRequired: approvalRequired,
  );
}

@riverpod
class MobileNewRunForm extends _$MobileNewRunForm {
  static const Uuid _uuid = Uuid();

  @override
  NewRunDraft build(String hostId, {String? workspaceId}) =>
      NewRunDraft(requestId: _uuid.v4(), workspaceId: workspaceId);

  void setObjective(String value) => _edit(objective: value);

  void setWorkspace(String? value) => _edit(workspaceId: () => value);

  void setIsolation(RunIsolation value) => _edit(isolation: value);

  void setRecipe(RecipeSource? value) => _edit(recipe: () => value);

  void setCoordinator(String? value) =>
      _edit(coordinatorProfileId: () => value);

  void setWorker(String? value) => _edit(workerProfileId: () => value);

  void setMaxConcurrent(int value) => _edit(maxConcurrent: value);

  void setApprovalRequired(bool value) => _edit(approvalRequired: value);

  /// Creates the run. The draft keeps its request id on failure, so trying
  /// again after a lost reply returns the run that was already created.
  Future<NewRunResult?> submit() async {
    final draft = state;
    if (!draft.canSubmit) return null;
    state = _copy(draft, submitting: true);
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      return await repository.create(draft.toRequest());
    } finally {
      if (ref.mounted) state = _copy(state, submitting: false);
    }
  }

  void _edit({
    String? objective,
    String? Function()? workspaceId,
    RunIsolation? isolation,
    RecipeSource? Function()? recipe,
    String? Function()? coordinatorProfileId,
    String? Function()? workerProfileId,
    int? maxConcurrent,
    bool? approvalRequired,
  }) {
    final current = state;
    state = NewRunDraft(
      requestId: _uuid.v4(),
      objective: objective ?? current.objective,
      workspaceId: workspaceId == null ? current.workspaceId : workspaceId(),
      isolation: isolation ?? current.isolation,
      recipe: recipe == null ? current.recipe : recipe(),
      coordinatorProfileId: coordinatorProfileId == null
          ? current.coordinatorProfileId
          : coordinatorProfileId(),
      workerProfileId: workerProfileId == null
          ? current.workerProfileId
          : workerProfileId(),
      maxConcurrent: maxConcurrent ?? current.maxConcurrent,
      approvalRequired: approvalRequired ?? current.approvalRequired,
      submitting: current.submitting,
    );
  }

  NewRunDraft _copy(NewRunDraft draft, {required bool submitting}) =>
      NewRunDraft(
        requestId: draft.requestId,
        objective: draft.objective,
        workspaceId: draft.workspaceId,
        isolation: draft.isolation,
        recipe: draft.recipe,
        coordinatorProfileId: draft.coordinatorProfileId,
        workerProfileId: draft.workerProfileId,
        maxConcurrent: draft.maxConcurrent,
        approvalRequired: draft.approvalRequired,
        submitting: submitting,
      );
}
