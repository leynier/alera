import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'activity_providers.g.dart';

/// Which part of Activity is open, kept per host while the app runs.
@Riverpod(keepAlive: true)
class MobileActivitySectionController
    extends _$MobileActivitySectionController {
  @override
  ActivitySection build(String hostId) => ActivitySection.runs;

  void select(ActivitySection section) => state = section;
}

/// Replies nobody has read yet, across every inbox of the host.
@riverpod
Future<int> mobileQuestionUnreadCount(Ref ref, String hostId) async {
  final summary = await ref.watch(mobileInboxSummaryProvider(hostId).future);
  return summary.fold<int>(0, (total, entry) => total + entry.unreadReplyCount);
}

/// Automations that are blocked or report a problem.
@riverpod
Future<int> mobileAutomationAttentionCount(Ref ref, String hostId) async {
  final catalog = await ref.watch(
    mobileAutomationCatalogProvider(hostId).future,
  );
  return catalog.where(AutomationBucket.needsAttention.contains).length;
}
