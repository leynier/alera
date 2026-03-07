import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingMessage', () {
    test('copyWith updates text', () {
      final msg = PendingMessage(
        id: '1',
        text: 'original',
        attachments: const <ComposerAttachment>[],
      );
      final updated = msg.copyWith(text: 'updated');
      expect(updated.id, '1');
      expect(updated.text, 'updated');
      expect(updated.attachments.length, 0);
    });

    test('copyWith updates attachments', () {
      final msg = PendingMessage(
        id: '1',
        text: 'test',
        attachments: const <ComposerAttachment>[],
      );
      final newAttachments = <ComposerAttachment>[
        ComposerAttachment(
          id: 'att1',
          path: '/test/file.txt',
          displayName: 'file.txt',
          kind: AttachmentKind.file,
        ),
      ];
      final updated = msg.copyWith(attachments: newAttachments);
      expect(updated.text, 'test');
      expect(updated.attachments.length, 1);
      expect(updated.attachments.first.displayName, 'file.txt');
    });

    test('copyWith preserves values when null', () {
      final msg = PendingMessage(
        id: '1',
        text: 'test',
        attachments: const <ComposerAttachment>[],
        planModeEnabled: true,
      );
      final updated = msg.copyWith(text: 'new text');
      expect(updated.id, '1');
      expect(updated.planModeEnabled, true);
    });
  });
}
