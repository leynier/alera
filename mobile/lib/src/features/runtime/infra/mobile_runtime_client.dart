import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:alera_mobile/src/features/runtime/domain/connection_attempt.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_binary_output_payload.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_wire.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_restart_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_capabilities.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_sidebar_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_project_client.dart';
import 'package:alera_mobile/src/core/logging/log_redaction.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

export 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

part 'mobile_runtime_client_host_tools.dart';
part 'mobile_runtime_client_lifecycle.dart';
part 'mobile_runtime_client_relay.dart';
part 'mobile_runtime_transport_connection.dart';
part 'mobile_runtime_relay_authorization.dart';
part 'mobile_runtime_dictation_requests.dart';
part 'mobile_runtime_terminal_requests.dart';
part 'mobile_terminal_output_resync.dart';
part 'mobile_runtime_codex_workspace_requests.dart';

class MobileRuntimeClient._(
  this._channel, {
  this._requestTimeout = _defaultRequestTimeout,
  final Duration _transportCloseTimeout = _defaultTransportCloseTimeout,
}) with
        MobileRuntimeWorkspaceSidebarClient,
        MobileRuntimeWorkspaceClient,
        MobileRuntimeProjectClient,
        MobileRuntimeClientHostTools,
        MobileRuntimeClientRelay,
        MobileRuntimeDictationRequests,
        MobileRuntimeTerminalRequests,
        MobileRuntimeTerminalOutputResync,
        MobileRuntimeCodexWorkspaceRequests
    implements
        MobileTerminalClient,
        MobileWorkspaceClient,
        MobileAgentTitleClient,
        MobileCodexWorkspaceClient {
  this {
    _subscription = _channel.stream.listen(
      _handleMessage,
      onError: _handleSocketError,
      onDone: _handleSocketClosed,
    );
  }

  new forTesting(
    WebSocketChannel channel, {
    Duration requestTimeout = _defaultRequestTimeout,
    Duration transportCloseTimeout = _defaultTransportCloseTimeout,
  }) : this._(
         channel,
         requestTimeout: requestTimeout,
         transportCloseTimeout: transportCloseTimeout,
       );

  static Future<MobileRuntimeClient> connect(
    String endpoint, {
    Duration connectTimeout = _defaultRequestTimeout,
  }) => _connectDirectTransport(endpoint, connectTimeout: connectTimeout);

  static Future<MobileRuntimeClient> connectRelay({
    required CloudRelayGrant grant,
    required RelayIdentityKeyPair identity,
    Future<CloudRelayGrant> Function()? requestGrant,
  }) => _connectRelayTransport(
    grant: grant,
    identity: identity,
    requestGrant: requestGrant,
  );

  static Future<PairedDeviceCredentials> pairDevice(
    PairingOffer offer, {
    String? deviceName,
  }) => _pairDirectDevice(offer, deviceName: deviceName);

  @override
  final WebSocketChannel _channel;
  @override
  final Duration _requestTimeout;

  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final StreamController<MobileTerminalOutputEvent> _terminalOutput =
      StreamController<MobileTerminalOutputEvent>.broadcast();
  final StreamController<(Object, StackTrace?)> _connectionFailures =
      StreamController<(Object, StackTrace?)>.broadcast(sync: true);

  late final StreamSubscription<Object?> _subscription;
  int _nextRequestId = 1;
  bool _disposed = false;
  DateTime? lastActivityAt;
  Object? _closedError;
  StackTrace? _closedStackTrace;
  Set<String> _runtimeCapabilities = const <String>{};
  bool _binaryFrames = false;
  CloudRelayGrant? _relayGrant;
  Future<CloudRelayGrant> Function()? _requestRelayGrant;
  Timer? _relayRenewalTimer;
  Timer? _relayExpiryTimer;
  ConnectionAttempt? _renewalAttempt;
  Completer<Map<String, Object?>>? _relayAuthorizationReply;
  int _relayAuthorizationId = 0;
  String get transport => _relaySession == null ? 'direct' : 'relay';
  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;
  @override
  Stream<MobileTerminalOutputEvent> get terminalOutput =>
      _terminalOutput.stream;
  Stream<(Object, StackTrace?)> get connectionFailures =>
      _connectionFailures.stream;
  int get debugPendingRequestCount => _pending.length;

  @override
  bool get isConnectionUsable => !_disposed && _closedError == null;

  /// The single door onto the terminal output stream, so neither the binary nor
  /// the base64 path can add to a closed controller.
  @override
  void emitTerminalOutput(MobileTerminalOutputEvent event) {
    if (_terminalOutput.isClosed) {
      return;
    }
    _terminalOutput.add(event);
  }

  /// Capabilities advertised by the runtime in the `mobile.hello` response.
  /// Empty until [authenticate] completes.
  @override
  Set<String> get runtimeCapabilities => _runtimeCapabilities;

  @override
  bool get supportsTabRename =>
      _runtimeCapabilities.contains(mobileTabRenameCapability);
  @override
  bool get supportsTerminalTitles =>
      _runtimeCapabilities.contains(mobileTerminalTitlesCapability);
  @override
  bool get supportsDeferredTerminalInput =>
      _runtimeCapabilities.contains(terminalDeferredInputCapability);
  @override
  bool get supportsTerminalRestart =>
      _runtimeCapabilities.contains(terminalRestartCapability);
  bool get supportsRuntimeRestart =>
      _runtimeCapabilities.contains(runtimeHostRestartCapability);
  bool get supportsPortableSettings =>
      _runtimeCapabilities.contains(mobilePortableSettingsCapability);
  bool get supportsAgentQuotas =>
      _runtimeCapabilities.contains(mobileAgentQuotaCapability);
  bool get supportsAgentQuotaClaudeTui =>
      _runtimeCapabilities.contains(mobileAgentQuotaClaudeTuiCapability);
  bool get supportsCodexResetCredits =>
      _runtimeCapabilities.contains(codexResetCreditsCapability);
  bool get supportsHostTools =>
      _runtimeCapabilities.contains(mobileHostToolsCapability);
  bool get supportsCloudEnrollment =>
      _runtimeCapabilities.contains(mobileCloudEnrollmentCapability);
  @override
  bool get supportsPromptImageUpload =>
      _runtimeCapabilities.contains(mobilePromptImageUploadCapability);

  bool get supportsAutomations =>
      _runtimeCapabilities.contains(automationsCapability);
  Future<Map<String, Object?>> authenticate({
    required String deviceId,
    required String deviceToken,
    String? cloudDeviceId,
  }) async {
    // Masked in logs and crash reports from here on: the token authenticates
    // this phone to the runtime, and exported logs are meant to be shareable.
    registerLogSecret(deviceToken);
    final payload = await requestMap('mobile.hello', <String, Object?>{
      'protocolVersion': aleraMobileProtocolVersion,
      'deviceId': deviceId,
      'deviceToken': deviceToken,
      'cloudDeviceId': ?cloudDeviceId,
      'binaryFrames': true,
      'supportedTabKinds': const <String>[],
    });
    _runtimeCapabilities = payload.stringList('runtimeCapabilities').toSet();
    // The response decides, not the request: an older runtime simply omits it
    // and keeps sending base64 inside JSON.
    _binaryFrames = payload['binaryFrames'] == true;
    unawaited(_refreshCrashReportingRuntimeContext());
    return payload;
  }

  Future<String> createCloudEnrollment() async {
    if (!supportsCloudEnrollment) {
      throw StateError('This host does not support account enrollment');
    }
    final payload = await requestMap('mobile.cloudEnrollment.create');
    return payload.requiredString('code');
  }

  Future<int> refreshCloudSubscriptions() async {
    if (!supportsCloudEnrollment) {
      throw StateError('This host does not support cloud subscriptions');
    }
    final payload = await requestMap('mobile.cloudSubscriptions.refresh');
    return payload.requiredInt('activeSubscriptions');
  }

  Future<MobileRuntimeStatus> mobileStatus() async {
    final payload = await requestMap(
      'mobile.status.get',
      const <String, Object?>{'includeNetworkStatus': false},
    );
    return MobileRuntimeStatus.fromJson(payload);
  }

  Future<RuntimeRestartResult> restartRuntime({bool force = false}) async {
    if (!supportsRuntimeRestart) {
      throw UnsupportedError('Update the runtime to restart it remotely.');
    }
    try {
      final payload = await requestMap('host.restart', <String, Object?>{
        'force': force,
      });
      return RuntimeRestartResult.fromJson(payload);
    } on StateError catch (error) {
      final busy = RuntimeRestartBusyException.tryParse(error);
      if (busy != null) {
        throw busy;
      }
      rethrow;
    }
  }

  @override
  Future<WorkspaceTabSummary> renameTab(String tabId, String title) async {
    final payload = await requestMap('tab.rename', <String, Object?>{
      'id': tabId,
      'title': title,
    });
    return WorkspaceTabSummary.fromJson(payload);
  }

  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    if (_disposed) {
      throw StateError('Mobile runtime client is disposed.');
    }
    final closedError = _closedError;
    if (closedError != null) {
      return Future<Object?>.error(closedError, _closedStackTrace);
    }
    final id = _nextRequestId++;
    if (_pending.length >= 256) {
      return Future.error(StateError('Too many pending runtime requests.'));
    }
    final completer = Completer<Object?>();
    _pending[id] = completer;
    final encoded = jsonEncode(<String, Object?>{
      'id': id,
      'type': type,
      'payload': payload,
    });
    unawaited(
      _sendTransport(encoded).catchError((error, stackTrace) {
        _handleSocketError(error, stackTrace);
      }),
    );
    final effectiveTimeout = timeout ?? _requestTimeout;
    return completer.future.timeout(
      effectiveTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException(
          'Mobile runtime request timed out.',
          effectiveTimeout,
        );
      },
    );
  }

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    final value = await request(type, payload, timeout);
    return asJsonMap(value);
  }

  @override
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final value = await request(type, payload);
    if (value is List<Object?>) {
      return value;
    }
    if (value is List) {
      return List<Object?>.from(value);
    }
    return const <Object?>[];
  }

  void _handleMessage(Object? raw) {
    if (!isConnectionUsable) return;
    lastActivityAt = DateTime.now().toUtc();
    if (_handleRelayControl(raw)) return;
    if (_relayHandshake != null) {
      unawaited(_handleRelayHandshakeMessage(raw));
      return;
    }
    if (_relaySession != null) {
      unawaited(_handleRelayMessage(raw));
      return;
    }
    _handleDecodedMessage(raw);
  }

  Future<void> _sendTransport(String encoded) async {
    final session = _relaySession;
    if (session == null) {
      _channel.sink.add(encoded);
      return;
    }
    final payload = await session.seal(utf8.encode(encoded));
    if (!isConnectionUsable) return;
    for (final fragment in fragmentRelayPayload(payload)) {
      _channel.sink.add(wrapRelayFrame(_relayClientId!, fragment));
    }
  }

  @override
  void _applyRelayCapabilities(Map<String, Object?> payload) {
    _runtimeCapabilities = payload.stringList('runtimeCapabilities').toSet();
    _binaryFrames = payload['binaryFrames'] == true;
    _startRelayRenewal();
  }

  @override
  void _handleDecodedMessage(Object? raw) {
    if (!isConnectionUsable) return;
    // Relay control responses are decrypted into bytes even though direct
    // WebSockets normally carry them as text. Recognize JSON first because a
    // large JSON object can otherwise look like a valid binary output frame.
    if (_binaryFrames && raw is List<int> && !looksLikeJsonBytes(raw)) {
      final output = decodeMobileBinaryOutput(raw);
      if (output != null) {
        emitTerminalOutput(output);
      }
      return;
    }
    final decoded = switch (raw) {
      String text => jsonDecode(text),
      List<int> bytes => jsonDecode(utf8.decode(bytes)),
      _ => null,
    };
    final message = asJsonMap(decoded);
    final event = message['event'];
    if (event is String) {
      final payload = asJsonMap(message['payload']);
      if (!_events.isClosed) {
        _events.add(MobileRuntimeEvent(event, payload));
      }
      if (event == 'output') {
        final sessionId = payload['sessionId'];
        final encoded = payload['dataBase64'];
        if (sessionId is String && encoded is String && encoded.isNotEmpty) {
          emitTerminalOutput(
            MobileTerminalOutputEvent(sessionId, base64Decode(encoded)),
          );
        }
      } else if (event == 'outputResyncRequired') {
        handleOutputResyncRequired(payload);
      }
      return;
    }
    final id = message['id'];
    if (id is! int) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (message['ok'] == true) {
      completer.complete(message['payload']);
    } else {
      completer.completeError(
        StateError((message['error'] as String?) ?? 'Mobile runtime error.'),
      );
    }
  }

  @override
  void _handleSocketError(Object error, [StackTrace? stackTrace]) {
    _stopRelayRenewal();
    _relayFragmentTimer?.cancel();
    _relayFragments.clear();
    // The single funnel every transport failure passes through, and the most
    // common thing a user reports about this app.
    final normalized = normalizeHostConnectionError(error);
    final firstFailure = _closedError == null;
    CrashReporting.clearRuntimeContext(this);
    Logger('MobileRuntimeClient').warning(
      'runtime connection failed with ${_pending.length} pending requests',
      error,
      stackTrace,
    );
    _closedError ??= normalized;
    _closedStackTrace ??= stackTrace;
    if (firstFailure && !_connectionFailures.isClosed) {
      _connectionFailures.add((normalized, stackTrace));
    }
    final handshake = _relayHandshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(error, stackTrace);
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(normalized, stackTrace);
      }
    }
    _pending.clear();
    // Both lanes end here so listeners can tell a dead socket from an idle
    // terminal. A half-open connection produces no error of its own, so a
    // client that stays silently open looks exactly like one with nothing to
    // deliver. `close` is idempotent, so `dispose` closing them again is fine.
    unawaited(_events.close());
    unawaited(_terminalOutput.close());
  }
}
