import 'package:flutter/foundation.dart';

import 'codex_timeline.dart';

@immutable
class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.contextWindowTokens,
    this.supportsFastMode = false,
    this.reasoningEfforts = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  factory CodexModelOption.fromJson(Map<String, Object?> json) {
    final id = _firstString(<Object?>[json['id'], json['model'], json['name']]);
    final label = _firstString(<Object?>[
      json['displayName'],
      json['label'],
      json['name'],
      id,
    ]);
    final reasoning =
        json['reasoningEfforts'] ??
        json['supportedReasoningEfforts'] ??
        (json['reasoning'] is Map
            ? (json['reasoning'] as Map)['efforts']
            : null);
    return CodexModelOption(
      id: id.isEmpty ? 'unknown' : id,
      label: label.isEmpty ? id : label,
      isDefault: json['isDefault'] == true || json['default'] == true,
      contextWindowTokens: _int(
        json['contextWindowTokens'] ?? json['contextWindow'],
      ),
      supportsFastMode:
          json['supportsFastMode'] == true ||
          _string(json['serviceTier']) == 'fast' ||
          _containsFast(json['serviceTiers']) ||
          _containsFast(json['supportedServiceTiers']),
      reasoningEfforts: _reasoningEfforts(reasoning),
      metadata: json,
    );
  }

  final String id;
  final String label;
  final bool isDefault;
  final int? contextWindowTokens;
  final bool supportsFastMode;
  final List<String> reasoningEfforts;
  final Map<String, Object?> metadata;
}

@immutable
class CodexInputAttachment {
  const CodexInputAttachment({
    required this.path,
    required this.isImage,
    this.mimeType,
    this.displayName,
  });

  final String path;
  final bool isImage;
  final String? mimeType;
  final String? displayName;
}

@immutable
class CodexQueuedMessage {
  const CodexQueuedMessage({
    required this.text,
    this.attachments = const <CodexInputAttachment>[],
    this.id,
  });

  final String text;
  final List<CodexInputAttachment> attachments;
  final String? id;
}

@immutable
class CodexQuestionOption {
  const CodexQuestionOption({required this.label, this.description});

  factory CodexQuestionOption.fromJson(Object? value) {
    final json = _map(value);
    return CodexQuestionOption(
      label: _firstString(<Object?>[json['label'], json['value'], value]),
      description: _string(json['description']),
    );
  }

  final String label;
  final String? description;
}

@immutable
class CodexQuestion {
  const CodexQuestion({
    required this.id,
    required this.question,
    this.header,
    this.options = const <CodexQuestionOption>[],
    this.isOther = false,
    this.isSecret = false,
    this.isMultiSelect = false,
  });

  factory CodexQuestion.fromJson(Object? value, {int index = 0}) {
    final json = _map(value);
    return CodexQuestion(
      id: _firstString(<Object?>[json['id'], json['key'], 'question-$index']),
      question: _firstString(<Object?>[
        json['question'],
        json['prompt'],
        json['text'],
        'Codex asked a question.',
      ]),
      header: _string(json['header']),
      options: <CodexQuestionOption>[
        if (json['options'] is List)
          for (final option in json['options'] as List)
            CodexQuestionOption.fromJson(option),
      ],
      isOther: json['isOther'] == true,
      isSecret: json['isSecret'] == true,
      isMultiSelect:
          json['isMultiSelect'] == true || json['multiSelect'] == true,
    );
  }

  final String id;
  final String question;
  final String? header;
  final List<CodexQuestionOption> options;
  final bool isOther;
  final bool isSecret;
  final bool isMultiSelect;
}

@immutable
class CodexPendingRequest {
  const CodexPendingRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  factory CodexPendingRequest.fromJson(Object? value) {
    final json = _map(value);
    return CodexPendingRequest(
      id: json['id'] ?? '',
      method: _string(json['method']) ?? 'request',
      params: _map(json['params']),
    );
  }

  final Object id;
  final String method;
  final Map<String, Object?> params;

  bool get isApproval {
    final methodName = method.toLowerCase();
    return methodName.contains('approval') ||
        methodName.contains('permission') ||
        methodName.contains('requestcommand') ||
        methodName.contains('requestfile');
  }

  bool get isQuestion {
    final methodName = method.toLowerCase();
    return methodName.contains('question') ||
        methodName.contains('userinput') ||
        params['questions'] is List;
  }

  List<CodexQuestion> get questions {
    final values = params['questions'];
    if (values is List && values.isNotEmpty) {
      return <CodexQuestion>[
        for (var index = 0; index < values.length; index++)
          CodexQuestion.fromJson(values[index], index: index),
      ];
    }
    return <CodexQuestion>[CodexQuestion.fromJson(params)];
  }

  String get requestTitle => isApproval
      ? 'Codex Needs Approval'
      : isQuestion
      ? 'Codex Needs Your Input'
      : 'Codex Request';

