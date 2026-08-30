import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/codex_transcript_status_watcher.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:flutter_test/flutter_test.dart';

/// The transcript watchdog is the only poller in the app that scales with how
/// many agents are running: a stat plus an incremental read per transcript,
/// every interval. These cases pin that it stops while nobody can see its
/// results, and that stopping never costs an update.
void main() {
  group('Codex transcript watchdog parking', () {
    late Directory tempDir;
    late File transcript;
    late _FakeStatusSink sink;
    late _FakeAppForeground foreground;
    late CodexTranscriptStatusWatcher watcher;

    const watchdogInterval = Duration(milliseconds: 20);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('alera-codex-parking-');
      transcript = File('${tempDir.path}/rollout.jsonl');
      transcript.writeAsStringSync(_turnStart);
      sink = _FakeStatusSink();
      foreground = _FakeAppForeground();
      watcher = CodexTranscriptStatusWatcher(
        sink,
        watchdogInterval,
        foreground,
      );
    });

    tearDown(() {
      watcher.dispose();
      foreground.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Watching starts on the prompt that opens a turn.
    void startWatching() {
      watcher.observeHookEvent(
        AgentHookEvent(
          terminalSessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          agentType: .codex,
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{
            'turn_id': 'turn-1',
            'transcript_path': transcript.path,
          },
        ),
      );
    }

    /// Append the line that ends the turn, without touching the watcher, so a
    /// scan is the only thing that can observe it.
    void completeTurnOnDisk() {
      transcript.writeAsStringSync(_turnComplete, mode: .append);
    }

    Future<void> waitOutSeveralIntervals() async {
      await Future.pause(watchdogInterval * 8);
    }

    /// Kill the file watch so polling is the only thing left driving scans.
    ///
    /// Deleting the path ends the subscription, which is what the watcher
    /// treats as "file watching is not working here" and falls back on. Without
    /// this the assertions below could not tell a parked timer from an event
    /// the file watch delivered anyway.
    Future<void> forcePollingFallback() async {
      transcript.deleteSync();
      await Future.pause(watchdogInterval * 3);
      transcript.writeAsStringSync(_turnStart);
      await Future.pause(watchdogInterval * 3);
    }

    test('a backgrounded app stops polling the transcript', () async {
      startWatching();
      await forcePollingFallback();
      final before = sink.events.length;

      foreground.setForeground(false);
      completeTurnOnDisk();
      await waitOutSeveralIntervals();

      expect(
        sink.events.length,
        before,
        reason: 'the poll timer kept reading the transcript while hidden',
      );
    });

    test('polling resumes on return and reads what accumulated', () async {
      startWatching();
      await forcePollingFallback();
      foreground.setForeground(false);
      completeTurnOnDisk();
      await waitOutSeveralIntervals();

      foreground.setForeground(true);
      await Future.pause(watchdogInterval * 3);

      expect(sink.events.map((event) => event.hookEventName), contains('Stop'));
    });

    test('returning to the foreground catches up on what was missed', () async {
      startWatching();
      await Future.pause(watchdogInterval * 2);
      foreground.setForeground(false);
      completeTurnOnDisk();
      await waitOutSeveralIntervals();

      foreground.setForeground(true);
      await Future.pause(watchdogInterval * 2);

      // Nothing is lost by parking: the scan resumes from the same byte offset,
      // so the completion written while hidden is read on return.
      expect(sink.events.map((event) => event.hookEventName), contains('Stop'));
    });

    test('a watch disposed while hidden stays disposed', () async {
      // Resuming must not revive a watch whose turn already ended, which is
      // what a stale foreground subscription would do.
      startWatching();
      completeTurnOnDisk();
      await Future.pause(watchdogInterval * 3);
      final afterStop = sink.events.length;

      foreground.setForeground(false);
      foreground.setForeground(true);
      await waitOutSeveralIntervals();

      expect(sink.events.length, afterStop);
    });
  });
}

const _turnStart =
    '{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}\n';
const _turnComplete =
    '{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}\n';

class _FakeAppForeground implements AppForeground {
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  var _isForeground = true;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> get changes => _changes.stream;

  void setForeground(bool value) {
    _isForeground = value;
    _changes.add(value);
  }

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}

class _FakeStatusSink implements AgentStatusSink {
  final List<AgentHookEvent> events = <AgentHookEvent>[];

  @override
  void applyHookEvent(AgentHookEvent event) {
    events.add(event);
  }
}
