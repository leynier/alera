part of 'codex_timeline.dart';

List<CodexTimelineCell>? _reduceModernCodexNotification(
  List<CodexTimelineCell> cells, {
  required String method,
  required Map<String, Object?> params,
  required String turnId,
  required String itemId,
  required DateTime timestamp,
}) => switch (method) {
  'turn/plan/updated' when turnId.isNotEmpty => _reduceModernPlan(
    cells,
    params: params,
    turnId: turnId,
    timestamp: timestamp,
  ),
  'item/fileChange/patchUpdated' when turnId.isNotEmpty => _upsert(
    cells,
    _newCell(
      id: itemId.isEmpty ? 'diff-$turnId' : 'item-$itemId',
      itemId: itemId.isEmpty ? null : itemId,
      turnId: turnId,
      kind: CodexTimelineKind.diff,
      status: CodexTimelineStatus.inProgress,
      timestamp: timestamp,
      title: 'File changes',
      isStreaming: true,
      metadata: <String, Object?>{
        'itemType': 'fileChange',
        'changes': params['changes'] ?? const <Object?>[],
      },
    ),
  ),
  'thread/compacted' when turnId.isNotEmpty => _completeContextCompaction(
    cells,
    turnId: turnId,
    timestamp: timestamp,
  ),
  'model/rerouted' when turnId.isNotEmpty => _reduceModelReroute(
    cells,
    params: params,
    turnId: turnId,
    timestamp: timestamp,
  ),
  'model/verification' when turnId.isNotEmpty => _upsert(
    cells,
    _newCell(
      id: 'model-verification-$turnId',
      turnId: turnId,
      kind: CodexTimelineKind.systemNotice,
      status: CodexTimelineStatus.info,
      timestamp: timestamp,
      title: 'Account verification',
      markdownText: _verificationMarkdown(params['verifications']),
      metadata: <String, Object?>{'verifications': params['verifications']},
    ),
  ),
  'model/safetyBuffering/updated' when turnId.isNotEmpty =>
    _reduceSafetyBuffering(
      cells,
      params: params,
      turnId: turnId,
      timestamp: timestamp,
    ),
  'mcpServer/startupStatus/updated' => _reduceMcpStartup(
    cells,
    params: params,
    turnId: turnId,
    timestamp: timestamp,
  ),
  'warning' ||
  'guardianWarning' ||
  'configWarning' ||
  'deprecationNotice' => _reduceCodexNotice(
    cells,
    method: method,
    params: params,
    turnId: turnId,
    timestamp: timestamp,
  ),
  _ => null,
};

List<CodexTimelineCell> _completeContextCompaction(
  List<CodexTimelineCell> cells, {
  required String turnId,
  required DateTime timestamp,
}) {
  final index = cells.lastIndexWhere(
    (cell) =>
        cell.turnId == turnId &&
        cell.metadata['itemType'].toString().toLowerCase().contains(
          'contextcompaction',
        ),
  );
  if (index < 0) {
    return _upsert(
      cells,
      _newCell(
        id: 'compaction-$turnId',
        turnId: turnId,
        kind: CodexTimelineKind.toolCall,
        status: CodexTimelineStatus.completed,
        timestamp: timestamp,
        title: 'Compacted',
        metadata: const <String, Object?>{'itemType': 'contextCompaction'},
      ),
    );
  }
  return <CodexTimelineCell>[
    for (var position = 0; position < cells.length; position++)
      position == index
          ? cells[position].copyWith(
              status: CodexTimelineStatus.completed,
              title: 'Compacted',
              isStreaming: false,
              updatedAt: timestamp,
            )
          : cells[position],
  ];
}

String _verificationMarkdown(Object? verifications) {
  final details = verifications?.toString() ?? '';
  return details.isEmpty || details == '[]'
      ? 'Codex requires additional account verification.'
      : 'Codex requires additional account verification: `$details`.';
}

List<CodexTimelineCell> _reduceSafetyBuffering(
  List<CodexTimelineCell> cells, {
  required Map<String, Object?> params,
  required String turnId,
  required DateTime timestamp,
}) {
  final visible = params['showBufferingUi'] == true;
  final fasterModel = params['fasterModel']?.toString().trim() ?? '';
  return _upsert(
    cells,
    _newCell(
      id: 'safety-buffering-$turnId',
      turnId: turnId,
      kind: CodexTimelineKind.systemNotice,
      status: visible
          ? CodexTimelineStatus.inProgress
          : CodexTimelineStatus.completed,
      timestamp: timestamp,
      title: 'Safety review',
      markdownText:
          'Codex is checking this request before continuing.${fasterModel.isEmpty ? '' : '\n\nA faster model is available: `$fasterModel`.'}',
      isStreaming: visible,
      metadata: <String, Object?>{
        'model': params['model'],
        'useCases': params['useCases'],
        'reasons': params['reasons'],
        'showBufferingUi': visible,
        'fasterModel': params['fasterModel'],
      },
    ),
  );
}

