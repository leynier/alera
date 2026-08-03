import 'package:flutter/foundation.dart';

part 'mobile_codex_timeline.dart';
part 'mobile_codex_state_helpers.dart';

@immutable
class MobileCodexModelOption {
  const MobileCodexModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.contextWindowTokens,
    this.supportsFastMode = false,
    this.reasoningEfforts = const <String>[],
    this.defaultReasoningEffort,
    this.metadata = const <String, Object?>{},
  });

  factory MobileCodexModelOption.fromJson(Object? value) {
    final json = _map(value);
    final id = _first(<Object?>[json['id'], json['model'], json['name']]);
    return MobileCodexModelOption(
      id: id.isEmpty ? 'unknown' : id,
      label: _first(<Object?>[
        json['displayName'],
        json['label'],
        json['name'],
        id,
      ]),
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
      reasoningEfforts: _reasoningEfforts(
        json['reasoningEfforts'] ??
            json['supportedReasoningEfforts'] ??
            (json['reasoning'] is Map
                ? (json['reasoning'] as Map)['efforts']
                : null),
      ),
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
class MobileCodexTimelineCell {
  const MobileCodexTimelineCell({
    required this.id,
    required this.kind,
    required this.status,
    this.itemId,
    this.turnId,
    this.createdAt,
    this.updatedAt,
    this.title,
    this.subtitle,
    this.markdownText,
    this.renderedMarkdownText,
    this.detailsText,
    this.isStreaming = false,
    this.isCollapsed = false,
    this.metadata = const <String, Object?>{},
  });

  factory MobileCodexTimelineCell.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexTimelineCell(
      id: _first(<Object?>[json['id'], 'cell']),
      kind: _first(<Object?>[json['kind'], 'systemNotice']),
      status: _first(<Object?>[json['status'], 'info']),
      itemId: _string(json['itemId']),
      turnId: _string(json['turnId']),
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
      title: _string(json['title']),
      subtitle: _string(json['subtitle']),
      markdownText: _string(json['markdownText']),
      renderedMarkdownText: _string(json['renderedMarkdownText']),
      detailsText: _string(json['detailsText']),
      isStreaming: json['isStreaming'] == true,
      isCollapsed: json['isCollapsed'] == true,
      metadata: _map(json['metadata']),
    );
  }

  final String id;
  final String kind;
  final String status;
  final String? itemId;
  final String? turnId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? title;
  final String? subtitle;
  final String? markdownText;
  final String? renderedMarkdownText;
  final String? detailsText;
  final bool isStreaming;
  final bool isCollapsed;
  final Map<String, Object?> metadata;

  MobileCodexTimelineCell copyWith({
    String? kind,
    String? status,
    DateTime? updatedAt,
    String? title,
    String? subtitle,
    String? markdownText,
    String? renderedMarkdownText,
    String? detailsText,
    bool? isStreaming,
    bool? isCollapsed,
    Map<String, Object?>? metadata,
  }) => MobileCodexTimelineCell(
    id: id,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    itemId: itemId,
    turnId: turnId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    markdownText: markdownText ?? this.markdownText,
    renderedMarkdownText: renderedMarkdownText ?? this.renderedMarkdownText,
    detailsText: detailsText ?? this.detailsText,
    isStreaming: isStreaming ?? this.isStreaming,
    isCollapsed: isCollapsed ?? this.isCollapsed,
    metadata: metadata ?? this.metadata,
  );

  String get displayText => _safeMarkdown(
    renderedMarkdownText ??
        markdownText ??
        detailsText ??
        title ??
        'Codex activity',
  );
  bool get isAssistant => kind == 'assistantMessage';
  bool get isUser => kind == 'userMessage';
  bool get isReasoning => kind == 'reasoning';
  bool get isApproval =>
      kind == 'toolCall' || kind == 'command' || kind == 'diff';
}

@immutable
class MobileCodexQuestionOption {
  const MobileCodexQuestionOption({required this.label, this.description});

  factory MobileCodexQuestionOption.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexQuestionOption(
      label: _first(<Object?>[json['label'], json['value'], value]),
      description: _string(json['description']),
    );
  }

  final String label;
  final String? description;
}

