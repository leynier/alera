import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_notifications.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/shell/application/shell_overlay_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the inbox shares the page slot with the Run Board and Automations', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final inbox = container.read(inboxNavigationProvider.notifier);
    container.read(runBoardNavigationProvider.notifier).open();
    expect(container.read(shellOverlayPageProvider), ShellOverlayPage.runBoard);

    inbox.open();
    expect(container.read(runBoardNavigationProvider).visible, isFalse);
    expect(container.read(shellOverlayPageProvider), ShellOverlayPage.inbox);

    container.read(automationsNavigationProvider.notifier).open();
    expect(container.read(inboxNavigationProvider).visible, isFalse);
    expect(
      container.read(shellOverlayPageProvider),
      ShellOverlayPage.automations,
    );

    inbox.open();
    container.read(runBoardNavigationProvider.notifier).open();
    expect(container.read(inboxNavigationProvider).visible, isFalse);

    container.read(runBoardNavigationProvider.notifier).close();
    expect(container.read(shellOverlayPageProvider), ShellOverlayPage.none);
  });

  test('compose opens the page with a preselected recipient once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final inbox = container.read(inboxNavigationProvider.notifier);
    inbox.compose(targetHandle: 'term-1');
    final location = container.read(inboxNavigationProvider);
    expect(location.visible, isTrue);
    expect(location.compose?.targetHandle, 'term-1');
    expect(location.composeSequence, 1);
    inbox.consumeCompose();
    expect(container.read(inboxNavigationProvider).compose, isNull);
    inbox.selectThread('msg_q1');
    inbox.filterStatus(InboxQuestionStatus.pending);
    inbox.filterInbox('ext:ci');
    final filtered = container.read(inboxNavigationProvider);
    expect(filtered.selectedThreadId, isNull);
    expect(filtered.statusFilter, InboxQuestionStatus.pending);
    expect(filtered.inboxFilter, 'ext:ci');
  });

  test('only growth of unread replies while the inbox is hidden notifies', () {
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