  String get approvalDescription => _firstString(<Object?>[
    params['reason'],
    params['command'],
    params['path'],
    params['filePath'],
    'Codex is requesting permission to continue.',
  ]);
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
    final raw = _map(value);
    final params = _map(raw['params']);
    final item = _map(params['item']);
    final method = _string(raw['method']) ?? 'event';
    return CodexTimelineEvent(
      method: method,
      raw: raw,
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
}

@immutable
class CodexChatSnapshot {
  const CodexChatSnapshot({
    this.events = const <CodexTimelineEvent>[],
    this.timelineCells = const <CodexTimelineCell>[],
    this.pendingRequests = const <CodexPendingRequest>[],
    this.activeTurnId,
    this.contextUsed,
    this.contextLimit,
    this.title,
  });

  factory CodexChatSnapshot.fromJson(Object? value) {
    final json = _map(value);
    final events = <CodexTimelineEvent>[
      for (final item
          in json['events'] is List
              ? json['events'] as List
              : const <Object?>[])
        CodexTimelineEvent.fromJson(item),
    ];
    var cells = <CodexTimelineCell>[
      for (final item
          in json['timelineCells'] is List
              ? json['timelineCells'] as List
              : const <Object?>[])
        if (item is Map) CodexTimelineCell.fromJson(_map(item)),
    ];
    if (cells.isEmpty && events.isNotEmpty) {
      for (final event in events) {
        cells = CodexTimelineReducer.reduce(cells, event.raw);
      }
    }
    return CodexChatSnapshot(
      events: events,
      timelineCells: cells,
      pendingRequests: <CodexPendingRequest>[
        for (final item
            in json['pendingRequests'] is List
                ? json['pendingRequests'] as List
                : const <Object?>[])
          CodexPendingRequest.fromJson(item),
      ],
      activeTurnId: _string(json['activeTurnId']),
      contextUsed: _int(json['contextUsed']),
      contextLimit: _int(json['contextLimit']),
      title: _string(json['title']),
    );
  }

  final List<CodexTimelineEvent> events;
  final List<CodexTimelineCell> timelineCells;
  final List<CodexPendingRequest> pendingRequests;
  final String? activeTurnId;
  final int? contextUsed;
  final int? contextLimit;
  final String? title;

  bool get isBusy => activeTurnId != null;
  bool get hasPlan =>
      timelineCells.any((cell) => cell.kind == CodexTimelineKind.plan);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 2,
    'events': <Map<String, Object?>>[for (final event in events) event.raw],
    'timelineCells': <Map<String, Object?>>[
      for (final cell in timelineCells) cell.toJson(),
    ],
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
    if (title != null) 'title': title,
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
    this.collaborationMode,
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
  final String? collaborationMode;
  final List<CodexQueuedMessage> queuedMessages;
  final String? error;

  bool get busy => sending || snapshot.isBusy;
  CodexModelOption? get selectedModelOption {
    for (final model in models) {
      if (model.id == selectedModel) return model;
    }
    return null;
  }

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
    Object? collaborationMode = _keepCollaborationMode,
    List<CodexQueuedMessage>? queuedMessages,
    Object? error = _keepError,
  }) => CodexChatState(
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
    collaborationMode: identical(collaborationMode, _keepCollaborationMode)
        ? this.collaborationMode
        : collaborationMode as String?,
    queuedMessages: queuedMessages ?? this.queuedMessages,
    error: identical(error, _keepError) ? this.error : error as String?,
  );
}

const Object _keepError = Object();
const Object _keepCollaborationMode = Object();

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String? _nullableString(Iterable<Object?> values) {
  final value = _firstString(values);
  return value.isEmpty ? null : value;
}

String _firstString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return '';
}

List<String> _reasoningEfforts(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final entry in value) {
    final effort = entry is Map
        ? (entry['effort'] ?? entry['id'] ?? entry['name'])?.toString()
        : entry.toString();
    if (effort != null && effort.trim().isNotEmpty) result.add(effort.trim());
  }
  return result;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

bool _containsFast(Object? value) =>
    value is List && value.any((item) => item.toString() == 'fast');

String _legacyKind(String method, Map<String, Object?> item) {
  final type = (item['type'] ?? '').toString().toLowerCase();
  final lower = method.toLowerCase();
  if (type.contains('user')) return 'user';
  if (type.contains('agent') || type.contains('assistant')) return 'assistant';
  if (type.contains('reason')) return 'reasoning';
  if (type.contains('command') || lower.contains('command')) return 'command';
  if (type.contains('tool') || lower.contains('tool')) return 'tool';
  if (type.contains('diff') || lower.contains('diff')) return 'diff';
  if (type.contains('plan') || lower.contains('plan')) return 'plan';
  return 'event';
}
