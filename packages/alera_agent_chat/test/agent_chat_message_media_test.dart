import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatItem _user(String id, {AgentChatItemOrigin? origin}) => AgentChatItem(
  id: id,
  type: AgentChatItemType.userMessage,
  status: AgentChatItemStatus.completed,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  origin: origin,
);

void main() {
  test('sorts attachments into media and card shapes', () {
    AgentChatAttachmentShape shape(AgentChatAttachment attachment) =>
        agentChatAttachmentShape(attachment);
    expect(
      shape(const AgentChatAttachment(type: .image, path: '/a.png')),
      AgentChatAttachmentShape.image,
    );
    expect(
      shape(const AgentChatAttachment(type: .file, path: '/b.JPG')),
      AgentChatAttachmentShape.image,
    );
    expect(
      shape(const AgentChatAttachment(type: .file, path: '/clip.mov')),
      AgentChatAttachmentShape.video,
    );
    expect(
      shape(
        const AgentChatAttachment(type: .localImage, name: 'Screenshot 1.png'),
      ),
      AgentChatAttachmentShape.snapshot,
    );
    expect(
      shape(const AgentChatAttachment(type: .file, name: 'Pasted File')),
      AgentChatAttachmentShape.pastedText,
    );
    expect(
      shape(const AgentChatAttachment(type: .file, path: '/notes.pdf')),
      AgentChatAttachmentShape.file,
    );
  });

  test('labels cards by kind and size', () {
    expect(
      agentChatAttachmentSubtitle(
        const AgentChatAttachment(
          type: .file,
          path: '/r.pdf',
          sizeBytes: 1258291,
        ),
      ),
      'PDF · 1.2 MB',
    );
    expect(
      agentChatAttachmentSubtitle(
        const AgentChatAttachment(type: .file, path: '/Makefile'),
      ),
      'File',
    );
    expect(
      agentChatAttachmentTitle(
        const AgentChatAttachment(type: .file, name: 'Pasted File'),
      ),
      'Pasted text',
    );
    expect(agentChatByteLabel(512), '512 B');
    expect(agentChatByteLabel(12 * 1024), '12 KB');
    expect(agentChatByteLabel(1024 * 1024 - 1), '1 MB');
    expect(agentChatByteLabel(1536 * 1024), '1.5 MB');
  });

  test('back-to-back steers form a burst labeled once, on the last', () {
    final placements = agentChatSteerPlacements(<AgentChatItem>[
      _user('a'),
      _user('b'),
      _user(
        'wake',
        origin: const AgentChatItemOrigin(kind: .orchestrationWake),
      ),
      _user('c'),
    ]);
    expect(
      <bool>[for (final placement in placements) placement.labeled],
      <bool>[false, true, true, true],
    );
    expect(placements[0].joinsNext, isTrue);
    expect(placements[1].joinsPrevious, isTrue);
    expect(placements[3].joinsPrevious, isFalse);
  });
}
