import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_binary_output_payload.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_sidebar_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_project_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

export 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

part 'mobile_runtime_client_host_tools.dart';
part 'mobile_runtime_terminal_requests.dart';
part 'mobile_terminal_output_resync.dart';

const Duration _defaultRequestTimeout = Duration(seconds: 20);
// Managed workspace lifecycle mirrors the desktop client timeouts
// (lib/src/features/workbench/infra/runtime_managed_workspace_client.dart).
const Duration _managedWorkspaceCreateTimeout = Duration(minutes: 30);
const Duration _managedWorkspaceRemoveTimeout = Duration(minutes: 10);

class MobileRuntimeClient
    with
        MobileRuntimeWorkspaceSidebarClient,
        MobileRuntimeProjectClient,
        MobileRuntimeClientHostTools,
        MobileRuntimeTerminalRequests,
        MobileRuntimeTerminalOutputResync
    implements MobileTerminalClient, MobileWorkspaceClient {
  MobileRuntimeClient._(
    this._channel, {
    this._requestTimeout = _defaultRequestTimeout,
  }) {
    _subscription = _channel.stream.listen(
      _handleMessage,
      onError: _handleSocketError,
      onDone: _handleSocketClosed,
    );
  }

  MobileRuntimeClient.forTesting(
    WebSocketChannel channel, {
    Duration requestTimeout = _defaultRequestTimeout,
  }) : this._(channel, requestTimeout: requestTimeout);

  static Future<MobileRuntimeClient> connect(String endpoint) async {
    final client = MobileRuntimeClient._(
      WebSocketChannel.connect(Uri.parse(endpoint)),
    );
    try {
      await client._channel.ready.timeout(client._requestTimeout);
      return client;
    } on Object {
      await client.dispose();
      rethrow;
    }
  }

  static Future<PairedDeviceCredentials> pairDevice(
    PairingOffer offer, {
    String? deviceName,
  }) async {
    final client = await MobileRuntimeClient.connect(offer.endpoint);
    try {
      final deviceNameOverride = deviceName?.trim();
      final requestPayload = <String, Object?>{
        'pairingId': offer.pairingId,
        'pairingSecret': offer.pairingSecret,
        if (deviceNameOverride != null && deviceNameOverride.isNotEmpty)
          'deviceName': deviceNameOverride,
      };
      final payload = await client.requestMap(
        'mobile.device.pair',
        requestPayload,
      );
      return PairedDeviceCredentials.fromJson(payload);
    } finally {
      await client.dispose();
    }
  }

  final WebSocketChannel _channel;
  final Duration _requestTimeout;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final StreamController<MobileTerminalOutputEvent> _terminalOutput =
      StreamController<MobileTerminalOutputEvent>.broadcast();

  late final StreamSubscription<Object?> _subscription;
  int _nextRequestId = 1;
  bool _disposed = false;
  Object? _closedError;
  StackTrace? _closedStackTrace;

  Set<String> _runtimeCapabilities = const <String>{};
  bool _binaryFrames = false;

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;
  @override
  Stream<MobileTerminalOutputEvent> get terminalOutput =>
      _terminalOutput.stream;
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
  bool get supportsWorkspaceMutations =>
      _runtimeCapabilities.contains(mobileWorkspaceMutationsCapability);

  @override
  bool get supportsTabRename =>
      _runtimeCapabilities.contains(mobileTabRenameCapability);
  @override
  bool get supportsTerminalTitles =>
      _runtimeCapabilities.contains(mobileTerminalTitlesCapability);
  @override
  bool get supportsDeferredTerminalInput =>
      _runtimeCapabilities.contains(terminalDeferredInputCapability);
  bool get supportsPortableSettings =>
      _runtimeCapabilities.contains(mobilePortableSettingsCapability);
  bool get supportsAgentQuotas =>
      _runtimeCapabilities.contains(mobileAgentQuotaCapability);
  bool get supportsAgentQuotaClaudeTui =>
      _runtimeCapabilities.contains(mobileAgentQuotaClaudeTuiCapability);
  bool get supportsHostTools =>
      _runtimeCapabilities.contains(mobileHostToolsCapability);

  Future<Map<String, Object?>> authenticate({
    required String deviceId,
    required String deviceToken,
  }) async {
    final payload = await requestMap('mobile.hello', <String, Object?>{
      'protocolVersion': aleraMobileProtocolVersion,
      'deviceId': deviceId,
      'deviceToken': deviceToken,
      'binaryFrames': true,
    });
    _runtimeCapabilities = payload.stringList('runtimeCapabilities').toSet();
    // The response decides, not the request: an older runtime simply omits it
    // and keeps sending base64 inside JSON.
    _binaryFrames = payload['binaryFrames'] == true;
    return payload;
  }

  Future<MobileRuntimeStatus> mobileStatus() async {
    final payload = await requestMap('mobile.status.get');
    return MobileRuntimeStatus.fromJson(payload);
  }

  @override
  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    await request('workspace.setPinned', <String, Object?>{
      'id': workspaceId,
      'isPinned': isPinned,
    });
  }

  @override
  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await request('workspaceRelation.link', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  @override
  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await request('workspaceRelation.unlink', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  @override
  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) async {
    final payload =
        await requestMap('workspace.createManaged', <String, Object?>{
          'projectId': projectId,
          'branch': branch,
          'reuseExistingBranch': reuseExistingBranch,
          if (!reuseExistingBranch && sourceBranch != null)
            'sourceBranch': sourceBranch,
          'name': ?name,
          'parentWorkspaceId': ?parentWorkspaceId,
        }, _managedWorkspaceCreateTimeout);
    return WorkspaceCreationResult.fromJson(payload);
  }

  @override
  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    await request('workspace.removeManaged', <String, Object?>{
      'id': workspaceId,
      'deleteBranch': ?deleteBranch,
    }, _managedWorkspaceRemoveTimeout);
  }

  @override
  Future<List<String>> cascadePreview(String workspaceId) async {
    final payload = await requestMap(
      'workspaceCascade.preview',
      <String, Object?>{
        'workspaceIds': <String>[workspaceId],
        'includeDescendants': true,
      },
    );
    return payload.stringList('workspaceIds');
  }

  @override
  Future<void> removeTab(String tabId) async {
    await request('tab.remove', <String, Object?>{'id': tabId});
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
  Future<List<ProjectSummary>> listProjects() async {
    final payload = await requestList('project.list');
    return <ProjectSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          ProjectSummary.fromJson(asJsonMap(item)),
    ];
  }

  @override
  Future<ProjectBranches> listBranches(String projectId) async {
    final payload = await requestMap('project.branches.list', <String, Object?>{
      'projectId': projectId,
    });
    return ProjectBranches.fromJson(payload);
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final payload = await requestList('workspace.listAll');
    return <WorkspaceSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          WorkspaceSummary.fromJson(asJsonMap(item)),
    ];
  }

  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    if (_disposed) {
      throw StateError('Mobile Runtime Client Is Disposed.');
    }
    final closedError = _closedError;
    if (closedError != null) {
      return Future<Object?>.error(closedError, _closedStackTrace);
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      _channel.sink.add(
        jsonEncode(<String, Object?>{
          'id': id,
          'type': type,
          'payload': payload,
        }),
      );
    } on Object catch (error, stackTrace) {
      _pending.remove(id);
      _handleSocketError(error, stackTrace);
      return Future<Object?>.error(error, stackTrace);
    }
    final effectiveTimeout = timeout ?? _requestTimeout;
    return completer.future.timeout(
      effectiveTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException(
          'Mobile Runtime Request Timed Out.',
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

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Mobile Runtime Client Closed.'));
      }
    }
    _pending.clear();
    await _subscription.cancel();
    await _events.close();
    await _terminalOutput.close();
    await _channel.sink.close();
  }

  void _handleMessage(Object? raw) {
    // Once negotiated, a binary message is terminal output and never JSON, so
    // it skips jsonDecode and base64Decode entirely.
    if (_binaryFrames && raw is List<int>) {
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
        StateError((message['error'] as String?) ?? 'Mobile Runtime Error.'),
      );
    }
  }

  void _handleSocketError(Object error, [StackTrace? stackTrace]) {
    _closedError ??= error;
    _closedStackTrace ??= stackTrace;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
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

  void _handleSocketClosed() {
    _handleSocketError(StateError('Mobile Runtime Connection Closed.'));
  }
}
