import 'dart:typed_data';

import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

abstract interface class TerminalHostClient {
  Stream<TerminalHostEvent> get events;

  bool get supportsTerminalRestart;

  bool get supportsDeferredInput;

  /// Events for one PTY session only.
  ///
  /// Every session used to filter the global stream, so one output chunk was
  /// dispatched to every live terminal and discarded by all but one. That is
  /// O(open terminals) per chunk.
  Stream<TerminalHostEvent> eventsForSession(String sessionId);

  /// Drops the per-session stream once nobody is listening to it.
  void releaseSession(String sessionId);

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

  Future<TerminalHostAttachment> restart({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  });

  Future<void> write({
    required String sessionId,
    required List<int> bytes,
    bool deferredEnter = false,
  });

  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  });

  Future<TerminalHostResume> setOutputPaused({
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

abstract interface class TerminalPulseHostClient {
  bool get supportsTerminalPulse;

  Future<TerminalPulseState> terminalPulseStatus(String sessionId);

  Future<TerminalPulseState> configureTerminalPulse({
    required String sessionId,
    required TerminalPulseConfiguration configuration,
    required bool armed,
  });
}

final class TerminalPulseState {
  const TerminalPulseState({
    required this.configuration,
    required this.armed,
    this.statusKnown = true,
    this.error,
  });

  factory TerminalPulseState.fromJson(Map<String, Object?> json) {
    return TerminalPulseState(
      configuration: TerminalPulseConfiguration.fromJson(json['configuration']),
      armed: json['armed'] == true,
      statusKnown: json['armed'] is bool,
      error: json['error'] as String?,
    );
  }

  final TerminalPulseConfiguration configuration;
  final bool armed;
  final bool statusKnown;
  final String? error;
}

final class TerminalHostRequestTimeoutException implements Exception {
  const TerminalHostRequestTimeoutException(this.requestType, this.duration);

  final String requestType;
  final Duration duration;

  @override
  String toString() {
    return 'Terminal host request "$requestType" timed out after '
        '${duration.inMilliseconds} ms.';
  }
}

final class TerminalHostConnectionClosedException implements Exception {
  const TerminalHostConnectionClosedException([this.reason]);

  final Object? reason;

  @override
  String toString() {
    final reason = this.reason?.toString();
    if (reason == null || reason.isEmpty) {
      return 'Terminal host connection closed.';
    }
    return 'Terminal host connection closed: $reason';
  }
}

final class TerminalHostStartupException implements Exception {
  const TerminalHostStartupException(this.cause);

  final Object? cause;

  @override
  String toString() => 'Terminal host did not start in time.';
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

/// How the host answered a resume.
///
/// A delta resume carries no bytes here: the host pushes what the client
/// missed on the output lane instead, so it stays ordered against live output
/// and goes through the same per-session decoder. Only a client the host can
/// no longer place in the stream gets [snapshot], which replaces the emulator.
final class TerminalHostResume {
  const TerminalHostResume({
    required this.isDelta,
    required this.snapshot,
    this.resetInteractionModes = false,
  });

  factory TerminalHostResume.fromJson(Map<String, Object?> json) {
    return TerminalHostResume(
      // A host that predates delta resumes answers with the whole scrollback
      // and no `delta` field, so an absent flag has to mean "replace".
      isDelta: json['delta'] == true,
      snapshot: decodeTerminalHostBytes(json['snapshotBase64']),
      resetInteractionModes: json['resetInteractionModes'] == true,
    );
  }

  final bool isDelta;
  final Uint8List snapshot;
  final bool resetInteractionModes;
}

sealed class TerminalHostEvent {
  const TerminalHostEvent(this.sessionId);

  final String sessionId;
}

final class TerminalHostOutputEvent extends TerminalHostEvent {
  const TerminalHostOutputEvent(super.sessionId, this.data);

  final Uint8List data;
}

/// Output that the socket reader isolate already decoded.
///
/// The isolate holds one decoder per session, so a code point split across
/// chunks is reassembled there rather than on the UI isolate.
final class TerminalHostOutputTextEvent extends TerminalHostEvent {
  const TerminalHostOutputTextEvent(super.sessionId, this.text);

  final String text;
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

final class TerminalHostPulseChangedEvent extends TerminalHostEvent {
  const TerminalHostPulseChangedEvent(super.sessionId, this.state);

  final TerminalPulseState state;
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
  'agentPresenceChanged',
  'codexThreadChanged',
  'codexServerChanged',
  'agentCanvasChanged',
};
