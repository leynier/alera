import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_availability.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_link_target.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_transport.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

void main() {
  group('agentChatLinkTarget', () {
    test('opens web links in the browser', () {
      expect(
        agentChatLinkTarget('https://example.com/docs'),
        isA<AgentChatExternalLink>(),
      );
    });

    test('reads file links the way agents print them', () {
      final relative =
          agentChatLinkTarget('lib/main.dart:42') as AgentChatWorkspaceLink;
      expect((relative.path, relative.line), ('lib/main.dart', 42));

      final bare =
          agentChatLinkTarget('notes.md:7:3') as AgentChatWorkspaceLink;
      expect((bare.path, bare.line), ('notes.md', 7));

      final fragment =
          agentChatLinkTarget('./src/app.ts#L10-L20') as AgentChatWorkspaceLink;
      expect((fragment.path, fragment.line), ('src/app.ts', 10));

      final absolute = agentChatLinkTarget(
        '/repo/lib/a.dart',
        cwd: '/repo/',
      ) as AgentChatWorkspaceLink;
      expect(absolute.path, 'lib/a.dart');

      final windows = agentChatLinkTarget(
        r'C:\work\app\src\b.rs',
        cwd: r'c:\Work\App',
      ) as AgentChatWorkspaceLink;
      expect(windows.path, 'src/b.rs');
    });

    test('refuses paths outside the workspace and non-file schemes', () {
      expect(agentChatLinkTarget('/etc/passwd', cwd: '/repo'), isNull);
      expect(agentChatLinkTarget('../secret.txt'), isNull);
      expect(agentChatLinkTarget('mailto:someone@example.com'), isNull);
      expect(agentChatLinkTarget('ftp://example.com/file'), isNull);
      expect(agentChatLinkTarget('   '), isNull);
    });
  });

  group('AgentChatComposerDraft', () {
    test('restoring keeps what was typed since and the refused prompt', () {
      const typed = AgentChatComposerDraft(
        value: TextEditingValue(text: 'New thought'),
      );
      final restored = typed.restoring(
        AgentChatComposerDraft.fromMessage('Old prompt', <AgentChatAttachment>[
          const AgentChatAttachment(type: .localImage, path: '/up/shot.png'),
        ]),
      );
      expect(restored.value.text, 'New thought\n\nOld prompt');
      expect(restored.attachments.single.isImage, isTrue);
      expect(restored.attachments.single.displayName, 'shot.png');
    });

    test('the same prompt keeps one client message id until settled', () {
      final ids = AgentChatSubmissionIds();
      var next = 0;
      String newId() => 'id-${next++}';
      expect(ids.claim('a', newId), 'id-0');
      expect(ids.claim('a', newId), 'id-0');
      ids.settled('a');
      expect(ids.claim('a', newId), 'id-1');
    });
  });

  test('a closed chat ignores late uploads until it is shown again', () {
    final store = AgentChatDraftStore();
    var notified = 0;
    store.addListener('host', 'chat-1', () => notified += 1);
    const upload = AgentChatDraftAttachment(
      path: '/uploads/log.txt',
      source: AgentChatAttachmentSource.file,
      displayName: 'log.txt',
    );
    store.addAttachment('host', 'chat-1', upload);
    expect(store.read('host', 'chat-1').attachments, <Object>[upload]);
    expect(notified, 1);

    store.close('host', 'chat-1');
    store.addAttachment('host', 'chat-1', upload);
    expect(store.read('host', 'chat-1').isEmpty, isTrue);

    store.activate('host', 'chat-1');
    store.addAttachment('host', 'chat-1', upload);
    expect(store.read('host', 'chat-1').attachments, hasLength(1));
  });

  test('availability prefers the connection over the chat state', () {
    expect(
      agentChatAvailability(
        refreshing: false,
        failed: true,
        disconnected: false,
        readOnly: true,
      ),
      AgentChatAvailability.offline,
    );
    expect(
      agentChatAvailability(
        refreshing: true,
        failed: false,
        disconnected: false,
        readOnly: false,
      ),
      AgentChatAvailability.reconnecting,
    );
    expect(
      agentChatAvailability(
        refreshing: false,
        failed: false,
        disconnected: false,
        readOnly: true,
      ).allowsInput,
      isFalse,
    );
  });

  group('MobileAgentChatTransport', () {
    test('keeps the runtime errorCode on refusals', () async {
      final client = FakeAgentChatClient();
      client.handlers['agentChat.send'] = (_) =>
          throw RuntimeRequestError('busy', code: 'turnActive');
      await expectLater(
        MobileAgentChatTransport(client).request('agentChat.send', const {}),
        throwsA(
          isA<AgentChatRequestException>().having(
            (error) => error.code,
            'code',
            'turnActive',
          ),
        ),
      );
    });

    test(
      'reports a lost connection as one, so a retry reuses its id',
      () async {
        final client = FakeAgentChatClient();
        client.handlers['agentChat.send'] = (_) =>
            throw const RuntimeConnectionLost();
        client.handlers['agentChat.interrupt'] = (_) =>
            throw TimeoutException('slow');
        final transport = MobileAgentChatTransport(client);
        await expectLater(
          transport.request('agentChat.send', const {}),
          throwsA(isA<AgentChatConnectionException>()),
        );
        await expectLater(
          transport.request('agentChat.interrupt', const {}),
          throwsA(isA<AgentChatConnectionException>()),
        );
      },
    );

    test('forwards events and reports the end of the connection', () async {
      final client = FakeAgentChatClient();
      final transport = MobileAgentChatTransport(client);
      final names = <String>[];
      final done = Completer<void>();
      transport.events.listen(
        (event) => names.add(event.name),
        onDone: done.complete,
      );
      client.emitChange(1, const <String, Object?>{});
      await client.disconnect();
      await done.future;
      expect(names, <String>[
        'agentChatChanged',
        AgentChatTransportEvents.disconnected,
      ]);
      expect(await transport.supportsCapability('agentChatV1'), isTrue);
    });
  });
}
