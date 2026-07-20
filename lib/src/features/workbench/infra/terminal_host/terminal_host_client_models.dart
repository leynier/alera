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

  /// Takes the viewport back from a mobile driver, restoring the last desktop
  /// dims. Returns whether there was a claim to undo.
  Future<bool> reclaimTerminal(String sessionId);

  /// Current driver per session, for rebuilding overlay state on (re)connect.
  Future<Map<String, TerminalSessionDriver>> listTerminalDrivers();

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

enum TerminalSessionDriverKind { idle, desktop, mobile }

/// Who owns a session's viewport (the mobile presence lock). While a mobile
/// device drives, the desktop pane shows an overlay instead of fighting over
/// the PTY dims.
final class TerminalSessionDriver {
  const TerminalSessionDriver({
    required this.kind,
    this.deviceId,
    this.deviceName,
  });

  static const TerminalSessionDriver idle = TerminalSessionDriver(
    kind: TerminalSessionDriverKind.idle,
  );

  factory TerminalSessionDriver.fromJson(Map<String, Object?> json) {
    return TerminalSessionDriver(
      kind: switch (json['kind']) {
        'mobile' => TerminalSessionDriverKind.mobile,
        'desktop' => TerminalSessionDriverKind.desktop,
        _ => TerminalSessionDriverKind.idle,
      },
      deviceId: json['deviceId'] as String?,
      deviceName: json['deviceName'] as String?,
    );
  }

  factory TerminalSessionDriver.fromPayloadValue(Object? value) {
    return TerminalSessionDriver.fromJson(switch (value) {
      final Map<String, Object?> driver => driver,
      final Map<dynamic, dynamic> driver => Map<String, Object?>.from(driver),
      _ => const <String, Object?>{},
    });
  }

  /// Parses the `terminal.driver.list` response into a session-id keyed map.
  static Map<String, TerminalSessionDriver> mapFromListPayload(
    Object? payload,
  ) {
    if (payload is! List) {
      return const <String, TerminalSessionDriver>{};
    }
    final drivers = <String, TerminalSessionDriver>{};
    for (final item in payload) {
      if (item is! Map) {
        continue;
      }
      final entry = Map<String, Object?>.from(item);
      final sessionId = entry['sessionId'];
      if (sessionId is String) {
        drivers[sessionId] = TerminalSessionDriver.fromPayloadValue(
          entry['driver'],
        );
      }
    }
    return drivers;
  }

  final TerminalSessionDriverKind kind;
  final String? deviceId;
  final String? deviceName;

  bool get isMobile => kind == TerminalSessionDriverKind.mobile;
}

final class TerminalHostDriverChangedEvent extends TerminalHostEvent {
  const TerminalHostDriverChangedEvent(
    super.sessionId,
    this.driver, {
    required this.cols,
    required this.rows,
  });

  factory TerminalHostDriverChangedEvent.fromPayload(
    String sessionId,
    Map<String, Object?> payload,
  ) {
    return TerminalHostDriverChangedEvent(
      sessionId,
      TerminalSessionDriver.fromPayloadValue(payload['driver']),
      cols: (payload['cols'] as num?)?.toInt() ?? 0,
      rows: (payload['rows'] as num?)?.toInt() ?? 0,
    );
  }

  final TerminalSessionDriver driver;
  final int cols;
  final int rows;
}

/// Broadcast event names surfaced on the runtime host event stream.
const Set<String> runtimeHostEventNames = <String>{
  'projectsChanged',
  'workspacesChanged',
  'workspaceTabsChanged',
  'workspaceTagsChanged',
  'workspaceRelationsChanged',
  'runtimeSettingsChanged',
  'agentQuotasChanged',
  'agentSkillInstallProgress',
  'workbenchViewPrefsChanged',
  'workspaceActivityChanged',
  'projectConfigsChanged',
  'linkedReviewsChanged',
  'sshTargetsChanged',
  'sshTargetBootstrapProgress',
  'mobileSettingsChanged',
  'mobilePairingsChanged',
  'mobileDevicesChanged',
  'mobileGatewayChanged',
};
