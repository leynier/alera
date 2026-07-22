import 'dart:convert';
import 'dart:typed_data';

const int aleraTerminalHostProtocolVersion = 4;
const String aleraCliExecutableName = 'alera';
const String aleraCliWindowsExecutableName = 'alera.exe';
const String aleraRuntimeHostCommand = 'runtime-host';
const String aleraTerminalHostCommand = 'terminal-host';
const String aleraRuntimeHostCapability = 'runtimeStore';
const String aleraRuntimeHostBootstrapCapability = 'sshTargetBootstrap';
const String aleraRuntimeHostManagedWorkspaceCapability =
    'managedWorkspaceLifecycle';
const String aleraRuntimeHostOrchestrationCapability = 'orchestration';
const String aleraRuntimeHostAgentQuotaClaudeTuiCapability =
    'agentQuotaClaudeTuiV1';
const String aleraRuntimeHostConnectedEvent = 'runtimeHostConnected';
const int defaultTerminalHostEmptyShutdownDelaySeconds = 30;
const int defaultTerminalHostDetachedSessionShutdownDelaySeconds = 60 * 60;
const int defaultTerminalHostScrollbackBytes = 10 * 1000 * 1000;

final class TerminalHostConfig {
  const TerminalHostConfig({
    this.emptyShutdownDelaySeconds =
        defaultTerminalHostEmptyShutdownDelaySeconds,
    this.detachedSessionShutdownDelaySeconds =
        defaultTerminalHostDetachedSessionShutdownDelaySeconds,
    this.scrollbackBytes = defaultTerminalHostScrollbackBytes,
  });

  factory TerminalHostConfig.fromJson(Map<String, Object?> json) {
    return TerminalHostConfig(
      emptyShutdownDelaySeconds: _positiveInt(
        json['emptyShutdownDelaySeconds'],
        'emptyShutdownDelaySeconds',
      ),
      detachedSessionShutdownDelaySeconds: _positiveInt(
        json['detachedSessionShutdownDelaySeconds'],
        'detachedSessionShutdownDelaySeconds',
      ),
      scrollbackBytes: _positiveInt(json['scrollbackBytes'], 'scrollbackBytes'),
    );
  }

  static const defaults = TerminalHostConfig();

  final int emptyShutdownDelaySeconds;
  final int detachedSessionShutdownDelaySeconds;
  final int scrollbackBytes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'emptyShutdownDelaySeconds': emptyShutdownDelaySeconds,
      'detachedSessionShutdownDelaySeconds':
          detachedSessionShutdownDelaySeconds,
      'scrollbackBytes': scrollbackBytes,
    };
  }
}

int _positiveInt(Object? value, String label) {
  if (value is int && value > 0) {
    return value;
  }
  throw FormatException('$label must be a positive integer.');
}

final class TerminalHostLaunch {
  const TerminalHostLaunch({
    required this.label,
    required this.shell,
    required this.arguments,
    required this.environment,
  });

  factory TerminalHostLaunch.fromJson(Map<String, Object?> json) {
    final shell = json['shell'];
    if (shell is! String || shell.isEmpty) {
      throw const FormatException('Terminal host launch shell is required.');
    }
    return TerminalHostLaunch(
      label: (json['label'] as String?) ?? 'shell',
      shell: shell,
      arguments: asTerminalHostStringList(json['arguments']),
      environment: asTerminalHostStringMap(json['environment']),
    );
  }

  final String label;
  final String shell;
  final List<String> arguments;
  final Map<String, String> environment;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'shell': shell,
      'arguments': arguments,
      'environment': environment,
    };
  }
}

String encodeTerminalHostBytes(List<int> bytes) {
  return base64Encode(bytes);
}

Uint8List decodeTerminalHostBytes(Object? value) {
  if (value is! String || value.isEmpty) {
    return Uint8List(0);
  }
  return base64Decode(value);
}

Map<String, Object?> asTerminalHostMap(Object? value, String label) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw FormatException('$label must be a JSON object.');
}

List<String> asTerminalHostStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return <String>[
    for (final item in value)
      if (item is String) item,
  ];
}

Map<String, String> asTerminalHostStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

final class RuntimeHostEvent {
  const RuntimeHostEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

abstract interface class RuntimeHostClient {
  Stream<RuntimeHostEvent> get runtimeEvents;

  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);
}
