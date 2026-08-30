part of 'mobile_codex_state.dart';

class const _MobileCodexTimelineEvent({
  required final Map<String, Object?> message,
  required final String rawMethod,
  required final String method,
  required final Map<String, Object?> params,
  required final Map<String, Object?> legacy,
  required final Map<String, Object?> item,
  required final String turnId,
  required final String itemId,
  required final String itemType,
}) {
  factory fromMessage(Map<String, Object?> message) {
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

  String get lowerMethod => method.toLowerCase();
}
