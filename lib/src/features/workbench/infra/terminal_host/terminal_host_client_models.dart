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

final class const TerminalPulseState({
  required final TerminalPulseConfiguration configuration,
  required final bool armed,
  final bool statusKnown = true,
  final String? error,
}) {
  factory fromJson(Map<String, Object?> json) {
    return TerminalPulseState(
      configuration: .fromJson(json['configuration']),
      armed: json['armed'] == true,
      statusKnown: json['armed'] is bool,
      error: json['error'] as String?,
    );
  }
}

final class const TerminalHostRequestTimeoutException(
  final String requestType,
  final Duration duration,
) implements Exception {
  @override
  String toString() {
    return 'Terminal host request "$requestType" timed out after '
        '${duration.inMilliseconds} ms.';
  }
}

final class const TerminalHostConnectionClosedException([final Object? reason])
    implements Exception {
  @override
  String toString() {
    final reason = this.reason?.toString();
    if (reason == null || reason.isEmpty) {
      return 'Terminal host connection closed.';
    }
    return 'Terminal host connection closed: $reason';
  }
}

final class const TerminalHostStartupException(final Object? cause)
    implements Exception {
  @override
  String toString() => 'Terminal host did not start in time.';
}

final class const TerminalHostAttachment({
  required final String sessionId,
  required final bool created,
  required final bool running,
  required final Uint8List snapshot,
  final int? exitCode,
}) {
  factory fromJson(Map<String, Object?> json) {
    return TerminalHostAttachment(
      sessionId: json['sessionId'] as String,
      created: json['created'] == true,
      running: json['running'] == true,
      snapshot: decodeTerminalHostBytes(json['snapshotBase64']),
      exitCode: json['exitCode'] is int ? json['exitCode'] as int : null,
    );
  }
}

/// How the host answered a resume.
///
/// A delta resume carries no bytes here: the host pushes what the client
/// missed on the output lane instead, so it stays ordered against live output
/// and goes through the same per-session decoder. Only a client the host can
/// no longer place in the stream gets [snapshot], which replaces the emulator.
final class const TerminalHostResume({
  required final bool isDelta,
  required final Uint8List snapshot,
  final bool resetInteractionModes = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    return TerminalHostResume(
      // A host that predates delta resumes answers with the whole scrollback
      // and no `delta` field, so an absent flag has to mean "replace".
      isDelta: json['delta'] == true,
      snapshot: decodeTerminalHostBytes(json['snapshotBase64']),
      resetInteractionModes: json['resetInteractionModes'] == true,
    );
  }
}

sealed class const TerminalHostEvent(final String sessionId);

final class const TerminalHostOutputEvent(super.sessionId, final Uint8List data)
    extends TerminalHostEvent;

/// Output that the socket reader isolate already decoded.
///
/// The isolate holds one decoder per session, so a code point split across
/// chunks is reassembled there rather than on the UI isolate.
final class const TerminalHostOutputTextEvent(
  super.sessionId,
  final String text,
) extends TerminalHostEvent;

final class const TerminalHostOutputResyncRequiredEvent(super.sessionId)
    extends TerminalHostEvent;

final class const TerminalHostExitEvent(super.sessionId, final int exitCode)
    extends TerminalHostEvent;

final class const TerminalHostErrorEvent(super.sessionId, final Object error)
    extends TerminalHostEvent;

enum TerminalSessionDriverKind { idle, desktop, mobile }

/// Who owns a session's viewport (the mobile presence lock). While a mobile
/// device drives, the desktop pane shows an overlay instead of fighting over
/// the PTY dims.
final class const TerminalSessionDriver({
  required final TerminalSessionDriverKind kind,
  final String? deviceId,
  final String? deviceName,
}) {
  static const TerminalSessionDriver idle = TerminalSessionDriver(kind: .idle);

  factory fromJson(Map<String, Object?> json) {
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

  factory fromPayloadValue(Object? value) {
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

  bool get isMobile => kind == TerminalSessionDriverKind.mobile;
}

final class const TerminalHostDriverChangedEvent(
  super.sessionId,
  final TerminalSessionDriver driver, {
  required final int cols,
  required final int rows,
}) extends TerminalHostEvent {
  factory fromPayload(String sessionId, Map<String, Object?> payload) {
    return TerminalHostDriverChangedEvent(
      sessionId,
      .fromPayloadValue(payload['driver']),
      cols: (payload['cols'] as num?)?.toInt() ?? 0,
      rows: (payload['rows'] as num?)?.toInt() ?? 0,
    );
  }
}

final class const TerminalHostPulseChangedEvent(
  super.sessionId,
  final TerminalPulseState state,
) extends TerminalHostEvent;

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
  'mobileRelayChanged',
  'mobileGatewayChanged',
  'agentPresenceChanged',
  'codexThreadChanged',
  'codexServerChanged',
};
