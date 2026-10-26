import 'dart:io';

import 'package:alera/src/features/agent_chat/infra/agent_chat_local_attachment_preparation.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Transport implements AgentChatTransport {
  _Transport({this.capable = false});
  final bool capable;
  final calls = <String>[];

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();
  @override
  Future<bool> supportsCapability(String capability) async => capable;
  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    calls.add(type);
    throw StateError('No upload should occur.');
  }
}

const _chat = AgentChatRef(chatId: 'chat', workspaceId: 'remote');

void main() {
  test('owner-host paths coinciding with a local file never access or upload that file', () async {
    final directory = await Directory.systemTemp.createTemp('chat-owned-path-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/same-path.txt');
    await file.writeAsString('local private contents');
    final transport = _Transport(capable: true);
    var localReads = 0;
    final service = AgentChatLocalAttachmentPreparation(
      transport: transport,
      localWorkspace: false,
      loadSource: (_) async {
        localReads += 1;
        throw StateError('Remote paths cannot open local files.');
      },
    );
    final ownerAttachment = AgentChatAttachment(type: .file, path: file.path);
    final result = await service.prepare(_chat, <AgentChatAttachment>[
      ownerAttachment,
    ], 'send-id');
    expect(result.single, same(ownerAttachment));
    expect(localReads, 0);
    expect(transport.calls, isEmpty);
    expect(await file.readAsString(), 'local private contents');
  });

  test(
    'old local hosts retain path sends without reading files for a new upload',
    () async {
      final transport = _Transport();
      final source = const AgentChatAttachment(
        type: .file,
        path: '/local/workspace/file',
        localSourcePath: '/local/workspace/file',
      );
      var opened = false;
      final service = AgentChatLocalAttachmentPreparation(
        transport: transport,
        localWorkspace: true,
        loadSource: (_) async {
          opened = true;
          throw StateError('No upload is supported.');
        },
      );
      expect(
        (await service.prepare(_chat, <AgentChatAttachment>[
          source,
        ], 'id')).single,
        same(source),
      );
      expect(opened, isFalse);
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'remote local sources fail closed when the new upload capability is absent',
    () async {
      final transport = _Transport();
      final service = AgentChatLocalAttachmentPreparation(
        transport: transport,
        localWorkspace: false,
      );
      await expectLater(
        service.prepare(_chat, const <AgentChatAttachment>[
          AgentChatAttachment(
            type: .file,
            path: '/picked/file',
            localSourcePath: '/picked/file',
          ),
        ], 'id'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(transport.calls, isEmpty);
    },
  );
}
