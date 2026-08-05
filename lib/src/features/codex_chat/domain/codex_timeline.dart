import 'codex_timeline_cell.dart';

export 'codex_timeline_cell.dart';

part 'codex_timeline_helpers.dart';
part 'codex_timeline_modern.dart';

/// The host and Flutter clients use this reducer as a compatibility oracle.
/// It deliberately keys cells by app-server item IDs, so deltas update one row
/// instead of creating a card for every notification.
abstract final class CodexTimelineReducer {
  static List<CodexTimelineCell> reduce(
    List<CodexTimelineCell> cells,
    Map<String, Object?> message, {
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now().toUtc()).toUtc();
    final rawMethod = message['method']?.toString() ?? '';
    final method = switch (rawMethod) {
      'codex/event/item_started' => 'item/started',
      'codex/event/item_completed' => 'item/completed',
      'codex/event/task_complete' => 'turn/completed',
      'codex/event/token_count' => 'token_count',
      _ => rawMethod,
    };
    final params = _map(message['params']);
    final legacyMessage = _map(params['msg']);
    final item = _map(params['item'] ?? legacyMessage['item']);
    final turnId = _firstString(<Object?>[
      params['turnId'],
      _map(params['turn'])['id'],
      item['turnId'],
      item['turn_id'],
      legacyMessage['turnId'],
      legacyMessage['turn_id'],
      message['turnId'],
    ]);
    final itemId = _firstString(<Object?>[
      params['itemId'],
      item['id'],
      params['id'],
      item['itemId'],
    ]);
    final lowerMethod = method.toLowerCase();
    final type = (item['type'] ?? params['type'] ?? '')
        .toString()
        .toLowerCase();
    final modern = _reduceModernCodexNotification(
      cells,
      method: method,
      params: params,
      turnId: turnId,
      itemId: itemId,
      timestamp: timestamp,
    );
    if (modern != null) return modern;

    if (rawMethod == 'codex/event/task_complete') {
      final text = _firstString(<Object?>[
        legacyMessage['last_agent_message'],
        legacyMessage['lastAgentMessage'],
      ]);
      var next = cells;
      if (text.isNotEmpty && turnId.isNotEmpty) {
        final existing = _find(next, 'assistant-$turnId');
        next = _upsert(
          next,
          _newCell(
            id: 'assistant-$turnId',
            turnId: turnId,
            kind: CodexTimelineKind.assistantMessage,
            status: CodexTimelineStatus.completed,
            timestamp: timestamp,
            title: 'Codex',
            markdownText: text,
            isStreaming: false,
            metadata: existing?.metadata ?? const <String, Object?>{},
          ),
        );
      }
      final completed = <CodexTimelineCell>[
        for (final cell in next)
          if (cell.turnId == turnId && cell.isStreaming)
            cell.copyWith(
              status: CodexTimelineStatus.completed,
              isStreaming: false,
              updatedAt: timestamp,
            )
          else
            cell,
      ];
      return _updateTurnSeparator(completed, turnId, params, timestamp);
    }

    if (method == 'turn/started' || method == 'turn/created') {
      if (turnId.isEmpty) return cells;
      final turn = _map(params['turn']);
      return _upsert(
        cells,
        _newCell(
          id: 'turn-$turnId',
          turnId: turnId,
          kind: CodexTimelineKind.turnSeparator,
          status: CodexTimelineStatus.info,
          timestamp: timestamp,
          title: 'Turn started',
          metadata: <String, Object?>{
            'startedAt': turn['startedAt'],
            'completedAt': turn['completedAt'],
            'computedDurationMs': turn['durationMs'],
          },
        ),
      );
    }

    if (method == 'turn/completed' ||
        method == 'turn/failed' ||
        method == 'turn/aborted' ||
        method == 'turn/interrupted') {
      final turnError = _map(params['turn'])['error'];
      final failed =
          method == 'turn/failed' ||
          (turnError is String && turnError.trim().isNotEmpty) ||
          (turnError is Map && turnError.isNotEmpty);
      final completed = <CodexTimelineCell>[
        for (final cell in cells)
          if (turnId.isNotEmpty && cell.turnId == turnId && cell.isStreaming)
            cell.copyWith(
              status: failed
                  ? CodexTimelineStatus.failed
                  : CodexTimelineStatus.completed,
              isStreaming: false,
              updatedAt: timestamp,
            )
          else
            cell,
      ];
      return _updateTurnSeparator(completed, turnId, params, timestamp);
    }

    if (method == 'turn/diff/updated') {
      final diff = _firstString(<Object?>[
        params['diff'],
        params['delta'],
        params['text'],
      ]);
      final hasSnapshot =
          params.containsKey('diff') ||
          params.containsKey('delta') ||
          params.containsKey('text');
      if (turnId.isEmpty || !hasSnapshot) return cells;
      final id = 'diff-$turnId';
      final existing = _find(cells, id);
      if (existing?.metadata['lastDelta'] == diff) return cells;
      return _upsert(
        cells,
        _newCell(
          id: id,
          turnId: turnId,
          kind: CodexTimelineKind.diff,
          status: CodexTimelineStatus.inProgress,
          timestamp: timestamp,
          title: 'File changes',
          detailsText: diff,
          isStreaming: true,
          metadata: <String, Object?>{
            ...?existing?.metadata,
            'lastDelta': diff,
          },
        ),
      );
    }

    if (method == 'item/agentMessage/delta' ||
        lowerMethod.contains('agentmessage') && lowerMethod.contains('delta')) {
      final delta = _firstString(<Object?>[
        params['delta'],
        params['text'],
        legacyMessage['delta'],
        legacyMessage['text'],
        legacyMessage['message'],
      ]);
      if (delta.isEmpty || turnId.isEmpty) return cells;
      final id = itemId.isEmpty ? 'assistant-$turnId' : 'item-$itemId';
      final existing = _find(cells, id);
      final phase = _firstString(<Object?>[
        item['phase'],
        params['phase'],
        existing?.metadata['streamPhase'],
      ]);
      final finalAnswer =
          phase.isEmpty || phase == 'final_answer' || phase == 'final';
      final current = existing?.markdownText ?? '';
      final existingKind = existing?.kind;
      final metadata = <String, Object?>{
        ...?existing?.metadata,
        'streamPhase': finalAnswer ? 'final_answer' : 'commentary',
        'lastDelta': delta,
      };
      if (existing != null && existing.metadata['lastDelta'] == delta) {
        return cells;
      }
      return _upsert(
        cells,
        _newCell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind:
              finalAnswer || existingKind == CodexTimelineKind.assistantMessage
              ? CodexTimelineKind.assistantMessage
              : CodexTimelineKind.progressText,
          status: CodexTimelineStatus.inProgress,
          timestamp: timestamp,
          markdownText: '$current$delta',
          isStreaming: true,
          metadata: metadata,
        ),
      );
    }

