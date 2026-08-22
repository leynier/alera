import 'dart:collection';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_event_normalizer.dart';

final class AgentHookLifecycleGuard {
  static const _ampCompletedThreadLimit = 32;
  static const _legacyAmpThreadKey = '<legacy>';

  final Map<String, _AgyCompletedTurn> _agyCompletedTurns = {};
  final Map<String, _AmpTerminalLifecycle> _ampTerminals = {};
  final Map<String, String> _workspaceByTerminal = {};

  bool shouldApply(AgentHookEvent event) {
    _workspaceByTerminal[event.terminalSessionId] = event.workspaceId;
    final eventName = agentHookEventName(event);
    if (eventName == null) {
      return true;
    }
    return switch (event.agentType) {
      AgentType.agy => _shouldApplyAgy(event, eventName),
      AgentType.amp => _shouldApplyAmp(event, eventName),
      AgentType.codex ||
      AgentType.claude ||
      AgentType.copilot ||
      AgentType.cursor ||
      AgentType.opencode ||
      AgentType.opencode2 ||
      AgentType.pi ||
      AgentType.grok ||
      AgentType.fx => true,
    };
  }

  void clearTerminal(String terminalSessionId) {
    _agyCompletedTurns.remove(terminalSessionId);
    _ampTerminals.remove(terminalSessionId);
    _workspaceByTerminal.remove(terminalSessionId);
  }

  void clearWorkspace(String workspaceId) {
    final terminalSessionIds = <String>[
      for (final entry in _workspaceByTerminal.entries)
        if (entry.value == workspaceId) entry.key,
    ];
    for (final terminalSessionId in terminalSessionIds) {
      clearTerminal(terminalSessionId);
    }
  }

  void reset() {
    _agyCompletedTurns.clear();
    _ampTerminals.clear();
    _workspaceByTerminal.clear();
  }

  bool _shouldApplyAgy(AgentHookEvent event, String eventName) {
    final terminalSessionId = event.terminalSessionId;
    if (eventName == 'PreInvocation') {
      _agyCompletedTurns.remove(terminalSessionId);
      return true;
    }

    final completed = _agyCompletedTurns[terminalSessionId];
    if (completed != null && eventName != 'Stop') {
      final transcriptPath = _readString(event.payload, const [
        'transcriptPath',
        'transcript_path',
      ]);
      if (completed.transcriptPath == null ||
          transcriptPath == null ||
          completed.transcriptPath == transcriptPath) {
        return false;
      }
    }

    if (eventName == 'Stop' && !_agyStopStillBusy(event.payload)) {
      _agyCompletedTurns[terminalSessionId] = _AgyCompletedTurn(
        _readString(event.payload, const ['transcriptPath', 'transcript_path']),
      );
    }
    return true;
  }

  bool _shouldApplyAmp(AgentHookEvent event, String eventName) {
    final terminal = _ampTerminals.putIfAbsent(
      event.terminalSessionId,
      _AmpTerminalLifecycle.new,
    );
    final threadKey = _ampThreadKey(event.payload);
    if (eventName == 'session.start') {
      terminal.completedThreads.remove(threadKey);
      return false;
    }
    if (eventName == 'agent.start') {
      terminal.completedThreads.remove(threadKey);
      return true;
    }
    if ((eventName == 'tool.call' || eventName == 'tool.result') &&
        terminal.completedThreads.contains(threadKey)) {
      return false;
    }
    if (eventName == 'agent.end') {
      terminal.completedThreads
        ..remove(threadKey)
        ..add(threadKey);
      while (terminal.completedThreads.length > _ampCompletedThreadLimit) {
        terminal.completedThreads.remove(terminal.completedThreads.first);
      }
    }
    return true;
  }

  String _ampThreadKey(Map<String, Object?> payload) {
    final direct = _readString(payload, const [
      'threadId',
      'threadID',
      'thread_id',
    ]);
    if (direct != null) {
      return direct;
    }
    final thread = payload['thread'];
    if (thread is Map) {
      final nested = _readString(Map<String, Object?>.from(thread), const [
        'id',
      ]);
      if (nested != null) {
        return nested;
      }
    }
    return _legacyAmpThreadKey;
  }

  String? _readString(Map<String, Object?> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  bool _agyStopStillBusy(Map<String, Object?> payload) {
    return payload['fullyIdle'] == false || payload['fully_idle'] == false;
  }
}

final class _AgyCompletedTurn {
  const _AgyCompletedTurn(this.transcriptPath);

  final String? transcriptPath;
}

final class _AmpTerminalLifecycle {
  final LinkedHashSet<String> completedThreads = LinkedHashSet<String>();
}
