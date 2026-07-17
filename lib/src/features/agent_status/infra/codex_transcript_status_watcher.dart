import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';

part 'codex_transcript_watch.dart';

class CodexTranscriptStatusWatcher {
  CodexTranscriptStatusWatcher(
    this._statusSink, [
    this._watchdogInterval = const Duration(seconds: 5),
  ]);

  final AgentStatusSink _statusSink;
  final Duration _watchdogInterval;
  final Map<String, _CodexTranscriptWatch> _watches =
      <String, _CodexTranscriptWatch>{};

  void observeHookEvent(AgentHookEvent event) {
    if (event.agentType != AgentType.codex) {
      return;
    }
    final eventName = _hookEventName(event);
    if (eventName == 'Stop') {
      _watches.remove(event.terminalSessionId)?.dispose();
      return;
    }
    if (eventName != 'UserPromptSubmit') {
      return;
    }

    final transcriptPath = _readString(event.payload, const <String>[
      'transcript_path',
      'transcriptPath',
    ]);
    if (transcriptPath == null) {
      return;
    }

    final previous = _watches.remove(event.terminalSessionId);
    previous?.dispose();
    final watch = _CodexTranscriptWatch(
      statusSink: _statusSink,
      terminalSessionId: event.terminalSessionId,
      workspaceId: event.workspaceId,
      tabId: event.tabId,
      transcriptPath: transcriptPath,
      turnId: _readString(event.payload, const <String>['turn_id', 'turnId']),
      watchdogInterval: _watchdogInterval,
    );
    _watches[event.terminalSessionId] = watch;
    watch.start();
  }

  Future<void> scanNowForTesting(String terminalSessionId) async {
    await _watches[terminalSessionId]?.scan();
  }

  void clear() {
    for (final watch in _watches.values) {
      watch.dispose();
    }
    _watches.clear();
  }

  void dispose() {
    clear();
  }
}