    if (method == 'item/reasoning/summaryTextDelta' ||
        method == 'item/reasoning/textDelta' ||
        lowerMethod.contains('reasoning') && lowerMethod.contains('delta')) {
      final delta = _firstString(<Object?>[
        params['delta'],
        params['text'],
        legacyMessage['delta'],
        legacyMessage['text'],
      ]);
      if (delta.isEmpty || turnId.isEmpty) return cells;
      final id = itemId.isEmpty ? 'reasoning-$turnId' : 'item-$itemId';
      final existing = _find(cells, id);
      if (existing != null && existing.metadata['lastDelta'] == delta) {
        return cells;
      }
      return _upsert(
        cells,
        _newCell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: CodexTimelineKind.reasoning,
          status: CodexTimelineStatus.inProgress,
          timestamp: timestamp,
          title: 'Reasoning',
          markdownText: '${existing?.markdownText ?? ''}$delta',
          isStreaming: true,
          metadata: <String, Object?>{
            ...?existing?.metadata,
            'lastDelta': delta,
          },
        ),
      );
    }

    if (method == 'item/commandExecution/outputDelta' ||
        method == 'item/fileChange/outputDelta' ||
        method == 'item/mcpToolCall/outputDelta' ||
        method == 'item/webSearch/outputDelta' ||
        method == 'item/plan/delta' ||
        method == 'item/commandExecution/terminalInteraction' ||
        method == 'item/mcpToolCall/progress' ||
        lowerMethod.contains('outputdelta')) {
      final delta = _firstString(<Object?>[
        params['delta'],
        params['text'],
        params['output'],
        params['interaction'],
        legacyMessage['delta'],
        legacyMessage['text'],
      ]);
      if (delta.isEmpty || turnId.isEmpty) return cells;
      final provisionalKind = _kindFor(type, lowerMethod);
      final id = itemId.isEmpty
          ? '${provisionalKind.name}-$turnId'
          : 'item-$itemId';
      final existing = _find(cells, id);
      final kind = existing?.kind ?? provisionalKind;
      if (existing?.metadata['lastDelta'] == delta) return cells;
      final resolvedId = itemId.isEmpty
          ? '${kind.name}-$turnId'
          : 'item-$itemId';
      final details = existing?.detailsText ?? existing?.markdownText ?? '';
      return _upsert(
        cells,
        _newCell(
          id: resolvedId,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: kind,
          status: CodexTimelineStatus.inProgress,
          timestamp: timestamp,
          title: _titleFor(type, lowerMethod),
          detailsText: '$details$delta',
          isStreaming: true,
          metadata: <String, Object?>{
            ...?existing?.metadata,
            'lastDelta': delta,
          },
        ),
      );
    }

    if ((lowerMethod.contains('subagent') || lowerMethod.contains('collab')) &&
        turnId.isNotEmpty) {
      final delta = _firstString(<Object?>[
        params['delta'],
        params['text'],
        params['summary'],
        params['message'],
        legacyMessage['summary'],
        legacyMessage['message'],
      ]);
      final id = itemId.isEmpty ? 'subAgent-$turnId' : 'item-$itemId';
      final existing = _find(cells, id);
      if (existing?.metadata['lastDelta'] == delta) return cells;
      return _upsert(
        cells,
        _newCell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: CodexTimelineKind.subAgent,
          status:
              lowerMethod.contains('completed') || lowerMethod.contains('end')
              ? CodexTimelineStatus.completed
              : CodexTimelineStatus.inProgress,
          timestamp: timestamp,
          title: 'Sub-agent',
          markdownText: delta.isEmpty
              ? existing?.markdownText
              : '${existing?.markdownText ?? ''}$delta',
          isStreaming:
              !lowerMethod.contains('completed') &&
              !lowerMethod.contains('end'),
          metadata: <String, Object?>{
            ...?existing?.metadata,
            if (delta.isNotEmpty) 'lastDelta': delta,
          },
        ),
      );
    }

    if (method == 'item/started' ||
        method == 'item/completed' ||
        method == 'item/updated') {
      if (turnId.isEmpty) return cells;
      final provisionalId = itemId.isEmpty ? '$type-$turnId' : 'item-$itemId';
      final existing = _find(cells, provisionalId);
      final phase = _firstString(<Object?>[
        item['phase'],
        params['phase'],
        existing?.metadata['streamPhase'],
      ]);
      final isAgentMessage =
          type.contains('agentmessage') || type.contains('assistant');
      final kind = isAgentMessage && phase == 'commentary'
          ? CodexTimelineKind.progressText
          : _kindFor(type, lowerMethod);
      final id = kind == CodexTimelineKind.userMessage
          ? 'user-$turnId'
          : itemId.isEmpty
          ? '${kind.name}-$turnId'
          : 'item-$itemId';
      final current = _find(cells, id) ?? existing;
      final fullText = _itemMarkdown(item);
      final details = _itemDetails(item);
      final rawStatus = (item['status'] ?? params['status'] ?? '')
          .toString()
          .toLowerCase();
      final status = rawStatus.contains('fail')
          ? CodexTimelineStatus.failed
          : rawStatus.contains('declin')
          ? CodexTimelineStatus.declined
          : method == 'item/completed'
          ? CodexTimelineStatus.completed
          : CodexTimelineStatus.inProgress;
      return _upsert(
        cells,
        _newCell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: kind,
          status: status,
          timestamp: timestamp,
          title: _titleFor(type, lowerMethod, item: item),
          subtitle: _firstString(<Object?>[
            item['command'],
            item['name'],
            item['path'],
            item['cwd'],
            item['server'],
          ]),
          markdownText: fullText.isEmpty ? current?.markdownText : fullText,
          detailsText: details.isEmpty ? current?.detailsText : details,
          isStreaming: method != 'item/completed',
          metadata: <String, Object?>{
            ...?current?.metadata,
            'itemType': item['type'],
            'type': item['type'],
            'query': item['query'],
            'url': item['url'],
            'action': item['action'],
            'changes': item['changes'],
            'arguments': item['arguments'],
            'result': item['result'],
            'commandActions': item['commandActions'],
            'durationMs': item['durationMs'],
            'status': item['status'],
            if (isAgentMessage && phase.isNotEmpty) 'streamPhase': phase,
          },
        ),
      );
    }

    if (method == 'error' ||
        method == 'stream/error' ||
        method == 'stream_error') {
      final text = _firstString(<Object?>[
        params['message'],
        params['error'],
        message['error'],
      ]);
      if (text.isEmpty) return cells;
      return <CodexTimelineCell>[
        ...cells,
        _newCell(
          id: 'error-${timestamp.microsecondsSinceEpoch}',
          turnId: turnId.isEmpty ? null : turnId,
          kind: CodexTimelineKind.systemNotice,
          status: CodexTimelineStatus.failed,
          timestamp: timestamp,
          title: 'Codex error',
          markdownText: text,
        ),
      ];
    }

    if (method.contains('review') && turnId.isNotEmpty) {
      final title = method.contains('enter')
          ? 'Preparing review'
          : 'Review finished';
      final review = _firstString(<Object?>[
        params['review'],
        item['review'],
        params['text'],
      ]);
      final id = itemId.isEmpty ? 'review-$turnId' : 'item-$itemId';
      final result = _upsert(
        cells,
        _newCell(
          id: id,
          itemId: itemId.isEmpty ? null : itemId,
          turnId: turnId,
          kind: CodexTimelineKind.toolCall,
          status: CodexTimelineStatus.completed,
          timestamp: timestamp,
          title: title,
          detailsText: review.isEmpty ? null : review,
        ),
      );
      if (review.isEmpty) return result;
      return <CodexTimelineCell>[
        ...result,
        _newCell(
          id: 'review-body-$turnId',
          turnId: turnId,
          kind: CodexTimelineKind.progressText,
          status: CodexTimelineStatus.completed,
          timestamp: timestamp,
          markdownText: review,
          metadata: <String, Object?>{
            CodexTimelineMetadata.uiPlacement:
                CodexTimelineMetadata.outsideWorked,
          },
        ),
      ];
    }

    return cells;
  }
}
