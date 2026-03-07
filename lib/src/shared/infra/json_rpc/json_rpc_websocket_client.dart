import 'dart:async';
import 'dart:convert';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A JSON-RPC client that communicates over a WebSocket connection.
///
/// This class mirrors the public interface of [JsonRpcClient] but uses a
/// [WebSocketChannel] instead of process stdio pipes.
class JsonRpcWebSocketClient {
  JsonRpcWebSocketClient(this._uri);

  final Uri _uri;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<JsonRpcServerRequest> _incomingRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();

  final Map<Object, Completer<Map<String, dynamic>>> _pendingRequests =
      <Object, Completer<Map<String, dynamic>>>{};

  var _requestCounter = 0;
  var _closed = false;

  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;
  Stream<JsonRpcServerRequest> get incomingRequests =>
      _incomingRequestsController.stream;

  /// Connects to the WebSocket server at the URI provided in the constructor.
  Future<void> connect() async {
    if (_channel != null) {
      return;
    }

    _channel = WebSocketChannel.connect(_uri);
    await _channel!.ready;

    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
  }

  Future<Map<String, dynamic>> request(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    _ensureOpen();

    final id = ++_requestCounter;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params ?? <String, dynamic>{},
    };

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;
    _write(payload);

    return completer.future;
  }

  Future<void> notify(String method, {Map<String, dynamic>? params}) async {
    _ensureOpen();

    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? <String, dynamic>{},
    };

    _write(payload);
  }

  Future<void> respondSuccess(Object id, {Map<String, dynamic>? result}) async {
    _ensureOpen();
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result ?? <String, dynamic>{},
    };
    _write(payload);
  }

  Future<void> respondError({
    required Object id,
    required int code,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    _ensureOpen();
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, dynamic>{
        'code': code,
        'message': message,
        ...?data == null ? null : <String, dynamic>{'data': data},
      },
    };
    _write(payload);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    await _subscription?.cancel();
    await _channel?.sink.close();

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('JSON-RPC WebSocket client closed'));
      }
    }
    _pendingRequests.clear();

    await _notificationsController.close();
    await _incomingRequestsController.close();
  }

  void _onMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      _dispatchMessage(message);
    } catch (error, stackTrace) {
      _notificationsController.addError(error, stackTrace);
    }
  }

  void _dispatchMessage(Map<String, dynamic> message) {
    final method = message['method'];
    final responseId = message['id'];
    if ((responseId is int || responseId is String) &&
        _pendingRequests.containsKey(responseId)) {
      final completer = _pendingRequests.remove(responseId)!;
      final rpcError = message['error'];
      if (rpcError is Map<String, dynamic>) {
        completer.completeError(StateError(jsonEncode(rpcError)));
      } else {
        completer.complete(message);
      }
      return;
    }

    if ((responseId is int || responseId is String) && method is String) {
      final params = message['params'];
      _incomingRequestsController.add(
        JsonRpcServerRequest(
          id: responseId,
          method: method,
          params: params is Map<String, dynamic>
              ? params
              : const <String, dynamic>{},
        ),
      );
      return;
    }

    _notificationsController.add(message);
  }

  void _write(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    _channel!.sink.add(json);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_closed && !_notificationsController.isClosed) {
      _notificationsController.addError(error, stackTrace);
    }
  }

  void _onDone() {
    if (_closed) {
      return;
    }
    final error = StateError('WebSocket connection closed unexpectedly');
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingRequests.clear();
    if (!_notificationsController.isClosed) {
      _notificationsController.addError(error);
    }
  }

  void _ensureOpen() {
    if (_channel == null) {
      throw StateError('JSON-RPC WebSocket client not connected');
    }
    if (_closed) {
      throw StateError('JSON-RPC WebSocket client already closed');
    }
  }
}