@immutable
class MobileCodexQuestion {
  const MobileCodexQuestion({
    required this.id,
    required this.question,
    this.header,
    this.options = const <MobileCodexQuestionOption>[],
    this.isMultiSelect = false,
    this.isSecret = false,
    this.isOther = false,
  });

  factory MobileCodexQuestion.fromJson(Object? value, {int index = 0}) {
    final json = _map(value);
    return MobileCodexQuestion(
      id: _first(<Object?>[json['id'], json['key'], 'question-$index']),
      question: _first(<Object?>[
        json['question'],
        json['prompt'],
        json['text'],
        'Codex asked a question.',
      ]),
      header: _string(json['header']),
      options: <MobileCodexQuestionOption>[
        if (json['options'] is List)
          for (final option in json['options'] as List)
            MobileCodexQuestionOption.fromJson(option),
      ],
      isMultiSelect:
          json['isMultiSelect'] == true || json['multiSelect'] == true,
      isSecret: json['isSecret'] == true,
      isOther: json['isOther'] == true,
    );
  }

  final String id;
  final String question;
  final String? header;
  final List<MobileCodexQuestionOption> options;
  final bool isMultiSelect;
  final bool isSecret;
  final bool isOther;
}

@immutable
class MobileCodexPendingRequest {
  const MobileCodexPendingRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  factory MobileCodexPendingRequest.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexPendingRequest(
      id: json['id'] ?? '',
      method: _first(<Object?>[json['method'], 'request']),
      params: _map(json['params']),
    );
  }

  final Object id;
  final String method;
  final Map<String, Object?> params;

  bool get isApproval {
    final lower = method.toLowerCase();
    return lower.contains('approval') ||
        lower.contains('permission') ||
        lower.contains('requestcommand') ||
        lower.contains('requestfile');
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
    final lower = method.toLowerCase();
    return lower.contains('question') ||
        lower.contains('userinput') ||
        lower.contains('request_user_input') ||
        params['questions'] is List;
  }

  List<MobileCodexQuestion> get questions {
    final values = params['questions'];
    if (values is List && values.isNotEmpty) {
      return <MobileCodexQuestion>[
        for (var index = 0; index < values.length; index++)
          MobileCodexQuestion.fromJson(values[index], index: index),
      ];
    }
    return <MobileCodexQuestion>[MobileCodexQuestion.fromJson(params)];
  }

  String get description => _first(<Object?>[
    params['reason'],
    params['command'],
    params['path'],
    'Codex is requesting permission to continue.',
  ]);
}

class MobileCodexState {
  const MobileCodexState({
    this.events = const <Map<String, Object?>>[],
    this.timelineCells = const <MobileCodexTimelineCell>[],
    this.pendingRequests = const <MobileCodexPendingRequest>[],
    this.activeTurnId,
    this.models = const <MobileCodexModelOption>[],
    this.collaborationModes = const <Map<String, Object?>>[],
    this.skills = const <Map<String, Object?>>[],
    this.apps = const <Map<String, Object?>>[],
    this.selectedModel,
    this.reasoningEffort = 'medium',
    this.speedMode = 'normal',
    this.permissionMode = 'on-request',
    this.planMode = false,
    this.collaborationMode,
    this.queuedMessages = const <Map<String, Object?>>[],
    this.contextUsed,
    this.contextLimit,
    this.title,
    this.error,
    this.sending = false,
    this.interrupting = false,
  });

