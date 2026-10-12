import 'package:alera_automations/alera_automations.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/runs/domain/run_detail_tab.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'activity_location.mapper.dart';

/// Where the Activity page is, including what each section had selected, so
/// switching sections and reopening the page both come back to the same place.
@MappableClass()
class ActivityLocation with ActivityLocationMappable {
  const ActivityLocation({
    this.visible = false,
    this.section = ActivitySection.runs,
    this.runs = const RunsLocation(),
    this.questions = const QuestionsLocation(),
    this.automations = const AutomationsLocation(),
  });
  final bool visible;
  final ActivitySection section;
  final RunsLocation runs;
  final QuestionsLocation questions;
  final AutomationsLocation automations;

  bool showing(ActivitySection value) => visible && section == value;
}

@MappableClass()
class RunsLocation with RunsLocationMappable {
  const RunsLocation({
    this.projectId,
    this.workspaceId,
    this.search = '',
    this.bucket,
    this.runId,
    this.tab = RunDetailTab.overview,
    this.taskId,
    this.gateId,
    this.gateFocusSequence = 0,
    this.timelineFilter = RunTimelineFilter.all,
  });
  final String? projectId;
  final String? workspaceId;
  final String search;
  final RunBucket? bucket;
  final String? runId;
  final RunDetailTab tab;
  final String? taskId;

  /// A gate Overview scrolls to; [gateFocusSequence] repeats the scroll when
  /// the same gate is focused again.
  final String? gateId;
  final int gateFocusSequence;
  final RunTimelineFilter timelineFilter;

  bool get filtered =>
      projectId != null ||
      workspaceId != null ||
      search.isNotEmpty ||
      bucket != null;
}

/// A request to open the question composer, optionally with a recipient.
class const InboxComposeRequest({final String? targetHandle});

@MappableClass()
class QuestionsLocation with QuestionsLocationMappable {
  const QuestionsLocation({
    this.inboxFilter,
    this.statusFilter,
    this.selectedThreadId,
    this.compose,
    this.composeSequence = 0,
  });
  final String? inboxFilter;
  final InboxQuestionStatus? statusFilter;
  final String? selectedThreadId;
  final InboxComposeRequest? compose;
  final int composeSequence;
}

@MappableClass()
class AutomationsLocation with AutomationsLocationMappable {
  const AutomationsLocation({
    this.scope = AutomationScope.all,
    this.filters = const AutomationCatalogFilters(),
    this.selectedId,
    this.selectedRunId,
    this.authoring,
    this.authoringSequence = 0,
    this.collapsedGroups = const <String>{},
  });
  final AutomationScope scope;
  final AutomationCatalogFilters filters;
  final String? selectedId;
  final String? selectedRunId;
  final AutomationAuthoringRequest? authoring;
  final int authoringSequence;

  /// Catalog group headers the user collapsed, by group key.
  final Set<String> collapsedGroups;
}
