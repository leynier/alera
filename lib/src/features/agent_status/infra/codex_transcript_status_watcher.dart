import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';

part 'codex_transcript_watch.dart';

class CodexTranscriptStatusWatcher {
  CodexTranscriptStatusWatcher(
    this._statusSink, [
    this._watchdogInterval = const Duration(seconds: 5),
    this._appForeground = const AlwaysForeground(),
  ]);

  final AgentStatusSink _statusSink;
  final Duration _watchdogInterval;
  final AppForeground _appForeground;
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
      appForeground: _appForeground,
    );
    _watches[event.terminalSessionId] = watch;
    watch.start();
  }

  Future<void> scanNowForTesting(String terminalSessionId) async {
    await _watches[terminalSessionId]?.scan();
  }

  /// Drops the watch for a terminal session that no longer exists.
  ///
  /// A Codex `Stop` hook is the normal end of a watch, but a terminal closed
  /// mid-turn never emits one, and without this the file watcher and its
  /// timers keep polling the transcript for the rest of the session.
  void clearTerminal(String terminalSessionId) {
    _watches.remove(terminalSessionId)?.dispose();
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
