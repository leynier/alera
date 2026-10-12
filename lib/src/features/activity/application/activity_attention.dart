import 'package:alera_automations/alera_automations.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/runs/application/run_board_pages.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'activity_attention.g.dart';

/// What needs the user across Activity: runs needing attention, unread
/// question replies and automations needing attention. A section the host
/// cannot answer counts as zero and is listed in [unavailable], so the total
/// never guesses.
class const ActivityAttention({
  this.runs = 0,
  this.questions = 0,
  this.automations = 0,
  this.unavailable = const <ActivitySection>{},
}) {
  final int runs;
  final int questions;
  final int automations;
  final Set<ActivitySection> unavailable;

  int get total => runs + questions + automations;

  /// Blocked or failing work, as opposed to replies waiting to be read.
  bool get hasBlockingWork => runs + automations > 0;

  int countFor(ActivitySection section) => switch (section) {
    ActivitySection.runs => runs,
    ActivitySection.questions => questions,
    ActivitySection.automations => automations,
  };

  @override
  bool operator ==(Object other) =>
      other is ActivityAttention &&
      other.runs == runs &&
      other.questions == questions &&
      other.automations == automations &&
      other.unavailable.length == unavailable.length &&
      other.unavailable.containsAll(unavailable);

  @override
  int get hashCode => Object.hash(
    runs,
    questions,
    automations,
    Object.hashAllUnordered(unavailable),
  );
}

@riverpod
ActivityAttention activityAttention(Ref ref) {
  final runs = ref.watch(runBoardAttentionProvider);
  final questions = ref.watch(inboxSummaryProvider);
  final automations = ref.watch(automationCatalogProvider);
  return ActivityAttention(
    runs: runs.hasError ? 0 : runs.value?.counts.attention ?? 0,
    questions: questions.hasError ? 0 : questions.value?.unreadReplyCount ?? 0,
    automations: automations.hasError
        ? 0
        : (automations.value ?? const <AutomationRecord>[])
              .where(AutomationBucket.needsAttention.contains)
              .length,
    unavailable: <ActivitySection>{
      if (runs.hasError) ActivitySection.runs,
      if (questions.hasError) ActivitySection.questions,
      if (automations.hasError) ActivitySection.automations,
    },
  );
}
