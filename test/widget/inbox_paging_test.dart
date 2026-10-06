import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  InboxTestClient client,
) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: inboxClientOverrides(client));
  addTearDown(container.dispose);
  addTearDown(client.events.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: InboxPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Load More merges the next page and a refresh starts over', (
    tester,
  ) async {
    final client = InboxTestClient()
      ..respond('inbox.summary', const <String, Object?>{'items': <Object?>[]});
    client.handlers['inbox.threads'] = (payload) => payload['before'] == 5
        ? <String, Object?>{
            'items': [
              inboxThreadJson(subject: 'Newest'),
              inboxThreadJson(threadId: 'msg_old', subject: 'Oldest'),
            ],
            'nextBefore': null,
          }
        : <String, Object?>{
            'items': [inboxThreadJson(subject: 'Newest')],
            'nextBefore': 5,
          };
    final container = await _pump(tester, client);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Oldest'), findsNothing);

    await tester.tap(find.text('Load More'));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.threads').last['before'], 5);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Oldest'), findsOneWidget);
    expect(find.text('Load More'), findsNothing);

    client.emit('inboxChanged');
    await tester.pumpAndSettle();
    expect(find.text('Oldest'), findsNothing);
    expect(find.text('Load More'), findsOneWidget);

    await tester.tap(find.text('Load More'));
    await tester.pumpAndSettle();
    expect(find.text('Oldest'), findsOneWidget);
    container.read(inboxNavigationProvider.notifier).filterInbox('ext:ci');
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.threads').last, {
      'inbox': 'ext:ci',
      'limit': 100,
    });
    expect(find.text('Oldest'), findsNothing);
  });

  testWidgets('a follow-up keeps the inbox of a CLI thread', (tester) async {
    final client = InboxTestClient()
      ..respond('inbox.summary', const <String, Object?>{'items': <Object?>[]})
      ..respond('inbox.threads', <String, Object?>{
        'items': [inboxThreadJson(inbox: 'ext:ci')],
      })
      ..respond('inbox.thread', <String, Object?>{
        ...inboxDetailJson(),
        'thread': inboxThreadJson(inbox: 'ext:ci'),
      });
    // Like the host: a follow-up must stay in the thread's own inbox.
    client.handlers['inbox.ask'] = (payload) {
      final inbox = payload['inbox'];
      if (inbox != null && inbox != 'ext:ci') {
        throw const TerminalHostConflictException(
          code: 'inbox_thread_mismatch',
          message: 'mismatch',
        );
      }
      return <String, Object?>{'threadId': 'msg_q1'};
    };
    await _pump(tester, client);
    await tester.tap(find.text('Migration risk'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('inboxFollowUpBody')),
      'And the rollback?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('inboxFollowUpSend')));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.ask').single.containsKey('inbox'), isFalse);
    expect(find.textContaining('same agent and inbox'), findsNothing);
  });
}
