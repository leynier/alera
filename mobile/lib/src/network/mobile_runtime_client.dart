import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models.dart';

const Duration _defaultRequestTimeout = Duration(seconds: 20);

class MobileRuntimeEvent {
  const MobileRuntimeEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

class MobileTerminalOutputEvent {
  const MobileTerminalOutputEvent(this.sessionId, this.data);

  final String sessionId;
  final Uint8List data;
}

abstract interface class MobileTerminalClient {
  Stream<MobileTerminalOutputEvent> get terminalOutput;
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId);
  Future<MobileTerminalSession> createTerminal(String workspaceId);
  Future<MobileTerminalSession> attachTerminal(String tabId);
  Future<void> writeTerminal(String sessionId, List<int> bytes);
  Future<void> detachTerminal(String sessionId);
}

class MobileRuntimeClient implements MobileTerminalClient {
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

  Stream<MobileRuntimeEvent> get events => _events.stream;
  @override
  Stream<MobileTerminalOutputEvent> get terminalOutput =>
      _terminalOutput.stream;
  int get debugPendingRequestCount => _pending.length;

  Future<Map<String, Object?>> authenticate({
    required String deviceId,
    required String deviceToken,
  }) {
    return requestMap('mobile.hello', <String, Object?>{
      'protocolVersion': aleraMobileProtocolVersion,
      'deviceId': deviceId,
      'deviceToken': deviceToken,
    });
  }

  Future<MobileRuntimeStatus> mobileStatus() async {
    final payload = await requestMap('mobile.status.get');
    return MobileRuntimeStatus.fromJson(payload);
  }

  Future<List<ProjectSummary>> listProjects() async {
    final payload = await requestList('project.list');
    return <ProjectSummary>[
      for (final item in payload)
        if (_asMap(item).isNotEmpty) ProjectSummary.fromJson(_asMap(item)),
    ];
  }

  Future<ProjectBranches> listBranches(String projectId) async {
    final payload = await requestMap('project.branches.list', <String, Object?>{
      'projectId': projectId,
    });
    return ProjectBranches.fromJson(payload);
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final payload = await requestList('workspace.listAll');
    return <WorkspaceSummary>[
      for (final item in payload)
        if (_asMap(item).isNotEmpty) WorkspaceSummary.fromJson(_asMap(item)),
    ];
  }

  @override
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId) async {
    final payload = await requestList('tab.list', <String, Object?>{
      'workspaceId': workspaceId,
    });
    return <WorkspaceTabSummary>[
      for (final item in payload)
        if (_asMap(item).isNotEmpty) WorkspaceTabSummary.fromJson(_asMap(item)),
    ];
  }

  @override
  Future<MobileTerminalSession> createTerminal(String workspaceId) async {
    final payload = await requestMap('terminal.create', <String, Object?>{
      'workspaceId': workspaceId,
      'title': 'Mobile Terminal',
      'cols': 80,
      'rows': 24,
    });
    return MobileTerminalSession.fromJson(payload);
  }

  @override
  Future<MobileTerminalSession> attachTerminal(String tabId) async {
    final payload = await requestMap('terminal.attach', <String, Object?>{
      'tabId': tabId,
      'cols': 80,
      'rows': 24,
    });
    return MobileTerminalSession.fromJson(payload);
  }

  @override
  Future<void> writeTerminal(String sessionId, List<int> bytes) async {
    if (bytes.isEmpty) {
      return;
    }
    await request('write', <String, Object?>{
      'sessionId': sessionId,
      'dataBase64': base64Encode(bytes),
    });
  }

  @override
  Future<void> detachTerminal(String sessionId) async {
    await request('detach', <String, Object?>{'sessionId': sessionId});
  }

  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
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
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException(
          'Mobile Runtime Request Timed Out.',
          _requestTimeout,
        );
      },
    );
  }

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final value = await request(type, payload);
    return _asMap(value);
  }

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
    final decoded = switch (raw) {
      String text => jsonDecode(text),
      List<int> bytes => jsonDecode(utf8.decode(bytes)),
      _ => null,
    };
    final message = _asMap(decoded);
    final event = message['event'];
    if (event is String) {
      final payload = _asMap(message['payload']);
      if (!_events.isClosed) {
        _events.add(MobileRuntimeEvent(event, payload));
      }
      if (event == 'output') {
        final sessionId = payload['sessionId'];
        final encoded = payload['dataBase64'];
        if (sessionId is String && encoded is String && encoded.isNotEmpty) {
          _terminalOutput.add(
            MobileTerminalOutputEvent(sessionId, base64Decode(encoded)),
          );
        }
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
  }

  void _handleSocketClosed() {
    _handleSocketError(StateError('Mobile Runtime Connection Closed.'));
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}
