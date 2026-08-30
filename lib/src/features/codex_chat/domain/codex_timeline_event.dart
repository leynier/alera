part of 'codex_chat_models.dart';

@immutable
class const CodexTimelineEvent({
  required final String method,
  required final Map<String, Object?> raw,
  required final String deduplicationKey,
  final String text = '',
  final String? title,
  final String kind = 'event',
}) {
  factory fromJson(Object? value) {
    final raw = _map(value);
    final params = _map(raw['params']);
    final item = _map(params['item']);
    final method = _string(raw['method']) ?? 'event';
    return CodexTimelineEvent(
      method: method,
      raw: raw,
      deduplicationKey: _eventDeduplicationKey(method, raw, params, item),
      text: _firstString(<Object?>[
        params['delta'],
        params['text'],
        item['text'],
        item['content'],
        item['message'],
        raw['result'],
      ]),
      title: _nullableString(<Object?>[
        params['title'],
        params['name'],
        item['name'],
        item['command'],
      ]),
      kind: _legacyKind(method, item),
    );
  }

  bool get isAssistant =>
      kind == 'assistant' || method.contains('agentMessage');
  bool get isUser => kind == 'user';
  bool get isReasoning => kind == 'reasoning' || method.contains('reasoning');
  bool get isTool => kind == 'tool' || method.contains('tool');
  bool get isCommand => kind == 'command' || method.contains('command');
  bool get isDiff => kind == 'diff' || method.contains('diff');
  bool get isPlan => kind == 'plan' || method.contains('plan');
  bool get isSubAgent =>
      method.contains('subagent') || method.contains('collab');
}

String _eventDeduplicationKey(
  String method,
  Map<String, Object?> raw,
  Map<String, Object?> params,
  Map<String, Object?> item,
) {
  final turn = _map(params['turn']);
  final eventId = _firstString(<Object?>[raw['id']]);
  final requestId = _firstString(<Object?>[
    params['requestId'],
    params['request_id'],
  ]);
  final turnId = _firstString(<Object?>[
    params['turnId'],
    params['turn_id'],
    turn['id'],
    item['turnId'],
    item['turn_id'],
  ]);
  final itemId = _firstString(<Object?>[
    params['itemId'],
    params['item_id'],
    item['id'],
    params['id'],
  ]);
  final delta = method.toLowerCase().contains('delta')
      ? _firstString(<Object?>[
          params['sequence'],
          params['sequenceNumber'],
          params['delta'],
          item['delta'],
        ])
      : '';
  if (<String>[
    eventId,
    requestId,
    turnId,
    itemId,
  ].any((value) => value.isNotEmpty)) {
    return <String>[
      method,
      eventId,
      requestId,
      turnId,
      itemId,
      delta,
    ].join('\u001f');
  }
  return <String>[
    method,
    _firstString(<Object?>[
      params['delta'],
      params['text'],
      params['message'],
      item['text'],
      item['message'],
      raw['result'],
    ]),
    _firstString(<Object?>[
      params['title'],
      params['name'],
      item['name'],
      item['command'],
    ]),
  ].join('\u001f');
}
