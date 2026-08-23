part of 'mobile_codex_state.dart';

class _MobileCodexTimelineEvent {
  const _MobileCodexTimelineEvent({
    required this.message,
    required this.rawMethod,
    required this.method,
    required this.params,
    required this.legacy,
    required this.item,
    required this.turnId,
    required this.itemId,
    required this.itemType,
  });

  factory _MobileCodexTimelineEvent.fromMessage(Map<String, Object?> message) {
    final rawMethod = message['method']?.toString() ?? '';
    final method = switch (rawMethod) {
      'codex/event/item_started' => 'item/started',
      'codex/event/item_completed' => 'item/completed',
      'codex/event/task_complete' => 'turn/completed',
      _ => rawMethod,
    };
    final params = _map(message['params']);
    final legacy = _map(params['msg']);
    final item = _map(params['item'] ?? legacy['item']);
    return _MobileCodexTimelineEvent(
      message: message,
      rawMethod: rawMethod,
      method: method,
      params: params,
      legacy: legacy,
      item: item,
      turnId: _first(<Object?>[
        params['turnId'],
        _map(params['turn'])['id'],
        item['turnId'],
        item['turn_id'],
        legacy['turnId'],
        legacy['turn_id'],
        message['turnId'],
      ]),
      itemId: _first(<Object?>[
        params['itemId'],
        params['item_id'],
        item['id'],
        params['id'],
      ]),
      itemType: (item['type'] ?? params['type'] ?? '').toString().toLowerCase(),
    );
  }

  final Map<String, Object?> message;
  final String rawMethod;
  final String method;
  final Map<String, Object?> params;
  final Map<String, Object?> legacy;
  final Map<String, Object?> item;
  final String turnId;
  final String itemId;
  final String itemType;

  String get lowerMethod => method.toLowerCase();
}
