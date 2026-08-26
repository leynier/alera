import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

final class FakeTerminalHostClient
    implements TerminalHostClient, TerminalPulseHostClient {
  FakeTerminalHostClient({
    required TerminalHostAttachment attachment,
    List<TerminalHostAttachment>? attachments,
    this.attachCompleter,
    this.pulseEnabled = false,
  }) : _attachments = attachments ?? <TerminalHostAttachment>[attachment];

  final List<TerminalHostAttachment> _attachments;
  final Completer<void>? attachCompleter;
  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final List<
    ({
      String sessionId,
      String workspaceId,
      String tabId,
      String workingDirectory,
      int cols,
      int rows,
    })
  >
  attachCalls =
      <
        ({
          String sessionId,
          String workspaceId,
          String tabId,
          String workingDirectory,
          int cols,
          int rows,
        })
      >[];
  final List<List<int>> writes = <List<int>>[];
  final List<bool> deferredEnterFlags = <bool>[];
  final List<(String, int, int)> resizes = <(String, int, int)>[];
  final List<(String, bool)> outputPaused = <(String, bool)>[];
  final List<String> detached = <String>[];
  final List<String> terminated = <String>[];
  final List<String> restarted = <String>[];
  final List<String> reclaimed = <String>[];
  Map<String, TerminalSessionDriver> drivers =
      <String, TerminalSessionDriver>{};
  final List<Object> writeErrors = <Object>[];
  final List<Object> resizeErrors = <Object>[];
  final List<Object> outputPausedErrors = <Object>[];
  final List<Object> pulseStatusErrors = <Object>[];
  final List<Object> pulseConfigurationErrors = <Object>[];
  final List<TerminalPulseConfiguration> pulseConfigurations =
      <TerminalPulseConfiguration>[];
  String? attachedWorkingDirectory;
  Object? writeError;
  final bool pulseEnabled;
  Completer<void>? reattachCompleter;
  TerminalPulseState pulseState = const TerminalPulseState(
    configuration: TerminalPulseConfiguration(),
    armed: false,
  );

  /// What `setOutputPaused(false)` answers with. A host that can still place
  /// the client in the output stream answers with a delta and pushes the
  /// missed bytes on the output lane, so the default carries no snapshot.
  TerminalHostResume? resume;

  @override
  Stream<TerminalHostEvent> get events => _events.stream;

  @override
  bool get supportsTerminalRestart => true;

  @override
  bool get supportsDeferredInput => true;

  @override
  Stream<TerminalHostEvent> eventsForSession(String sessionId) {
    return _events.stream.where((event) => event.sessionId == sessionId);
  }

  @override
  void releaseSession(String sessionId) {}

  @override
  Future<void> configure(TerminalHostConfig config) async {}

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {}

  @override
  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    attachCalls.add((
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      workingDirectory: workingDirectory,
      cols: cols,
      rows: rows,
    ));
    attachedWorkingDirectory = workingDirectory;
    final gate = attachCalls.length == 1 ? attachCompleter : reattachCompleter;
    if (gate case final completer?) {
      await completer.future;
    }
    final index = attachCalls.length - 1;
    return _attachments[index < _attachments.length
        ? index
        : _attachments.length - 1];
  }

  @override
  Future<TerminalHostAttachment> restart({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    restarted.add(sessionId);
    return _attachments.last;
  }

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
    bool deferredEnter = false,
  }) async {
    if (writeErrors.isNotEmpty) {
      throw writeErrors.removeAt(0);
    }
    if (writeError case final error?) {
      throw error;
    }
    writes.add(List<int>.from(bytes));
    deferredEnterFlags.add(deferredEnter);
  }

  @override
  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  }) async {
    if (resizeErrors.isNotEmpty) {
      throw resizeErrors.removeAt(0);
    }
    resizes.add((sessionId, cols, rows));
  }

  @override
  Future<TerminalHostResume> setOutputPaused({
    required String sessionId,
    required bool paused,
  }) async {
    if (outputPausedErrors.isNotEmpty) {
      throw outputPausedErrors.removeAt(0);
    }
    outputPaused.add((sessionId, paused));
    return resume ?? TerminalHostResume(isDelta: true, snapshot: Uint8List(0));
  }

  @override
  bool get supportsTerminalPulse => pulseEnabled;

  @override
  Future<TerminalPulseState> terminalPulseStatus(String sessionId) async {
    if (pulseStatusErrors.isNotEmpty) {
      throw pulseStatusErrors.removeAt(0);
    }
    return pulseState;
  }

  @override
  Future<TerminalPulseState> configureTerminalPulse({
    required String sessionId,
    required TerminalPulseConfiguration configuration,
    required bool armed,
  }) async {
    if (pulseConfigurationErrors.isNotEmpty) {
      throw pulseConfigurationErrors.removeAt(0);
    }
    pulseConfigurations.add(configuration);
    pulseState = TerminalPulseState(configuration: configuration, armed: armed);
    return pulseState;
  }

  @override
  Future<void> detach(String sessionId) async {
    detached.add(sessionId);
  }

  @override
  Future<void> terminate(String sessionId) async {
    terminated.add(sessionId);
  }

  @override
  Future<bool> reclaimTerminal(String sessionId) async {
    reclaimed.add(sessionId);
    return true;
  }

  @override
  Future<Map<String, TerminalSessionDriver>> listTerminalDrivers() async {
    return drivers;
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }

  void emit(TerminalHostEvent event) {
    _events.add(event);
  }
}
