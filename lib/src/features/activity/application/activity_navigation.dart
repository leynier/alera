import 'package:alera/src/features/activity/domain/activity_location.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'activity_navigation.g.dart';

/// Where the Activity page is. Nothing here selects a workspace: Open
/// Workspace and Open Terminal are explicit actions that close the page.
// Retain only navigation, never runtime snapshots or subscriptions.
@Riverpod(keepAlive: true)
class ActivityNavigation extends _$ActivityNavigation {
  @override
  ActivityLocation build() => const ActivityLocation();

  /// Shows the page, on [section] when given, else where it was left.
  void open([ActivitySection? section]) =>
      state = state.copyWith(visible: true, section: section ?? state.section);

  void close() => state = state.copyWith(visible: false);

  void showSection(ActivitySection section) =>
      state = state.copyWith(section: section);

  // Runs.

  /// Selects a run on its Overview. Never selects a workspace.
  void selectRun(String? id) => state = state.copyWith.runs(
    runId: id,
    tab: RunDetailTab.overview,
    taskId: null,
    gateId: null,
  );

  void showRunTab(RunDetailTab tab) =>
      state = state.copyWith.runs(tab: tab, gateId: null);

  /// Opens a task in the Tasks tab, or the stage list when [id] is null.
  void selectTask(String? id) => state = state.copyWith.runs(
    tab: RunDetailTab.tasks,
    taskId: id,
    gateId: null,
  );

  /// Opens Activity on a run's Overview, scrolled to [gateId].
  void focusGate(String runId, String gateId) {
    open(ActivitySection.runs);
    state = state.copyWith.runs(
      runId: runId,
      tab: RunDetailTab.overview,
      taskId: null,
      gateId: gateId,
      gateFocusSequence: state.runs.gateFocusSequence + 1,
    );
  }

  void filterTimeline(RunTimelineFilter filter) =>
      state = state.copyWith.runs(timelineFilter: filter);

  void searchRuns(String value) => state = state.copyWith.runs(search: value);

  void filterRunBucket(RunBucket? bucket) =>
      state = state.copyWith.runs(bucket: bucket);

  void filterRunProject(String? id) =>
      state = state.copyWith.runs(projectId: id, workspaceId: null);

  void filterRunWorkspace(String? id) =>
      state = state.copyWith.runs(workspaceId: id);

  void clearRunFilters() => state = state.copyWith.runs(
    projectId: null,
    workspaceId: null,
    search: '',
    bucket: null,
  );

  // Questions.

  /// A thread is a question, so selecting one always shows Questions.
  void selectThread(String? threadId) =>
      state = state.copyWith.questions(selectedThreadId: threadId);

  /// Opens the page on Questions, where replies are read.
  void openQuestions() => open(ActivitySection.questions);

  void filterInbox(String? inbox) => state = state.copyWith.questions(
    inboxFilter: inbox,
    selectedThreadId: null,
  );

  void filterQuestionStatus(InboxQuestionStatus? status) =>
      state = state.copyWith.questions(statusFilter: status);

  /// Opens Questions and asks the section to show the composer once mounted.
  void compose({String? targetHandle}) {
    openQuestions();
    state = state.copyWith.questions(
      compose: InboxComposeRequest(targetHandle: targetHandle),
      composeSequence: state.questions.composeSequence + 1,
    );
  }

  void consumeCompose() => state = state.copyWith.questions(compose: null);

  // Automations.

  /// Opens Automations; a [scope] starts from that scope with no filters.
  void openAutomations({
    AutomationScope? scope,
    AutomationCatalogFilters? filters,
  }) {
    open(ActivitySection.automations);
    state = state.copyWith.automations(
      scope: scope ?? state.automations.scope,
      filters:
          filters ??
          (scope == null
              ? state.automations.filters
              : const AutomationCatalogFilters()),
    );
  }

  void setAutomationScope(AutomationScope scope) =>
      state = state.copyWith.automations(scope: scope);

  void setAutomationFilters(AutomationCatalogFilters filters) =>
      state = state.copyWith.automations(filters: filters);

  void clearAutomationFilters() => state = state.copyWith.automations(
    filters: const AutomationCatalogFilters(),
  );

  void selectAutomation(String? id) =>
      state = state.copyWith.automations(selectedId: id, selectedRunId: null);

  void selectAutomationRun(String automationId, String? runId) => state = state
      .copyWith
      .automations(selectedId: automationId, selectedRunId: runId);

  /// Opens Automations and asks the section to start authoring once mounted.
  void startAuthoring(
    AutomationAuthoringRequest request, {
    AutomationScope? scope,
  }) {
    open(ActivitySection.automations);
    state = state.copyWith.automations(
      scope: scope ?? state.automations.scope,
      authoring: request,
      authoringSequence: state.automations.authoringSequence + 1,
    );
  }

  void consumeAuthoring() =>
      state = state.copyWith.automations(authoring: null);
}
