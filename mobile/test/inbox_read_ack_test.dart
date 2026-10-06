import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/infra/mobile_runtime_inbox_repository.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_app_lifecycle.dart';
import 'support/fake_inbox_client.dart';

Widget _thread(FakeInboxClient client, ControlledAppLifecycle lifecycle) =>
    ProviderScope(
      overrides: [
        mobileInboxClientProvider('host').overrideWith((ref) async => client),
        appLifecycleControllerProvider.overrideWith(() => lifecycle),
      ],
      child: const MaterialApp(
        home: InboxThreadScreen(hostId: 'host', threadId: 'msg_1'),
      ),
    );

void main() {
  testWidgets('opening a thread in the foreground acknowledges it once', (
    tester,
  ) async {
    final client = FakeInboxClient()..threads = [inboxThreadJson(unread: 2)];
    addTearDown(client.dispose);
    final lifecycle = ControlledAppLifecycle(AppLifecycleState.resumed);
    await tester.pumpWidget(_thread(client, lifecycle));
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.markRead').single.payload, <String, Object?>{
      'threadId': 'msg_1',
    });
    expect(
      client.callsOf('inbox.thread').first.payload.containsKey('markRead'),
      isFalse,
    );

    client.emit(inboxChangedEvent, <String, Object?>{'revision': 4});
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.thread'), hasLength(2));
    expect(client.callsOf('inbox.markRead'), hasLength(1));
  });

  testWidgets('a refresh in the background leaves replies unread until the '
      'app resumes', (tester) async {
    final client = FakeInboxClient()..threads = [inboxThreadJson()];
    addTearDown(client.dispose);
    final lifecycle = ControlledAppLifecycle(AppLifecycleState.resumed);
    await tester.pumpWidget(_thread(client, lifecycle));
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.markRead'), isEmpty);

    lifecycle.setLifecycleState(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    client.threads.single['unreadReplyCount'] = 1;
    client.revision = 5;
    client.emit(inboxChangedEvent, <String, Object?>{'revision': 5});
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.thread'), hasLength(2));
    expect(client.callsOf('inbox.markRead'), isEmpty);

    lifecycle.setLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.markRead'), hasLength(1));
    lifecycle.setLifecycleState(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    lifecycle.setLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.markRead'), hasLength(1));
  });
}
