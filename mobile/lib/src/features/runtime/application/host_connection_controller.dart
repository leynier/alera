import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_restart_result.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_connection_controller.g.dart';

const Duration _probeTimeout = Duration(seconds: 8);
const Duration _runtimeRestartReconnectDelay = Duration(milliseconds: 300);
const List<Duration> _retryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

/// The runtime socket ended without the app asking it to, so every stream and
/// pending request on that client is dead. Raised into the provider so screens
/// stop showing a live-looking connection and offer their Retry instead.
class RuntimeConnectionLost implements Exception {
  const RuntimeConnectionLost();

  @override
  String toString() => 'Lost The Connection To The Host';
}

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed. Transport failures recover
/// while the app is in the foreground, and leaving every host surface disposes
/// the client and stops retry work.
@riverpod
class HostConnectionController extends _$HostConnectionController {
  final Logger _logger = Logger('HostConnectionController');
  MobileRuntimeClient? _client;
  StreamSubscription<MobileRuntimeEvent>? _closeSub;
  Timer? _retryTimer;
  Future<void>? _connectionAttempt;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  int _retryIndex = 0;
  bool _building = false;
  bool _disposed = false;

  @override
  Future<MobileRuntimeClient> build(String hostId) async {
    _building = true;
    _lifecycleState = ref.read(appLifecycleControllerProvider);
    ref.listen(appLifecycleControllerProvider, _handleLifecycleChange);
    ref.onDispose(_dispose);
    try {
      final client = await _openClient();
      await _bindClient(client);
      return client;
    } catch (error, stackTrace) {
      _scheduleRetry(error);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _building = false;
    }
  }

  Future<void> reconnectNow() {
    _retryIndex = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    return _runReconnect();
  }

  Future<RuntimeRestartResult> restartRuntime({bool force = false}) async {
    final client = _client ?? state.value;
    if (client == null) {
      throw StateError('Host Is Not Connected.');
    }
    try {
      final result = await client.restartRuntime(force: force);
      await _closeSub?.cancel();
      _closeSub = null;
      _client = null;
      state = const AsyncLoading<MobileRuntimeClient>();
      unawaited(_recoverAfterRuntimeRestart(client));
      return result;
    } on RuntimeRestartBusyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'could not restart runtime host $hostId',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _recoverAfterRuntimeRestart(MobileRuntimeClient client) async {
    try {
      await client.dispose();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'could not close the previous runtime connection for $hostId',
        error,
        stackTrace,
      );
    }
    await Future<void>.delayed(_runtimeRestartReconnectDelay);
    if (!_disposed) {
      await reconnectNow();
    }
  }

  Future<MobileRuntimeClient> _openClient() async {
    final hosts = await ref.read(pairedHostsControllerProvider.future);
    final host = hosts.where((host) => host.id == hostId).firstOrNull;
    if (host == null) {
      throw StateError('Host Is Not Paired.');
    }
    final deviceToken = await ref
        .read(hostRepositoryProvider)
        .readDeviceToken(hostId);
    if (deviceToken == null || deviceToken.trim().isEmpty) {
      throw StateError('Device Token Is Missing.');
    }
    final cloudDeviceId = await ref
        .read(cloudAccountRepositoryProvider)
        .getOrCreateInstallationId();
    final client = await MobileRuntimeClient.connect(host.endpoint);
    try {
      await client.authenticate(
        deviceId: host.deviceId,
        deviceToken: deviceToken,
        cloudDeviceId: cloudDeviceId,
      );
    } on Object {
      await client.dispose();
      rethrow;
    }
    return client;
  }

  Future<void> _bindClient(MobileRuntimeClient client) async {
    if (_disposed) {
      await client.dispose();
      return;
    }
    final previousClient = _client;
    _client = null;
    await _closeSub?.cancel();
    _closeSub = null;
    if (previousClient != null && !identical(previousClient, client)) {
      await previousClient.dispose();
    }
    _client = client;
    _retryIndex = 0;
    final closeSub = client.events.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) =>
          _handleClientEnded(client, error, stackTrace),
      onDone: () => _handleClientEnded(
        client,
        const RuntimeConnectionLost(),
        StackTrace.current,
      ),
      cancelOnError: false,
    );
    _closeSub = closeSub;
  }

  void _handleClientEnded(
    MobileRuntimeClient client,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_disposed || !identical(_client, client)) {
      return;
    }
    _client = null;
    _closeSub = null;
    state = AsyncError(error, stackTrace);
    _logger.warning(
      'connection to host $hostId ended; scheduling recovery',
      error,
      stackTrace,
    );
    _scheduleRetry(error, immediate: true);
  }

  void _handleLifecycleChange(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    _lifecycleState = next;
    if (next != AppLifecycleState.resumed) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (previous == AppLifecycleState.resumed || _building) {
      return;
    }
    final client = _client;
    if (client == null) {
      unawaited(reconnectNow());
      return;
    }
    unawaited(_probe(client));
  }

  Future<void> _probe(MobileRuntimeClient client) async {
    try {
      await client.mobileStatus().timeout(_probeTimeout);
    } on Object catch (error, stackTrace) {
      if (_disposed || !identical(_client, client)) {
        return;
      }
      _logger.warning(
        'foreground probe failed for host $hostId; reconnecting',
        error,
        stackTrace,
      );
      await reconnectNow();
    }
  }

  void _scheduleRetry(Object error, {bool immediate = false}) {
    if (_disposed ||
        _lifecycleState != AppLifecycleState.resumed ||
        !_isRetryable(error) ||
        _retryTimer != null) {
      return;
    }
    final delay = immediate
        ? Duration.zero
        : _retryDelays[_retryIndex.clamp(0, _retryDelays.length - 1)];
    if (!immediate && _retryIndex < _retryDelays.length - 1) {
      _retryIndex += 1;
    }
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_runReconnect());
    });
  }

  bool _isRetryable(Object error) =>
      error is! StateError && error is! FormatException;

  Future<void> _runReconnect() {
    final activeAttempt = _connectionAttempt;
    if (activeAttempt != null) {
      return activeAttempt;
    }
    if (_disposed || _lifecycleState != AppLifecycleState.resumed) {
      return Future<void>.value();
    }
    late final Future<void> attempt;
    attempt = _performReconnect().whenComplete(() {
      if (identical(_connectionAttempt, attempt)) {
        _connectionAttempt = null;
      }
    });
    _connectionAttempt = attempt;
    return attempt;
  }

  Future<void> _performReconnect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final previousClient = _client;
    _client = null;
    await _closeSub?.cancel();
    _closeSub = null;
    if (previousClient != null) {
      await previousClient.dispose();
    }
    if (_disposed) {
      return;
    }
    state = const AsyncLoading<MobileRuntimeClient>();
    try {
      final client = await _openClient();
      await _bindClient(client);
      if (!_disposed) {
        state = AsyncData(client);
      }
    } on Object catch (error, stackTrace) {
      if (_disposed) {
        return;
      }
      _logger.warning('could not reconnect to host $hostId', error, stackTrace);
      state = AsyncError(error, stackTrace);
      _scheduleRetry(error);
    }
  }

  void _dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final closeSub = _closeSub;
    _closeSub = null;
    final client = _client;
    _client = null;
    if (closeSub != null) {
      unawaited(closeSub.cancel());
    }
    if (client != null) {
      unawaited(client.dispose());
    }
  }
}
