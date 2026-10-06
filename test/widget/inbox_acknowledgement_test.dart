import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';

class _WindowFocus implements AppForeground {
  _WindowFocus(this._focused);

  bool _focused;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  set focused(bool value) {
    _focused = value;
    _changes.add(value);
  }

  @override
  bool get isForeground => _focused;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  void dispose() => unawaited(_changes.close());
}

InboxTestClient _client({int unread = 1}) => InboxTestClient()
  ..respond('inbox.summary', <String, Object?>{
    'items': [
      {'inbox': 'ext:user', 'threadCount': 1, 'unreadReplyCount': unread},
    ],
  })
  ..respond('inbox.threads', <String, Object?>{
    'items': [inboxThreadJson(unread: unread)],
  })
  ..respond('inbox.thread', <String, Object?>{
    ...inboxDetailJson(),
    'thread': inboxThreadJson(unread: unread),
  });

Future<void> _pumpPage(
  WidgetTester tester,
  InboxTestClient client,
  _WindowFocus focus,
) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      ...inboxClientOverrides(client),
      inboxWindowFocusProvider.overrideWithValue(focus),
    ],
  );
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
  await tester.tap(find.text('Migration risk'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a thread refreshed in an unfocused window stays unread', (
    tester,
  ) async {
    final client = _client();
    final focus = _WindowFocus(false);
    await _pumpPage(tester, client, focus);
    expect(client.callsTo('inbox.thread').last['markRead'], isFalse);
    client.emit('inboxChanged');
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.markRead'), isEmpty);

    focus.focused = true;
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.markRead'), [
      {'threadId': 'msg_q1'},
    ]);
    // The same unread state is not acknowledged twice.
    focus.focused = false;
    focus.focused = true;
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.markRead'), hasLength(1));
  });

  testWidgets('a thread opened in a focused window is acknowledged', (
    tester,
  ) async {
    final client = _client();
    await _pumpPage(tester, client, _WindowFocus(true));
    expect(client.callsTo('inbox.markRead'), [
      {'threadId': 'msg_q1'},
    ]);
  });
}
