class MobileCodexState {
  const MobileCodexState({
    this.events = const <Map<String, Object?>>[],
    this.pendingRequests = const <Map<String, Object?>>[],
    this.activeTurnId,
    this.models = const <Map<String, Object?>>[],
    this.error,
    this.sending = false,
  });

  factory MobileCodexState.fromSnapshot(Object? value) {
    final json = _asMap(value);
    return MobileCodexState(
      events: _maps(json['events']),
      pendingRequests: _maps(json['pendingRequests']),
      activeTurnId: json['activeTurnId'] as String?,
    );
  }

  final List<Map<String, Object?>> events;
  final List<Map<String, Object?>> pendingRequests;
  final String? activeTurnId;
  final List<Map<String, Object?>> models;
  final String? error;
  final bool sending;

  bool get busy => sending || activeTurnId != null;

  MobileCodexState copyWith({
    List<Map<String, Object?>>? events,
    List<Map<String, Object?>>? pendingRequests,
    String? activeTurnId,
    List<Map<String, Object?>>? models,
    Object? error = _keep,
    bool? sending,
  }) {
    return MobileCodexState(
      events: events ?? this.events,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      activeTurnId: activeTurnId ?? this.activeTurnId,
      models: models ?? this.models,
      error: identical(error, _keep) ? this.error : error as String?,
      sending: sending ?? this.sending,
    );
  }
}

const Object _keep = Object();

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return const <String, Object?>{};
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

String mobileCodexEventText(Map<String, Object?> event) {
  final params = _asMap(event['params']);
  final item = _asMap(params['item']);
  for (final value in <Object?>[
    params['delta'],
    params['text'],
    item['text'],
    item['content'],
    item['message'],
  ]) {
    if (value is String && value.isNotEmpty) return value;
  }
  return event['method']?.toString() ?? 'Codex event';
}

bool mobileCodexRequestIsApproval(Map<String, Object?> request) {
  final method = request['method']?.toString() ?? '';
  return method.contains('approval') || method.contains('permission');
}