  factory MobileCodexState.fromSnapshot(Object? value) {
    final json = _map(value);
    final events = _maps(json['events']);
    var cells = <MobileCodexTimelineCell>[
      if (json['timelineCells'] is List)
        for (final item in json['timelineCells'] as List)
          MobileCodexTimelineCell.fromJson(item),
    ];
    if (cells.isEmpty && events.isNotEmpty) {
      for (final event in events) {
        cells = MobileCodexTimelineReducer.reduce(cells, event);
      }
    }
    return MobileCodexState(
      events: events,
      timelineCells: cells,
      pendingRequests: <MobileCodexPendingRequest>[
        if (json['pendingRequests'] is List)
          for (final item in json['pendingRequests'] as List)
            MobileCodexPendingRequest.fromJson(item),
      ],
      activeTurnId: _string(json['activeTurnId']),
      title: _string(json['title']),
      contextUsed: _int(json['contextUsed']),
      contextLimit: _int(json['contextLimit']),
    );
  }

  final List<Map<String, Object?>> events;
  final List<MobileCodexTimelineCell> timelineCells;
  final List<MobileCodexPendingRequest> pendingRequests;
  final String? activeTurnId;
  final List<MobileCodexModelOption> models;
  final List<Map<String, Object?>> collaborationModes;
  final List<Map<String, Object?>> skills;
  final List<Map<String, Object?>> apps;
  final String? selectedModel;
  final String reasoningEffort;
  final String speedMode;
  final String permissionMode;
  final bool planMode;
  final String? collaborationMode;
  final List<Map<String, Object?>> queuedMessages;
  final int? contextUsed;
  final int? contextLimit;
  final String? title;
  final String? error;
  final bool sending;
  final bool interrupting;

  bool get busy => sending || interrupting || activeTurnId != null;

  MobileCodexTimelineCell? get latestActionablePlan {
    var latestUserIndex = -1;
    for (var index = timelineCells.length - 1; index >= 0; index--) {
      if (timelineCells[index].isUser) {
        latestUserIndex = index;
        break;
      }
    }
    if (latestUserIndex < 0) return null;
    for (
      var index = timelineCells.length - 1;
      index > latestUserIndex;
      index--
    ) {
      final cell = timelineCells[index];
      if (cell.kind == 'plan' &&
          cell.status != 'failed' &&
          cell.status != 'declined' &&
          !cell.isStreaming &&
          (cell.markdownText ?? cell.detailsText ?? '').trim().isNotEmpty) {
        return cell;
      }
    }
    return null;
  }

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

  MobileCodexState copyWith({
    List<Map<String, Object?>>? events,
    List<MobileCodexTimelineCell>? timelineCells,
    List<MobileCodexPendingRequest>? pendingRequests,
    Object? activeTurnId = _keep,
    List<MobileCodexModelOption>? models,
    List<Map<String, Object?>>? collaborationModes,
    List<Map<String, Object?>>? skills,
    List<Map<String, Object?>>? apps,
    String? selectedModel,
    String? reasoningEffort,
    String? speedMode,
    String? permissionMode,
    bool? planMode,
    Object? collaborationMode = _keepCollaborationMode,
    List<Map<String, Object?>>? queuedMessages,
    int? contextUsed,
    int? contextLimit,
    Object? title = _keep,
    Object? error = _keep,
    bool? sending,
    bool? interrupting,
  }) => MobileCodexState(
    events: events ?? this.events,
    timelineCells: timelineCells ?? this.timelineCells,
    pendingRequests: pendingRequests ?? this.pendingRequests,
    activeTurnId: identical(activeTurnId, _keep)
        ? this.activeTurnId
        : activeTurnId as String?,
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
    contextUsed: contextUsed ?? this.contextUsed,
    contextLimit: contextLimit ?? this.contextLimit,
    title: identical(title, _keep) ? this.title : title as String?,
    error: identical(error, _keep) ? this.error : error as String?,
    sending: sending ?? this.sending,
    interrupting: interrupting ?? this.interrupting,
  );
}

const Object _keep = Object();
const Object _keepCollaborationMode = Object();
