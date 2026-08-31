import 'codex_chat_models.dart';

Map<String, Object?> codexQueueDraft(CodexQueuedMessage message) => {
  'text': message.text,
  'attachments': [
    for (final a in message.attachments)
      {
        'id': a.id,
        'path': a.path,
        'isImage': a.isImage,
        'type': a.isImage ? 'localImage' : 'file',
        'mimeType': a.mimeType,
        'displayName': a.displayName,
        'sizeBytes': a.sizeBytes,
        'detail': a.detail,
        'isDirectory': a.isDirectory,
        'origin': a.origin.name,
        'tokenText': a.tokenText,
        'tokenStart': a.tokenStart,
        'annotationContext': a.annotationContext,
        'annotationUrl': a.annotationUrl,
        'annotationTitle': a.annotationTitle,
        'annotationCount': a.annotationCount,
      },
  ],
  'catalogSelections': [
    for (final d in message.draftItems)
      {
        'id': d.id,
        'type': d.kind.name,
        'name': d.name,
        'path': d.path,
        'tokenText': d.tokenText,
        'tokenStart': d.tokenStart,
        'iconUrl': d.iconUrl,
      },
  ],
};

CodexQueuedMessage codexQueuedMessageFromWire(Map<String, Object?> entry) {
  final payload = _map(entry['payload']);
  final draft = _map(payload['draft'] ?? payload['userMessage']);
  return CodexQueuedMessage(
    id: entry['id']?.toString(),
    text: draft['text']?.toString() ?? '',
    payload: payload,
    deliveryStatus: entry['status']?.toString() ?? 'queued',
    deliveryError: entry['error']?.toString(),
    attachments: [
      for (final a in _maps(draft['attachments']))
        CodexInputAttachment(
          id: a['id']?.toString(),
          path: a['path']?.toString() ?? '',
          isImage: a['isImage'] == true || a['type'] == 'localImage',
          mimeType: a['mimeType']?.toString(),
          displayName: a['displayName']?.toString(),
          sizeBytes: a['sizeBytes'] as int?,
          detail: a['detail']?.toString(),
          isDirectory: a['isDirectory'] == true,
          origin: a['origin'] == 'mention'
              ? CodexInputAttachmentOrigin.mention
              : CodexInputAttachmentOrigin.attachment,
          tokenText: a['tokenText']?.toString(),
          tokenStart: a['tokenStart'] as int?,
          annotationContext: a['annotationContext']?.toString(),
          annotationUrl: a['annotationUrl']?.toString(),
          annotationTitle: a['annotationTitle']?.toString(),
          annotationCount: a['annotationCount'] as int?,
        ),
    ],
    draftItems: [
      for (final d in _maps(draft['catalogSelections']))
        CodexDraftItem(
          id: d['id']?.toString() ?? '${d['type']}-${d['path']}',
          kind:
              CodexDraftItemKind.values
                  .where((kind) => kind.name == d['type'])
                  .firstOrNull ??
              CodexDraftItemKind.mention,
          name: d['name']?.toString() ?? '',
          path: d['path']?.toString() ?? '',
          tokenText: d['tokenText']?.toString(),
          tokenStart: d['tokenStart'] as int?,
          iconUrl: d['iconUrl']?.toString(),
        ),
    ],
  );
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};
Iterable<Map<String, Object?>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, Object?>.from)
    : const [];
