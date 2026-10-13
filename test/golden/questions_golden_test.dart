import 'package:alchemist/alchemist.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';
import 'alera_golden_harness.dart';

// Old enough that every time label is a calendar date, so the image does not
// depend on the day the test runs.
const String _asked = '2025-03-01 12:00:00';
const String _answered = '2025-03-01 12:02:00';

Map<String, Object?> _thread() => <String, Object?>{
  ...inboxThreadJson(status: 'answered', unread: 1),
  'createdAt': _asked,
  'lastActivityAt': _answered,
  'deliveryMode': 'pasted_now',
};

InboxTestClient _client() => InboxTestClient()
  ..deliverySupported = true
  ..respond('inbox.summary', <String, Object?>{
    'items': [
      {'inbox': 'ext:user', 'threadCount': 1, 'unreadReplyCount': 1},
    ],
  })
  ..respond('inbox.threads', <String, Object?>{
    'items': [_thread()],
  })
  ..respond('inbox.thread', <String, Object?>{
    'thread': _thread(),
    'messages': [
      <String, Object?>{
        'kind': 'question',
        'status': 'answered',
        'message': <String, Object?>{
          'id': 'msg_q1',
          'from_handle': 'ext:user',
          'to_handle': 'term-1',
          'body':
              'Which auth flow do you want for the CLI: device code or PKCE?',
          'read': true,
          'created_at': _asked,
        },
      },
      <String, Object?>{
        'kind': 'reply',
        'message': <String, Object?>{
          'id': 'msg_r1',
          'from_handle': 'term-1',
          'to_handle': 'ext:user',
          'body': 'Device code. PKCE needs a browser on the same machine.',
          'read': false,
          'created_at': _answered,
        },
      },
    ],
    'recipient': <String, Object?>{
      'handle': 'term-1',
      'sessionLive': true,
      'agent': 'claude',
      'deliveryMode': 'pasted_now',
      'acceptsQueuedInput': true,
    },
    'revision': 3,
  });

void main() {
  runAleraGoldenTests(() {
    for (final scenario in [
      (name: 'questions_thread', width: 1100.0, height: 800.0, scale: 1.0),
      (
        name: 'questions_thread_compact_scaled',
        width: 420.0,
        height: 900.0,
        scale: 2.0,
      ),
    ]) {
      goldenTest(
        scenario.name,
        fileName: scenario.name,
        constraints: BoxConstraints.tightFor(
          width: scenario.width,
          height: scenario.height,
        ),
        pumpBeforeTest: (tester) async {
          await tester.pumpAndSettle();
        },
        builder: () {
          final client = _client();
          final container = ProviderContainer(
            overrides: [
              ...inboxClientOverrides(client),
              activityAttentionProvider.overrideWithValue(
                const ActivityAttention(questions: 1),
              ),
            ],
          );
          addTearDown(container.dispose);
          addTearDown(client.events.close);
          container.read(activityNavigationProvider.notifier)
            ..open(ActivitySection.questions)
            ..selectThread('msg_q1');
          return UncontrolledProviderScope(
            container: container,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: const Material(child: ActivityPage()),
              ),
            ),
          );
        },
      );
    }
  });
}
