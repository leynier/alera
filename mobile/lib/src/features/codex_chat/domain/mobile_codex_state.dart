import 'package:flutter/foundation.dart';

part 'mobile_codex_timeline.dart';
part 'mobile_codex_requests.dart';
part 'mobile_codex_state_helpers.dart';
part 'mobile_codex_projection.dart';
part 'mobile_codex_thread_models.dart';

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
    this.permissionMode = 'untrusted',
    this.planMode = false,
    this.collaborationMode,
    this.queuedMessages = const <Map<String, Object?>>[],
    this.contextUsed,
    this.contextLimit,
    this.promptHistory = const <String>[],
    this.mcpInitializing = false,
    this.title,
    this.activeCwd,
    this.historyNextCursor,
    this.error,
    this.sending = false,
    this.interrupting = false,
    this.presentationRows = const <MobileCodexPresentationRow>[],
    this.recovery,
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
    final activeTurnId = _string(json['activeTurnId']);
    return MobileCodexState(
      events: events,
      timelineCells: cells,
      pendingRequests: <MobileCodexPendingRequest>[
        if (json['pendingRequests'] is List)
          for (final item in json['pendingRequests'] as List)
            MobileCodexPendingRequest.fromJson(item),
      ],
      activeTurnId: activeTurnId,
      title: _string(json['title']),
      activeCwd: _string(json['activeCwd']),
      historyNextCursor: _string(json['historyNextCursor']),
      contextUsed: _int(json['contextUsed']),
      contextLimit: _int(json['contextLimit']),
      promptHistory: mobileCodexPromptHistory(cells),
      mcpInitializing: _mobileCodexHasInitializingMcp(cells),
      presentationRows: MobileCodexTimelineProjection.project(
        cells,
        activeTurnId: activeTurnId,
      ),
    );
  }

  MobileCodexState applySnapshotDelta(Object? value) {
    final json = _map(value);
    if (json.isEmpty) return this;
    final removedIds = <String>{
      if (json['timelineRemovedIds'] is List)
        for (final id in json['timelineRemovedIds'] as List)
          if (id?.toString() case final String value when value.isNotEmpty)
            value,
    };
    final upserts = <String, MobileCodexTimelineCell>{};
    if (json['timelineUpserts'] is List) {
      for (final item in json['timelineUpserts'] as List) {
        if (item is! Map) continue;
        final cell = MobileCodexTimelineCell.fromJson(item);
        upserts[cell.id] = cell;
      }
    }
    final cellsChanged = removedIds.isNotEmpty || upserts.isNotEmpty;
    final nextCells = !cellsChanged
        ? timelineCells
        : <MobileCodexTimelineCell>[
            for (final cell in timelineCells)
              if (!removedIds.contains(cell.id))
                upserts.remove(cell.id) ?? cell,
            ...upserts.values,
          ];
    final replacementEvents = json['eventsReplace'] is List
        ? _maps(json['eventsReplace'])
        : null;
    final appendedEvents = _maps(json['eventsAppend']);
    final eventLimit = _int(json['eventLimit']) ?? 160;
    final combinedEvents =
        replacementEvents ??
        (appendedEvents.isEmpty
            ? events
            : <Map<String, Object?>>[...events, ...appendedEvents]);
    final nextEvents = combinedEvents.length <= eventLimit
        ? combinedEvents
        : combinedEvents.sublist(combinedEvents.length - eventLimit);
    final nextActiveTurnId = json.containsKey('activeTurnId')
        ? _string(json['activeTurnId'])
        : activeTurnId;
    return copyWith(
      events: nextEvents,
      timelineCells: nextCells,
      pendingRequests: json.containsKey('pendingRequests')
          ? <MobileCodexPendingRequest>[
              if (json['pendingRequests'] is List)
                for (final item in json['pendingRequests'] as List)
                  MobileCodexPendingRequest.fromJson(item),
            ]
          : pendingRequests,
      activeTurnId: nextActiveTurnId,
      contextUsed: json.containsKey('contextUsed')
          ? _int(json['contextUsed'])
          : contextUsed,
      contextLimit: json.containsKey('contextLimit')
          ? _int(json['contextLimit'])
          : contextLimit,
      title: json.containsKey('title') ? _string(json['title']) : title,
      promptHistory: cellsChanged
          ? mobileCodexPromptHistory(nextCells)
          : promptHistory,
      mcpInitializing: cellsChanged
          ? _mobileCodexHasInitializingMcp(nextCells)
          : mcpInitializing,
      presentationRows: MobileCodexTimelineProjection.project(
        nextCells,
        activeTurnId: nextActiveTurnId,
      ),
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
  final List<String> promptHistory;
  final bool mcpInitializing;
  final String? title;
  final String? activeCwd;
  final String? historyNextCursor;
  final String? error;
  final bool sending;
  final bool interrupting;
  final List<MobileCodexPresentationRow> presentationRows;
  final MobileCodexThreadRecovery? recovery;

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
      if (cell.kind == 'systemNotice' &&
          const <String>{
            'threadBoundary',
            'contextReset',
          }.contains(cell.metadata['noticeType'])) {
        return null;
      }
      if (cell.kind == 'plan' &&
          cell.metadata['plan'] is! List &&
          cell.status != 'failed' &&
          cell.status != 'declined' &&
          !cell.isStreaming &&
          (cell.markdownText ?? cell.detailsText ?? '').trim().isNotEmpty) {
        return cell;
      }
    }
    return null;
  }

  bool get hasEquivalentPlanRequest =>
      pendingRequests.any((request) => request.isImplementPlanQuestion);

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
    Object? contextUsed = _keep,
    Object? contextLimit = _keep,
    List<String>? promptHistory,
    bool? mcpInitializing,
    Object? title = _keep,
    Object? activeCwd = _keep,
    Object? historyNextCursor = _keep,
    Object? error = _keep,
    bool? sending,
    bool? interrupting,
    List<MobileCodexPresentationRow>? presentationRows,
    Object? recovery = _keepRecovery,
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
    contextUsed: identical(contextUsed, _keep)
        ? this.contextUsed
        : contextUsed as int?,
    contextLimit: identical(contextLimit, _keep)
        ? this.contextLimit
        : contextLimit as int?,
    promptHistory: promptHistory ?? this.promptHistory,
    mcpInitializing: mcpInitializing ?? this.mcpInitializing,
    title: identical(title, _keep) ? this.title : title as String?,
    activeCwd: identical(activeCwd, _keep)
        ? this.activeCwd
        : activeCwd as String?,
    historyNextCursor: identical(historyNextCursor, _keep)
        ? this.historyNextCursor
        : historyNextCursor as String?,
    error: identical(error, _keep) ? this.error : error as String?,
    sending: sending ?? this.sending,
    interrupting: interrupting ?? this.interrupting,
    presentationRows:
        presentationRows ??
        (timelineCells == null && identical(activeTurnId, _keep)
            ? this.presentationRows
            : MobileCodexTimelineProjection.project(
                timelineCells ?? this.timelineCells,
                activeTurnId: identical(activeTurnId, _keep)
                    ? this.activeTurnId
                    : activeTurnId as String?,
              )),
    recovery: identical(recovery, _keepRecovery)
        ? this.recovery
        : recovery as MobileCodexThreadRecovery?,
  );
}

const Object _keep = Object();
const Object _keepRecovery = Object();
const Object _keepCollaborationMode = Object();

List<String> mobileCodexPromptHistory(List<MobileCodexTimelineCell> cells) =>
    List<String>.unmodifiable(<String>[
      for (final cell in cells)
        if (cell.kind == 'userMessage' &&
            cell.metadata['isSteering'] != true &&
            (cell.markdownText ?? '').trim().isNotEmpty)
          cell.markdownText!.trim(),
    ]);

bool _mobileCodexHasInitializingMcp(List<MobileCodexTimelineCell> cells) =>
    cells.any(
      (cell) =>
          cell.metadata['itemType'] == 'mcpServerStartup' &&
          (cell.isStreaming || cell.status == 'inProgress'),
    );
