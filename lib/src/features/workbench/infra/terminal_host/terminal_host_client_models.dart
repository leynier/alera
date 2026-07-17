import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

abstract interface class TerminalHostClient {
  Stream<TerminalHostEvent> get events;

  Future<void> ensureStarted({required TerminalHostConfig config});

  Future<void> configure(TerminalHostConfig config);

  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  });

  Future<void> write({required String sessionId, required List<int> bytes});

  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  });

  Future<Uint8List> setOutputPaused({
    required String sessionId,
    required bool paused,
  });

  Future<void> detach(String sessionId);

  Future<void> terminate(String sessionId);

  void dispose();
}

final class TerminalHostRequestTimeoutException implements Exception {
  const TerminalHostRequestTimeoutException(this.requestType, this.duration);

  final String requestType;
  final Duration duration;

  @override
  String toString() {
    return 'Terminal host request "$requestType" timed out after '
        '${duration.inMilliseconds} ms. The connection was closed.';
  }
}

final class TerminalHostAttachment {
  const TerminalHostAttachment({
    required this.sessionId,
    required this.created,
    required this.running,
    required this.snapshot,
    this.exitCode,
  });

  factory TerminalHostAttachment.fromJson(Map<String, Object?> json) {
    return TerminalHostAttachment(
      sessionId: json['sessionId'] as String,
      created: json['created'] == true,
      running: json['running'] == true,
      snapshot: decodeTerminalHostBytes(json['snapshotBase64']),
      exitCode: json['exitCode'] is int ? json['exitCode'] as int : null,
    );
  }

  final String sessionId;
  final bool created;
  final bool running;
  final Uint8List snapshot;
  final int? exitCode;
}

final class TerminalHostSnapshot {
  const TerminalHostSnapshot({required this.data});

  factory TerminalHostSnapshot.fromJson(Map<String, Object?> json) {
    return TerminalHostSnapshot(
      data: decodeTerminalHostBytes(json['snapshotBase64']),
    );
  }

  final Uint8List data;
}

sealed class TerminalHostEvent {
  const TerminalHostEvent(this.sessionId);

  final String sessionId;
}

final class TerminalHostOutputEvent extends TerminalHostEvent {
  const TerminalHostOutputEvent(super.sessionId, this.data);

  final Uint8List data;
}

final class TerminalHostOutputResyncRequiredEvent extends TerminalHostEvent {
  const TerminalHostOutputResyncRequiredEvent(super.sessionId);
}

final class TerminalHostExitEvent extends TerminalHostEvent {
  const TerminalHostExitEvent(super.sessionId, this.exitCode);

  final int exitCode;
}

final class TerminalHostErrorEvent extends TerminalHostEvent {
  const TerminalHostErrorEvent(super.sessionId, this.error);

  final Object error;
}
