import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

final class FakeTerminalHostClient implements TerminalHostClient {
  FakeTerminalHostClient({
    required TerminalHostAttachment attachment,
    List<TerminalHostAttachment>? attachments,
  }) : _attachments = attachments ?? <TerminalHostAttachment>[attachment];

  final List<TerminalHostAttachment> _attachments;
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
  final List<(String, int, int)> resizes = <(String, int, int)>[];
  final List<String> detached = <String>[];
  final List<String> terminated = <String>[];
  final List<Object> writeErrors = <Object>[];
  final List<Object> resizeErrors = <Object>[];
  String? attachedWorkingDirectory;
  Object? writeError;

  @override
  Stream<TerminalHostEvent> get events => _events.stream;

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
    final index = attachCalls.length - 1;
    return _attachments[index < _attachments.length
        ? index
        : _attachments.length - 1];
  }

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
  }) async {
    if (writeErrors.isNotEmpty) {
      throw writeErrors.removeAt(0);
    }
    if (writeError case final error?) {
      throw error;
    }
    writes.add(List<int>.from(bytes));
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
  Future<void> detach(String sessionId) async {
    detached.add(sessionId);
  }

  @override
  Future<void> terminate(String sessionId) async {
    terminated.add(sessionId);
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }

  void emit(TerminalHostEvent event) {
    _events.add(event);
  }
}