List<CodexTimelineCell> _reduceMcpStartup(
  List<CodexTimelineCell> cells, {
  required Map<String, Object?> params,
  required String turnId,
  required DateTime timestamp,
}) {
  final name = params['name']?.toString().trim();
  final status = params['status']?.toString() ?? 'starting';
  final failed = status.toLowerCase() == 'failed';
  final starting = status.toLowerCase() == 'starting';
  return _upsert(
    cells,
    _newCell(
      id: 'mcp-startup-${name?.isNotEmpty == true ? name : 'MCP'}',
      turnId: turnId.isEmpty ? null : turnId,
      kind: CodexTimelineKind.toolCall,
      status: failed
          ? CodexTimelineStatus.failed
          : starting
          ? CodexTimelineStatus.inProgress
          : CodexTimelineStatus.completed,
      timestamp: timestamp,
      title: '${name?.isNotEmpty == true ? name : 'MCP'} MCP server',
      subtitle: status,
      detailsText: (params['error'] ?? params['failureReason'])?.toString(),
      isStreaming: starting,
      metadata: <String, Object?>{
        'itemType': 'mcpServerStartup',
        'status': status,
        'failureReason': params['failureReason'],
      },
    ),
  );
}

List<CodexTimelineCell> _reduceModernPlan(
  List<CodexTimelineCell> cells, {
  required Map<String, Object?> params,
  required String turnId,
  required DateTime timestamp,
}) {
  final plan = switch (params['plan']) {
    final List<Object?> value => value,
    _ => const <Object?>[],
  };
  final complete =
      plan.isNotEmpty &&
      plan.every(
        (entry) =>
            _map(entry)['status']?.toString().toLowerCase() == 'completed',
      );
  return _upsert(
    cells,
    _newCell(
      id: 'plan-$turnId',
      turnId: turnId,
      kind: CodexTimelineKind.plan,
      status: complete
          ? CodexTimelineStatus.completed
          : CodexTimelineStatus.inProgress,
      timestamp: timestamp,
      title: 'Plan',
      markdownText: _modernPlanMarkdown(params['explanation'], plan),
      isStreaming: !complete,
      metadata: <String, Object?>{
        'explanation': params['explanation'],
        'plan': plan,
      },
    ),
  );
}

String _modernPlanMarkdown(Object? explanation, List<Object?> plan) {
  final sections = <String>[];
  final intro = explanation?.toString().trim() ?? '';
  if (intro.isNotEmpty) sections.add(intro);
  final steps = <String>[];
  for (final entry in plan) {
    final step = _map(entry);
    final text = step['step']?.toString().trim() ?? '';
    if (text.isEmpty) continue;
    final status = step['status']?.toString().toLowerCase() ?? 'pending';
    final marker = status == 'completed' ? 'x' : ' ';
    final suffix = status == 'inprogress' ? ' *(In progress)*' : '';
    steps.add('- [$marker] $text$suffix');
  }
  if (steps.isNotEmpty) sections.add(steps.join('\n'));
  return sections.join('\n\n');
}

List<CodexTimelineCell> _reduceModelReroute(
  List<CodexTimelineCell> cells, {
  required Map<String, Object?> params,
  required String turnId,
  required DateTime timestamp,
}) {
  final from = params['fromModel']?.toString() ?? 'the selected model';
  final to = params['toModel']?.toString() ?? 'another model';
  final reason = params['reason']?.toString().trim() ?? '';
  return _upsert(
    cells,
    _newCell(
      id: 'model-reroute-$turnId',
      turnId: turnId,
      kind: CodexTimelineKind.systemNotice,
      status: CodexTimelineStatus.info,
      timestamp: timestamp,
      title: 'Model changed',
      markdownText:
          'Codex switched from `$from` to `$to`${reason.isEmpty ? '' : ' because $reason'}.',
      metadata: <String, Object?>{
        'fromModel': params['fromModel'],
        'toModel': params['toModel'],
        'reason': params['reason'],
      },
    ),
  );
}

List<CodexTimelineCell> _reduceCodexNotice(
  List<CodexTimelineCell> cells, {
  required String method,
  required Map<String, Object?> params,
  required String turnId,
  required DateTime timestamp,
}) {
  final summary = (params['message'] ?? params['summary'])?.toString().trim();
  final details = params['details']?.toString().trim();
  final text = <String>[
    if (summary != null && summary.isNotEmpty) summary,
    if (details != null && details.isNotEmpty) details,
  ].join('\n\n');
  if (text.isEmpty) return cells;
  final title = switch (method) {
    'deprecationNotice' => 'Codex deprecation',
    'configWarning' => 'Configuration warning',
    'guardianWarning' => 'Safety warning',
    _ => 'Codex warning',
  };
  return <CodexTimelineCell>[
    ...cells,
    _newCell(
      id: 'notice-${timestamp.microsecondsSinceEpoch}',
      turnId: turnId.isEmpty ? null : turnId,
      kind: CodexTimelineKind.systemNotice,
      status: CodexTimelineStatus.info,
      timestamp: timestamp,
      title: title,
      subtitle: params['path']?.toString(),
      markdownText: text,
      metadata: <String, Object?>{'noticeType': method},
    ),
  ];
}
