import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

const _chat = AgentChatRef(chatId: 'chat', workspaceId: 'remote-workspace');
const _uploadId = '26ff2908-0cbd-4c5b-ad34-a8900ee80204';

final class _Transport implements AgentChatTransport {
  bool supported = true;
  int initialOffset = 0;
  int sizeBytes = 1;
  int chunkBytes = 3;
  bool completed = false;
  final requests = <(String, Map<String, Object?>)>[];
  final uploaded = <int>[];
  bool dropChunkAnswer = false;

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async =>
      supported && capability == AgentChatWire.attachmentUploadCapability;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload));
    switch (type) {
      case AgentChatWire.attachmentStart:
        return <String, Object?>{
          'uploadId': _uploadId,
          'chunkBytes': chunkBytes,
          'offset': initialOffset,
          'complete': completed,
        };
      case AgentChatWire.attachmentChunk:
        final data = base64Decode(payload['dataBase64']! as String);
        uploaded.addAll(data);
        final nextOffset = (payload['offset']! as int) + data.length;
        initialOffset = nextOffset;
        if (dropChunkAnswer) {
          dropChunkAnswer = false;
          throw const AgentChatConnectionException(
            'Disconnected after acknowledgment was lost.',
          );
        }
        return <String, Object?>{'nextOffset': nextOffset};
      case AgentChatWire.attachmentComplete:
        completed = true;
        return <String, Object?>{
          'attachmentId': _uploadId,
          'path': '/satellite/private/attachment',
          'type': 'file',
          'name': 'document.md',
          'sizeBytes': sizeBytes,
        };
      case AgentChatWire.attachmentCancel:
        return <String, Object?>{};
      default:
        throw StateError('Unexpected request $type.');
    }
  }
}

Future<AgentChatAttachment> _upload(
  _Transport transport,
  List<int> bytes, {
  void Function(int, int)? onProgress,
  void Function(int)? onRead,
}) => AgentChatAttachmentUploader(transport).upload(
  chat: _chat,
  uploadId: _uploadId,
  type: .file,
  name: 'document.md',
  sizeBytes: transport.sizeBytes,
  openRead: (offset) {
    onRead?.call(offset);
    return Stream.value(bytes.sublist(offset));
  },
  onProgress: onProgress,
);

void main() {
  test(
    'uploads only bounded chunks with host scope and opaque receipt',
    () async {
      final transport = _Transport()..sizeBytes = 8;
      final progress = <int>[];
      final attachment = await _upload(
        transport,
        utf8.encode('document'),
        onProgress: (done, _) => progress.add(done),
      );
      expect(transport.uploaded, utf8.encode('document'));
      expect(
        transport.requests
            .where((call) => call.$1 == AgentChatWire.attachmentChunk)
            .map(
              (call) => base64Decode(call.$2['dataBase64']! as String).length,
            ),
        <int>[3, 3, 2],
      );
      for (final request in transport.requests) {
        expect(request.$2['workspaceId'], _chat.workspaceId);
        expect(request.$2['chatId'], _chat.chatId);
        expect(request.$2['uploadId'], _uploadId);
        expect(request.$2.containsKey('path'), isFalse);
      }
      expect(progress, <int>[0, 3, 6, 8]);
      expect(attachment.attachmentId, _uploadId);
      expect(attachment.path, '/satellite/private/attachment');
      expect(
        transport.requests.any((call) => call.$1 == AgentChatWire.send),
        isFalse,
      );
    },
  );

  test(
    'lost chunk answer resumes same reservation and never sends a chat turn',
    () async {
      final transport = _Transport()
        ..sizeBytes = 6
        ..dropChunkAnswer = true;
      final bytes = utf8.encode('abcdef');
      await expectLater(
        _upload(transport, bytes),
        throwsA(isA<AgentChatConnectionException>()),
      );
      int? resumedAt;
      await _upload(transport, bytes, onRead: (offset) => resumedAt = offset);
      expect(resumedAt, 3);
      expect(transport.uploaded, bytes);
      expect(
        transport.requests
            .where((call) => call.$1 == AgentChatWire.attachmentStart)
            .length,
        2,
      );
      expect(
        transport.requests.any((call) => call.$1 == AgentChatWire.send),
        isFalse,
      );
    },
  );

  test(
    'completed retry only replays completion and does not read the file',
    () async {
      final transport = _Transport()
        ..sizeBytes = 1
        ..initialOffset = 1
        ..completed = true;
      var opened = false;
      await _upload(transport, <int>[1], onRead: (_) => opened = true);
      expect(opened, isFalse);
      expect(transport.requests.map((call) => call.$1), <String>[
        AgentChatWire.attachmentStart,
        AgentChatWire.attachmentComplete,
      ]);
    },
  );

  test(
    'source length changes and malicious chunk budgets fail before completion',
    () async {
      for (final bytes in [
        <int>[],
        <int>[1, 2],
      ]) {
        final transport = _Transport();
        await expectLater(_upload(transport, bytes), throwsFormatException);
        expect(
          transport.requests.any(
            (call) => call.$1 == AgentChatWire.attachmentComplete,
          ),
          isFalse,
        );
      }
      final transport = _Transport()
        ..chunkBytes = AgentChatAttachmentUploader.maxChunkBytes + 1;
      await expectLater(_upload(transport, <int>[1]), throwsFormatException);
      expect(transport.uploaded, isEmpty);
    },
  );

  test(
    'older runtimes and oversized files do not receive upload requests',
    () async {
      final old = _Transport()..supported = false;
      await expectLater(
        _upload(old, <int>[1]),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(old.requests, isEmpty);
      final large = _Transport()
        ..sizeBytes = AgentChatAttachmentUploader.maxFileBytes + 1;
      await expectLater(_upload(large, <int>[]), throwsFormatException);
      expect(large.requests, isEmpty);
    },
  );

  test(
    'local source origin persists in local input but never crosses the wire',
    () {
      final json = <String, Object?>{
        'type': 'file',
        'path': 'host-relative',
        'localSourcePath': '/picked/file',
        'attachmentId': _uploadId,
      };
      expect(AgentChatAttachment.fromJson(json).localSourcePath, isNull);
      final attachment = AgentChatAttachment.fromJson(json, localDraft: true);
      expect(attachment.localSourcePath, '/picked/file');
      expect(attachment.toJson().containsKey('localSourcePath'), isFalse);
      expect(
        AgentChatAttachment.fromJson(attachment.toJson()).attachmentId,
        _uploadId,
      );
    },
  );
}
