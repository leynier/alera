import 'package:alera/src/design_system/badges/alera_attention_chip.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_attention_control.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/inbox/application/inbox_notifications.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/shell/application/shell_overlay_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity is the only shell page and reopens where it was left', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier);
    expect(container.read(shellOverlayPageProvider), ShellOverlayPage.none);

    navigation.open();
    expect(container.read(shellOverlayPageProvider), ShellOverlayPage.activity);
    expect(
      container.read(activityNavigationProvider).section,
      ActivitySection.runs,
    );

    navigation.showSection(ActivitySection.automations);
    navigation.close();
    expect(container.read(shellOverlayPageProvider), ShellOverlayPage.none);
    navigation.open();
    expect(
      container.read(activityNavigationProvider).section,
      ActivitySection.automations,
    );
    navigation.open(ActivitySection.questions);
    expect(
      container.read(activityNavigationProvider).section,
      ActivitySection.questions,
    );
  });

  test('switching sections keeps what each section had selected', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier)
      ..open(ActivitySection.runs)
      ..selectRun('run-1')
      ..selectTask('task-2')
      ..selectThread('msg_q1')
      ..selectAutomationRun('nightly', 'automation-run-3');

    for (final section in ActivitySection.values) {
      navigation.showSection(section);
      final location = container.read(activityNavigationProvider);
      expect(location.section, section);
      expect(location.runs.runId, 'run-1');
      expect(location.runs.taskId, 'task-2');
      expect(location.questions.selectedThreadId, 'msg_q1');
      expect(location.automations.selectedId, 'nightly');
      expect(location.automations.selectedRunId, 'automation-run-3');
    }
  });

  test('compose opens Questions with a preselected recipient once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier);
    navigation.compose(targetHandle: 'term-1');
    final location = container.read(activityNavigationProvider);
    expect(location.visible, isTrue);
    expect(location.section, ActivitySection.questions);
    expect(location.questions.compose?.targetHandle, 'term-1');
    expect(location.questions.composeSequence, 1);
    navigation.consumeCompose();
    expect(
      container.read(activityNavigationProvider).questions.compose,
      isNull,
    );
    navigation
      ..selectThread('msg_q1')
      ..filterQuestionStatus(InboxQuestionStatus.pending)
      ..filterInbox('ext:ci');
    final filtered = container.read(activityNavigationProvider).questions;
    expect(filtered.selectedThreadId, isNull);
    expect(filtered.statusFilter, InboxQuestionStatus.pending);
    expect(filtered.inboxFilter, 'ext:ci');
  });

  test('selecting a question, composing or a notification shows Questions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier);
    ActivitySection section() =>
        container.read(activityNavigationProvider).section;

    navigation.open(ActivitySection.runs);
    navigation.compose(targetHandle: 'term-1');
    expect(section(), ActivitySection.questions);
    navigation.selectThread('msg_q1');
    expect(
      container.read(activityNavigationProvider).questions.selectedThreadId,
      'msg_q1',
    );

    navigation.close();
    navigation.open(ActivitySection.runs);
    navigation.openQuestions();
    expect(section(), ActivitySection.questions);
    expect(container.read(activityNavigationProvider).visible, isTrue);
  });

  test('automations open on a scope and authoring is consumed once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(activityNavigationProvider.notifier);
    const scope = AutomationScope(
      kind: AutomationScopeKind.project,
      id: 'project-1',
    );
    navigation.setAutomationFilters(
      const AutomationCatalogFilters(search: 'nightly'),
    );
    navigation.openAutomations(scope: scope);
    var location = container.read(activityNavigationProvider);
    expect(location.section, ActivitySection.automations);
    expect(location.automations.scope, scope);
    expect(location.automations.filters.isFiltered, isFalse);

    navigation.startAuthoring(
      const AutomationAuthoringRequest(projectId: 'project-1'),
    );
    location = container.read(activityNavigationProvider);
    expect(location.automations.authoring?.projectId, 'project-1');
    expect(location.automations.authoringSequence, 1);
    navigation.consumeAuthoring();
    expect(
      container.read(activityNavigationProvider).automations.authoring,
      isNull,
    );
  });

  test('a section the host cannot answer is left out of the total', () {
    const attention = ActivityAttention(
      questions: 2,
      automations: 1,
      unavailable: <ActivitySection>{ActivitySection.runs},
    );
    expect(attention.total, 3);
    expect(
      activityAttentionTooltip(attention),
      'Open Activity · 3 items need attention · Runs unavailable',
    );
    expect(activityAttentionTone(attention), AleraAttentionTone.warning);
    expect(
      activityAttentionTooltip(
        const ActivityAttention(
          unavailable: <ActivitySection>{
            ActivitySection.runs,
            ActivitySection.questions,
            ActivitySection.automations,
          },
        ),
      ),
      'Open Activity · Runs, Questions and Automations unavailable',
    );
    expect(
      activityAttentionTone(const ActivityAttention(questions: 1)),
      AleraAttentionTone.accent,
    );
    expect(
      activityAttentionTone(const ActivityAttention()),
      AleraAttentionTone.muted,
    );
    expect(
      activityAttentionTooltip(const ActivityAttention()),
      'Open Activity',
    );
    expect(AleraAttentionChip.formatCount(1000), '999+');
  });

  test('only growth of unread replies while Questions is hidden notifies', () {
    final tracker = InboxReplyNotificationTracker();
    expect(tracker.observe(4, inboxVisible: false), 0);
    expect(tracker.observe(6, inboxVisible: false), 2);
    expect(tracker.observe(6, inboxVisible: false), 0);
    expect(tracker.observe(7, inboxVisible: true), 0);
    expect(tracker.observe(3, inboxVisible: false), 0);
    expect(tracker.observe(4, inboxVisible: false), 1);
  });

  test('notifications carry no reply text and are recognizable', () {
    final notification = inboxReplyNotification(2);
    expect(notification.title, 'New Inbox Reply');
    expect(notification.body, contains('2 questions'));
    expect(isInboxNotificationPayload(notification.payload), isTrue);
    expect(isInboxNotificationPayload('{"terminalSessionId":"x"}'), isFalse);
    expect(isInboxNotificationPayload('not json'), isFalse);
  });
}
