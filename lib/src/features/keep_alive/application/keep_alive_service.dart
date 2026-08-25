import 'dart:async';

import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:alera/src/features/keep_alive/infra/keep_alive_backend.dart';
import 'package:logging/logging.dart';

class KeepAliveService {
  KeepAliveService({required this.backend, Logger? logger})
    : _logger = logger ?? Logger('KeepAliveService');

  final KeepAliveBackend backend;
  final Logger _logger;
  KeepAliveSnapshot _snapshot = const KeepAliveSnapshot.inactive();
  Future<void> _operationTail = Future<void>.value();
  bool _disposed = false;

  KeepAliveSnapshot get snapshot => _snapshot;

  Future<KeepAliveSnapshot> setEnabled(bool enabled) {
    return _enqueue(() => _setEnabled(enabled));
  }

  Future<KeepAliveSnapshot> refresh() {
    return _enqueue(_refresh);
  }

  Future<void> dispose() {
    _disposed = true;
    return _enqueue(() async {
      _snapshot = await _trySetEnabled(false);
      return _snapshot;
    });
  }

  Future<KeepAliveSnapshot> _setEnabled(bool enabled) async {
    if (_disposed && enabled) {
      return _snapshot;
    }
    _snapshot = await _trySetEnabled(enabled);
    return _snapshot;
  }

  Future<KeepAliveSnapshot> _refresh() async {
    try {
      _snapshot = await backend.status();
    } catch (error, stackTrace) {
      _logger.warning('[keep-alive] failed to read status', error, stackTrace);
      _snapshot = KeepAliveSnapshot.inactive(error: error.toString());
    }
    return _snapshot;
  }

  Future<KeepAliveSnapshot> _trySetEnabled(bool enabled) async {
    try {
      return await backend.setEnabled(enabled);
    } catch (error, stackTrace) {
      _logger.warning(
        '[keep-alive] failed to ${enabled ? 'start' : 'stop'}',
        error,
        stackTrace,
      );
      return KeepAliveSnapshot.inactive(error: error.toString());
    }
  }

  Future<KeepAliveSnapshot> _enqueue(
    Future<KeepAliveSnapshot> Function() operation,
  ) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
