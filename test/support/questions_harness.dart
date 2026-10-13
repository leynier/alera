import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_test_client.dart';

/// Canned host with two questions and one agent that can be asked.
InboxTestClient questionsTestClient({
  String targetDeliveryMode = 'paste',
  String secondStatus = 'pending',
}) => InboxTestClient()
  ..respond('inbox.summary', <String, Object?>{
    'items': [
      {'inbox': 'ext:user', 'threadCount': 2, 'unreadReplyCount': 1},
      {'inbox': 'ext:ci', 'threadCount': 1, 'unreadReplyCount': 0},
    ],
    'revision': 3,
  })
  ..respond('inbox.threads', <String, Object?>{
    'items': [
      inboxThreadJson(status: 'answered', unread: 1),
      inboxThreadJson(
        threadId: 'msg_q2',
        status: secondStatus,
        subject: 'Rollback plan',
      ),
    ],
    'revision': 3,
  })
  ..respond('inbox.targets', <String, Object?>{
    'items': [
      {
        'handle': 'term-1',
        'sessionLive': true,
        'workspaceId': 'ws-1',
        'agent': 'claude',
        'deliveryMode': targetDeliveryMode,
        'tabTitle': 'Fix Login',
      },
    ],
  });

/// Activity on its Questions section, over [client].
Future<ProviderContainer> pumpQuestionsActivity(
  WidgetTester tester,
  InboxTestClient client,
) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      ...inboxClientOverrides(client),
      // The rail's other sections read the real runtime; keep them out.
      activityAttentionProvider.overrideWithValue(const ActivityAttention()),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(activityNavigationProvider.notifier)
      .open(ActivitySection.questions);
  addTearDown(client.events.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: ActivityPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
