part of 'terminal_host_client.dart';

extension SocketTerminalHostClientLifecycle on SocketTerminalHostClient {
  /// Connects to a live host when one is already published; never launches.
  ///
  /// Returns `null` when no compatible host is reachable.
  Future<Map<String, Object?>?> probeRuntimeStatus() async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    try {
      final connection = await _connectRuntime(launchIfMissing: false);
      final payload = await _requestOnConnection(
        connection,
        'status.get',
        const <String, Object?>{},
      );
      return asTerminalHostMap(payload, 'runtime status');
    } on StateError catch (error) {
      if (error.message.contains('No live Alera runtime host')) {
        return null;
      }
      rethrow;
    }
  }

  Future<RuntimeHostShutdownResult> shutdownRuntime({
    bool force = false,
  }) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    try {
      final connection = await _connectRuntime(launchIfMissing: false);
      final payload = await _requestOnConnection(
        connection,
        'host.shutdown',
        <String, Object?>{'force': force},
      );
      return RuntimeHostShutdownResult.fromJson(
        asTerminalHostMap(payload, 'runtime shutdown'),
      );
    } on StateError catch (error) {
      final busy = _busyExceptionFromShutdown(error.message);
      if (busy != null) {
        throw busy;
      }
      rethrow;
    }
  }
}

final _shutdownBusyPattern = RegExp(
  r'Runtime host has (\d+) active agent\(s\), (\d+) active terminal session\(s\), (\d+) active background job\(s\), and (\d+) active push subscription\(s\)',
);

final _threeCountShutdownBusyPattern = RegExp(
  r'Runtime host has (\d+) active agent\(s\), (\d+) active terminal session\(s\) and (\d+) active background job\(s\)',
);

final _twoCountShutdownBusyPattern = RegExp(
  r'Runtime host has (\d+) active terminal session\(s\) and (\d+) active background job\(s\)',
);

RuntimeHostBusyException? _busyExceptionFromShutdown(String message) {
  final match = _shutdownBusyPattern.firstMatch(message);
  if (match != null) {
    return RuntimeHostBusyException(
      message: message,
      activeAgents: int.tryParse(match.group(1) ?? '') ?? 0,
      activeSessions: int.tryParse(match.group(2) ?? '') ?? 0,
      activeJobs: int.tryParse(match.group(3) ?? '') ?? 0,
      activePushSubscriptions: int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }
  final threeCount = _threeCountShutdownBusyPattern.firstMatch(message);
  if (threeCount != null) {
    return RuntimeHostBusyException(
      message: message,
      activeAgents: int.tryParse(threeCount.group(1) ?? '') ?? 0,
      activeSessions: int.tryParse(threeCount.group(2) ?? '') ?? 0,
      activeJobs: int.tryParse(threeCount.group(3) ?? '') ?? 0,
    );
  }
  final legacy = _twoCountShutdownBusyPattern.firstMatch(message);
  if (legacy == null) return null;
  return RuntimeHostBusyException(
    message: message,
    activeSessions: int.tryParse(legacy.group(1) ?? '') ?? 0,
    activeJobs: int.tryParse(legacy.group(2) ?? '') ?? 0,
  );
}

Future<bool> _controlAcceptsHello(_TerminalHostControl control) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      control.port,
      timeout: _terminalHostConnectTimeout,
    );
    final lines = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    socket.writeln(
      jsonEncode(<String, Object?>{
        'id': 0,
        'type': 'hello',
        'payload': <String, Object?>{
          'protocolVersion': aleraTerminalHostProtocolVersion,
          'token': control.token,
        },
      }),
    );
    final line = await lines.first.timeout(_terminalHostConnectTimeout);
    final message = asTerminalHostMap(
      jsonDecode(line),
      'Terminal host hello response',
    );
    return message['id'] == 0 && message['ok'] == true;
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
  }
}
