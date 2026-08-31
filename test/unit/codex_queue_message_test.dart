import 'dart:convert';

import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_queue_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'queued drafts preserve attachment and catalog identity across clients',
    () {
      const original = CodexQueuedMessage(
        text: 'Inspect @src with \$audit',
        attachments: [
          CodexInputAttachment(
            id: 'screenshot',
            path: '/runtime/attachments/screenshot.png',
            isImage: true,
            mimeType: 'image/png',
            displayName: 'Screenshot',
            sizeBytes: 128,
            detail: 'original',
            annotationContext: 'Review the marked button',
            annotationUrl: 'https://example.com/page',
            annotationTitle: 'Example Page',
            annotationCount: 2,
          ),
          CodexInputAttachment(
            id: 'source',
            path: '/workspace/src',
            isImage: false,
            isDirectory: true,
            origin: .mention,
            tokenText: '@src',
            tokenStart: 8,
          ),
        ],
        draftItems: [
          CodexDraftItem(
            id: 'audit-skill',
            kind: .skill,
            name: 'Audit',
            path: '/workspace/skills/audit/SKILL.md',
            tokenText: '\$audit',
            tokenStart: 18,
            iconUrl: 'https://example.com/audit.png',
          ),
        ],
      );
      final draft = codexQueueDraft(original);
      expect(draft['catalogSelections'], [
        {
          'id': 'audit-skill',
          'type': 'skill',
          'name': 'Audit',
          'path': '/workspace/skills/audit/SKILL.md',
          'tokenText': '\$audit',
          'tokenStart': 18,
          'iconUrl': 'https://example.com/audit.png',
        },
      ]);
      final wire = jsonDecode(
        jsonEncode({
          'id': 'queued-42',
          'status': 'failed',
          'error': 'The active turn ended.',
          'payload': {
            'draft': draft,
            'input': [
              {'type': 'text', 'text': original.text},
            ],
            'model': 'captured-model',
          },
        }),
      ) as Map<String, Object?>;
      final restored = codexQueuedMessageFromWire(wire);

      expect(restored.id, 'queued-42');
      expect(restored.deliveryStatus, 'failed');
      expect(restored.deliveryError, 'The active turn ended.');
      expect(restored.payload, wire['payload']);
      expect(restored.text, original.text);
      expect(restored.attachments, hasLength(2));
      final image = restored.attachments.first;
      expect(image.id, 'screenshot');
      expect(image.path, '/runtime/attachments/screenshot.png');
      expect(image.isImage, isTrue);
      expect(image.mimeType, 'image/png');
      expect(image.displayName, 'Screenshot');
      expect(image.sizeBytes, 128);
      expect(image.detail, 'original');
      expect(image.annotationContext, 'Review the marked button');
      expect(image.annotationUrl, 'https://example.com/page');
      expect(image.annotationTitle, 'Example Page');
      expect(image.annotationCount, 2);
      final directory = restored.attachments.last;
      expect(directory.id, 'source');
      expect(directory.isImage, isFalse);
      expect(directory.isDirectory, isTrue);
      expect(directory.origin, CodexInputAttachmentOrigin.mention);
      expect(directory.tokenText, '@src');
      expect(directory.tokenStart, 8);
      final skill = restored.draftItems.single;
      expect(skill.id, 'audit-skill');
      expect(skill.kind, CodexDraftItemKind.skill);
      expect(skill.name, 'Audit');
      expect(skill.path, '/workspace/skills/audit/SKILL.md');
      expect(skill.tokenText, '\$audit');
      expect(skill.tokenStart, 18);
      expect(skill.iconUrl, 'https://example.com/audit.png');
    },
  );

  test('legacy presentation remains readable without a dedicated draft', () {
    final restored = codexQueuedMessageFromWire({
      'id': 'legacy-message',
      'payload': {
        'userMessage': {
          'text': 'Legacy input',
          'attachments': [
            {'type': 'localImage', 'path': '/runtime/legacy.png'},
            null,
          ],
          'catalogSelections': [
            {'type': 'future-reference', 'path': '/workspace/notes.md'},
            false,
          ],
        },
      },
    });
    expect(restored.text, 'Legacy input');
    expect(restored.deliveryStatus, 'queued');
    expect(restored.deliveryError, isNull);
    expect(restored.attachments.single.isImage, isTrue);
    expect(
      restored.attachments.single.origin,
      CodexInputAttachmentOrigin.attachment,
    );
    expect(
      restored.draftItems.single.id,
      'future-reference-/workspace/notes.md',
    );
    expect(restored.draftItems.single.kind, CodexDraftItemKind.mention);
    expect(restored.draftItems.single.name, isEmpty);
  });

  test('the current queue draft takes precedence over legacy presentation', () {
    final restored = codexQueuedMessageFromWire({
      'payload': {
        'draft': {'text': 'Edited queue entry'},
        'userMessage': {'text': 'Original presentation'},
      },
    });
    expect(restored.text, 'Edited queue entry');
    expect(restored.attachments, isEmpty);
    expect(restored.draftItems, isEmpty);
  });

  test('missing or invalid optional presentation does not invent content', () {
    for (final entry in <Map<String, Object?>>[
      {},
      {'payload': false},
      {
        'payload': {
          'draft': {'attachments': false, 'catalogSelections': 'invalid'},
        },
      },
    ]) {
      final restored = codexQueuedMessageFromWire(entry);
      expect(restored.id, isNull);
      expect(restored.text, isEmpty);
      expect(restored.deliveryStatus, 'queued');
      expect(restored.attachments, isEmpty);
      expect(restored.draftItems, isEmpty);
    }
  });
}
