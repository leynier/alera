import 'package:flutter/foundation.dart';

import 'codex_timeline.dart';

part 'codex_chat_state.dart';
part 'codex_chat_models_helpers.dart';

@immutable
class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.contextWindowTokens,
    this.supportsFastMode = false,
    this.reasoningEfforts = const <String>[],
    this.defaultReasoningEffort,
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
      defaultReasoningEffort: _string(json['defaultReasoningEffort']),
      supportsFastMode:
          json['supportsFastMode'] == true ||
          _containsFast(json['serviceTier']) ||
          _containsFast(json['additionalSpeedTiers']) ||
          _containsFast(json['serviceTiers']) ||
          _containsFast(json['supportedServiceTiers']) ||
          _containsFast(json['serviceTierOptions']),
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
  final String? defaultReasoningEffort;
  final Map<String, Object?> metadata;
}

@immutable
class CodexInputAttachment {
  const CodexInputAttachment({
    required this.path,
    required this.isImage,
    this.mimeType,
    this.displayName,
    this.detail,
  });

  final String path;
  final bool isImage;
  final String? mimeType;
  final String? displayName;
  final String? detail;
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

  bool get isPermissionsRequest =>
      method.toLowerCase() == 'item/permissions/requestapproval';

  bool get isElicitation =>
      method.toLowerCase() == 'mcpserver/elicitation/request';

  bool get isBlocking {
    final value = params['isBlocking'];
    if (value is bool) return value;
    if (params.containsKey('autoResolutionMs')) return false;
    return true;
  }

  int? get autoResolutionMs => _int(params['autoResolutionMs']);

  String get elicitationMode => _string(params['mode']) ?? '';

  Map<String, Object?> get elicitationSchema => _map(params['requestedSchema']);

  bool get hasSupportedElicitationForm =>
      isElicitation &&
      (elicitationMode == 'form' || elicitationMode == 'openai/form') &&
      elicitationSchema['properties'] is Map;

  bool get isQuestion {
    final methodName = method.toLowerCase();
    return methodName.contains('question') ||
        methodName.contains('userinput') ||
        methodName.contains('request_user_input') ||
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
      : isElicitation
      ? 'MCP Server Needs Input'
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

  /// The plan prompt is a turn-local affordance. Older snapshots can retain
  /// plans from many turns, so rendering a button for any plan makes a stale
  /// plan actionable after the user has started a new request.
  CodexTimelineCell? get latestActionablePlan {
    final latestUserIndex = _latestUserIndex;
    if (latestUserIndex < 0) return null;
    for (
      var index = timelineCells.length - 1;
      index > latestUserIndex;
      index--
    ) {
      final cell = timelineCells[index];
      if (cell.kind != CodexTimelineKind.plan ||
          cell.status == CodexTimelineStatus.failed ||
          cell.status == CodexTimelineStatus.declined ||
          cell.isStreaming ||
          (cell.markdownText ?? cell.detailsText ?? '').trim().isEmpty) {
        continue;
      }
      return cell;
    }
    return null;
  }

  /// A server question asking whether to implement a plan owns the prompt.
  /// Showing the local fallback at the same time creates two competing
  /// actions and can send an answer for an already resolved request.
  bool get hasEquivalentPlanRequest => pendingRequests.any((request) {
    if (!request.isQuestion) return false;
    final text = <Object?>[
      request.params['title'],
      request.params['question'],
      request.params['prompt'],
      request.params['message'],
      for (final question in request.questions) question.question,
    ].join(' ').toLowerCase();
    return text.contains('implement') && text.contains('plan');
  });

  bool get shouldShowImplementPlan =>
      latestActionablePlan != null && !hasEquivalentPlanRequest;

  bool get hasPlan => shouldShowImplementPlan;

  int get _latestUserIndex {
    for (var index = timelineCells.length - 1; index >= 0; index--) {
      if (timelineCells[index].kind == CodexTimelineKind.userMessage) {
        return index;
      }
    }
    return -1;
  }

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
