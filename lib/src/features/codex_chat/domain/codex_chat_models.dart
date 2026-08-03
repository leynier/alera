import 'package:flutter/foundation.dart';

@immutable
class CodexModelOption {
  const CodexModelOption({required this.id, required this.label});

  factory CodexModelOption.fromJson(Map<String, Object?> json) {
    final id = (json['id'] ?? json['model'] ?? json['name']).toString().trim();
    final label = (json['displayName'] ?? json['name'] ?? id).toString().trim();
    return CodexModelOption(
      id: id.isEmpty ? 'unknown' : id,
      label: label.isEmpty ? id : label,
    );
  }

  final String id;
  final String label;
}

@immutable
class CodexInputAttachment {
  const CodexInputAttachment({required this.path, required this.isImage});

  final String path;
  final bool isImage;
}

@immutable
class CodexQueuedMessage {
  const CodexQueuedMessage({required this.text, this.attachments = const []});

  final String text;
  final List<CodexInputAttachment> attachments;
}

@immutable
class CodexTimelineEvent {
  const CodexTimelineEvent({
    required this.method,
    required this.raw,
    this.text = '',
    this.title,
    this.kind = 'event',
  });

  factory CodexTimelineEvent.fromJson(Object? value) {
    final raw = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final method = raw['method']?.toString() ?? 'event';
    final params = _map(raw['params']);
    final item = _map(params['item']);
    final text = _firstString(<Object?>[
      params['delta'],
      params['text'],
      item['text'],
      item['content'],
      item['message'],
      raw['result'],
    ]);
    final title = _firstString(<Object?>[
      params['title'],
      params['name'],
      item['name'],
      item['command'],
    ]);
    return CodexTimelineEvent(
      method: method,
      raw: raw,
      text: text,
      title: title.isEmpty ? null : title,
      kind: _kindFor(method, item),
    );
  }

  final String method;
  final Map<String, Object?> raw;
  final String text;
  final String? title;
  final String kind;

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

  static String _kindFor(String method, Map<String, Object?> item) {
    final rawType = (item['type'] ?? '').toString().toLowerCase();
    if (rawType.contains('user')) return 'user';
    if (rawType.contains('agent') || rawType.contains('assistant')) {
      return 'assistant';
    }
    if (rawType.contains('reason')) return 'reasoning';
    if (rawType.contains('command') || method.contains('command')) {
      return 'command';
    }
    if (rawType.contains('tool') || method.contains('tool')) return 'tool';
    if (rawType.contains('diff') || method.contains('diff')) return 'diff';
    if (rawType.contains('plan') || method.contains('plan')) return 'plan';
    return 'event';
  }
}

@immutable
class CodexPendingRequest {
  const CodexPendingRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  factory CodexPendingRequest.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return CodexPendingRequest(
      id: json['id'] ?? '',
      method: json['method']?.toString() ?? 'request',
      params: _map(json['params']),
    );
  }

  final Object id;
  final String method;
  final Map<String, Object?> params;

  bool get isApproval =>
      method.contains('approval') || method.contains('permission');
  bool get isQuestion =>
      method.contains('question') || method.contains('input');
}

@immutable
class CodexChatSnapshot {
  const CodexChatSnapshot({
    this.events = const <CodexTimelineEvent>[],
    this.pendingRequests = const <CodexPendingRequest>[],
    this.activeTurnId,
    this.contextUsed,
    this.contextLimit,
  });

  factory CodexChatSnapshot.fromJson(Object? value) {
    final json = _map(value);
    return CodexChatSnapshot(
      events: <CodexTimelineEvent>[
        for (final item
            in json['events'] is List
                ? json['events'] as List
                : const <Object?>[])
          CodexTimelineEvent.fromJson(item),
      ],
      pendingRequests: <CodexPendingRequest>[
        for (final item
            in json['pendingRequests'] is List
                ? json['pendingRequests'] as List
                : const <Object?>[])
          CodexPendingRequest.fromJson(item),
      ],
      activeTurnId: _nullableString(json['activeTurnId']),
      contextUsed: _nullableInt(json['contextUsed']),
      contextLimit: _nullableInt(json['contextLimit']),
    );
  }

  final List<CodexTimelineEvent> events;
  final List<CodexPendingRequest> pendingRequests;
  final String? activeTurnId;
  final int? contextUsed;
  final int? contextLimit;

  bool get isBusy => activeTurnId != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'events': <Map<String, Object?>>[for (final event in events) event.raw],
    'pendingRequests': <Map<String, Object?>>[
      for (final request in pendingRequests)
        <String, Object?>{
          'id': request.id,
          'method': request.method,
          'params': request.params,
        },
    ],
    if (activeTurnId != null) 'activeTurnId': activeTurnId,
    if (contextUsed != null) 'contextUsed': contextUsed,
    if (contextLimit != null) 'contextLimit': contextLimit,
  };
}

@immutable
class CodexChatState {
  const CodexChatState({
    this.loading = true,
    this.sending = false,
    this.interrupting = false,
    this.snapshot = const CodexChatSnapshot(),
    this.models = const <CodexModelOption>[],
    this.collaborationModes = const <Map<String, Object?>>[],
    this.skills = const <Map<String, Object?>>[],
    this.apps = const <Map<String, Object?>>[],
    this.selectedModel,
    this.reasoningEffort = 'medium',
    this.speedMode = 'normal',
    this.permissionMode = 'on-request',
    this.planMode = false,
    this.queuedMessages = const <CodexQueuedMessage>[],
    this.error,
  });

  final bool loading;
  final bool sending;
  final bool interrupting;
  final CodexChatSnapshot snapshot;
  final List<CodexModelOption> models;
  final List<Map<String, Object?>> collaborationModes;
  final List<Map<String, Object?>> skills;
  final List<Map<String, Object?>> apps;
  final String? selectedModel;
  final String reasoningEffort;
  final String speedMode;
  final String permissionMode;
  final bool planMode;
  final List<CodexQueuedMessage> queuedMessages;
  final String? error;

  bool get busy => sending || snapshot.isBusy;

  CodexChatState copyWith({
    bool? loading,
    bool? sending,
    bool? interrupting,
    CodexChatSnapshot? snapshot,
    List<CodexModelOption>? models,
    List<Map<String, Object?>>? collaborationModes,
    List<Map<String, Object?>>? skills,
    List<Map<String, Object?>>? apps,
    String? selectedModel,
    String? reasoningEffort,
    String? speedMode,
    String? permissionMode,
    bool? planMode,
    List<CodexQueuedMessage>? queuedMessages,
    Object? error = _keepError,
  }) {
    return CodexChatState(
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      interrupting: interrupting ?? this.interrupting,
      snapshot: snapshot ?? this.snapshot,
      models: models ?? this.models,
      collaborationModes: collaborationModes ?? this.collaborationModes,
      skills: skills ?? this.skills,
      apps: apps ?? this.apps,
      selectedModel: selectedModel ?? this.selectedModel,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      speedMode: speedMode ?? this.speedMode,
      permissionMode: permissionMode ?? this.permissionMode,
      planMode: planMode ?? this.planMode,
      queuedMessages: queuedMessages ?? this.queuedMessages,
      error: identical(error, _keepError) ? this.error : error as String?,
    );
  }
}

const Object _keepError = Object();

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return const <String, Object?>{};
}

String _firstString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.isNotEmpty) return value;
    if (value is List) {
      final nested = _firstString(value);
      if (nested.isNotEmpty) return nested;
    }
    if (value is Map) {
      final nested = _firstString(value.values);
      if (nested.isNotEmpty) return nested;
    }
  }
  return '';
}

String? _nullableString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;
