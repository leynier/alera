import 'package:flutter/foundation.dart';

part 'mobile_codex_timeline.dart';
part 'mobile_codex_timeline_event.dart';
part 'mobile_codex_timeline_classification.dart';
part 'mobile_codex_timeline_compaction.dart';
part 'mobile_codex_timeline_content.dart';
part 'mobile_codex_model_option.dart';
part 'mobile_codex_requests.dart';
part 'mobile_codex_state_helpers.dart';
part 'mobile_codex_projection.dart';
part 'mobile_codex_thread_models.dart';
part 'mobile_codex_goal.dart';

@immutable
class const MobileCodexTimelineCell({
  required final String id,
  required final String kind,
  required final String status,
  final String? itemId,
  final String? turnId,
  final DateTime? createdAt,
  final DateTime? updatedAt,
  final String? title,
  final String? subtitle,
  final String? markdownText,
  final String? renderedMarkdownText,
  final String? detailsText,
  final bool isStreaming = false,
  final bool isCollapsed = false,
  final Map<String, Object?> metadata = const <String, Object?>{},
}) {
  factory fromJson(Object? value) {
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

  MobileCodexTimelineCell copyWith({
    String? id,
    String? kind,
    String? status,
    String? itemId,
    String? turnId,
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
    id: id ?? this.id,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    itemId: itemId ?? this.itemId,
    turnId: turnId ?? this.turnId,
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

class const MobileCodexState({
  final List<Map<String, Object?>> events = const <Map<String, Object?>>[],
  final List<MobileCodexTimelineCell> timelineCells =
      const <MobileCodexTimelineCell>[],
  final Set<String> paginatedHistoryCellIds = const <String>{},
  final List<MobileCodexPendingRequest> pendingRequests =
      const <MobileCodexPendingRequest>[],
  final String? activeTurnId,
  final List<MobileCodexModelOption> models = const <MobileCodexModelOption>[],
  final List<Map<String, Object?>> collaborationModes =
      const <Map<String, Object?>>[],
  final List<Map<String, Object?>> skills = const <Map<String, Object?>>[],
  final List<Map<String, Object?>> apps = const <Map<String, Object?>>[],
  final String? selectedModel,
  final String reasoningEffort = 'medium',
  final String speedMode = 'normal',
  final String permissionMode = 'untrusted',
  final bool planMode = false,
  final String? collaborationMode,
  final List<Map<String, Object?>> queuedMessages =
      const <Map<String, Object?>>[],
  final int? contextUsed,
  final int? contextLimit,
  final List<String> promptHistory = const <String>[],
  final bool mcpInitializing = false,
  final String? title,
  final String? activeCwd,
  final String? historyNextCursor,
  final String? error,
  final bool sending = false,
  final bool interrupting = false,
  final List<MobileCodexPresentationRow> presentationRows =
      const <MobileCodexPresentationRow>[],
  final MobileCodexThreadRecovery? recovery,
  final MobileCodexGoal? goal,
}) {
  factory fromSnapshot(Object? value, {bool deriveTimeline = true}) {
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
      promptHistory: deriveTimeline
          ? mobileCodexPromptHistory(cells)
          : const <String>[],
      mcpInitializing: deriveTimeline
          ? mobileCodexHasInitializingMcp(cells)
          : false,
      presentationRows: deriveTimeline
          ? MobileCodexTimelineProjection.project(
              cells,
              activeTurnId: activeTurnId,
            )
          : const <MobileCodexPresentationRow>[],
      goal: json['goal'] is Map ? MobileCodexGoal.fromJson(json['goal']) : null,
    );
  }

  MobileCodexState applySnapshotDelta(
    Object? value, {
    bool deriveTimeline = true,
  }) {
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
    final nextPaginatedHistoryCellIds = removedIds.isEmpty
        ? paginatedHistoryCellIds
        : Set<String>.unmodifiable(
            paginatedHistoryCellIds.difference(removedIds),
          );
    return copyWith(
      events: nextEvents,
      timelineCells: nextCells,
      paginatedHistoryCellIds: nextPaginatedHistoryCellIds,
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
      goal: json.containsKey('goal')
          ? json['goal'] is Map
                ? MobileCodexGoal.fromJson(json['goal'])
                : null
          : goal,
      promptHistory: cellsChanged && deriveTimeline
          ? mobileCodexPromptHistory(nextCells)
          : promptHistory,
      mcpInitializing: cellsChanged && deriveTimeline
          ? mobileCodexHasInitializingMcp(nextCells)
          : mcpInitializing,
      presentationRows: deriveTimeline
          ? MobileCodexTimelineProjection.project(
              nextCells,
              activeTurnId: nextActiveTurnId,
            )
          : presentationRows,
    );
  }

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
    Set<String>? paginatedHistoryCellIds,
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
    Object? goal = _keepGoal,
  }) => MobileCodexState(
    events: events ?? this.events,
    timelineCells: timelineCells ?? this.timelineCells,
    paginatedHistoryCellIds:
        paginatedHistoryCellIds ?? this.paginatedHistoryCellIds,
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
    goal: identical(goal, _keepGoal) ? this.goal : goal as MobileCodexGoal?,
  );
}

const Object _keepGoal = Object();

const Object _keep = Object();
const Object _keepRecovery = Object();
const Object _keepCollaborationMode = Object();

List<String> mobileCodexPromptHistory(List<MobileCodexTimelineCell> cells) =>
    List<String>.unmodifiableOf(<String>[
      for (final cell in cells)
        if (cell.kind == 'userMessage' &&
            cell.metadata['isSteering'] != true &&
            cell.metadata['isGoal'] != true &&
            (cell.markdownText ?? '').trim().isNotEmpty)
          cell.markdownText!.trim(),
    ]);

bool mobileCodexHasInitializingMcp(List<MobileCodexTimelineCell> cells) =>
    cells.any(
      (cell) =>
          cell.metadata['itemType'] == 'mcpServerStartup' &&
          (cell.isStreaming || cell.status == 'inProgress'),
    );
