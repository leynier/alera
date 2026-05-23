import 'dart:async';
import 'dart:convert';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_framer.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

class JsonRpcServerRequest {
  const JsonRpcServerRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final Object id;
  final String method;
  final Map<String, dynamic> params;
}

class JsonRpcClient {
  JsonRpcClient({
    required this._processRunner,
    required this._executable,
    required this._arguments,
    this._workingDirectory,
    this._environment,
  });

  final ProcessRunner _processRunner;
  final String _executable;
  final List<String> _arguments;
  final String? _workingDirectory;
  final Map<String, String>? _environment;

  final JsonRpcFramer _framer = JsonRpcFramer();
  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<JsonRpcServerRequest> _incomingRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();

  final Map<Object, Completer<Map<String, dynamic>>> _pendingRequests =
      <Object, Completer<Map<String, dynamic>>>{};

  StartedProcess? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  var _requestCounter = 0;
  var _closed = false;

  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;
  Stream<JsonRpcServerRequest> get incomingRequests =>
      _incomingRequestsController.stream;

  Future<void> start() async {
    if (_process != null) {
      return;
    }

    _process = await _processRunner.start(
      _executable,
      _arguments,
      workingDirectory: _workingDirectory,
      environment: _environment,
    );

    _stdoutSub = _process!.stdout.listen(_onStdoutChunk, onError: _onIoError);
    _stderrSub = _process!.stderr.listen((data) {
      if (_closed || _notificationsController.isClosed) {
        return;
      }
      _notificationsController.add(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'alera.stderr',
        'params': <String, dynamic>{
          'data': utf8.decode(data, allowMalformed: true),
        },
      });
    }, onError: _onIoError);

    unawaited(
      _process!.exitCode.then((code) {
        if (_closed) {
          return;
        }
        final error = StateError('JSON-RPC process exited with code $code');
        for (final completer in _pendingRequests.values) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
        _pendingRequests.clear();
        _notificationsController.addError(error);
      }),
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

  /// Emits a synthetic notification on the [notifications] stream without
  /// touching the underlying process. Used for client-side diagnostics
  /// (mirrors the internal `alera.stderr` forwarding pattern).
  void emitSyntheticNotification(
    String method, {
    Map<String, dynamic>? params,
  }) {
    if (_notificationsController.isClosed) {
      return;
    }
    _notificationsController.add(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? <String, dynamic>{},
    });
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

    final stdoutSub = _stdoutSub;
    final stderrSub = _stderrSub;
    _stdoutSub = null;
    _stderrSub = null;
    _process?.kill();

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('JSON-RPC client closed'));
      }
    }
    _pendingRequests.clear();

    // close() can be called while a stdout callback is settling a failed
    // request; awaiting that same subscription cancel can deadlock cleanup.
    unawaited(stdoutSub?.cancel());
    unawaited(stderrSub?.cancel());
    await _notificationsController.close();
    await _incomingRequestsController.close();
  }

  void _onStdoutChunk(List<int> chunk) {
    if (_closed) {
      return;
    }
    try {
      final messages = _framer.addChunk(chunk);
      for (final message in messages) {
        _dispatchMessage(message);
      }
    } catch (error, stackTrace) {
      if (!_notificationsController.isClosed) {
        _notificationsController.addError(error, stackTrace);
      }
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
    _process!.stdinWrite(utf8.encode('$json\n'));
  }

  void _onIoError(Object error, StackTrace stackTrace) {
    if (!_notificationsController.isClosed) {
      _notificationsController.addError(error, stackTrace);
    }
  }

  void _ensureOpen() {
    if (_process == null) {
      throw StateError('JSON-RPC client not started');
    }
    if (_closed) {
      throw StateError('JSON-RPC client already closed');
    }
  }
}
