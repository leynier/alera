import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

enum PromptWorkspaceOperationStatus {
  running,
  needsInput,
  completed,
  failed,
  cancelled;

  static PromptWorkspaceOperationStatus parse(Object? value) {
    for (final status in values) {
      if (status.name == value) {
        return status;
      }
    }
    return failed;
  }
}

/// One `workspace.promptStart` operation as the runtime reports it.
class const PromptWorkspaceOperation({
  required final String id,
  required final PromptWorkspaceOperationStatus status,
  required final String phase,
  final Map<String, Object?>? workspace,
  final String? agentTabId,
  final String? setupTabId,
  final List<String> warnings = const <String>[],
  final String? errorMessage,
  final bool retryable = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    final error = _optionalMap(json['error']);
    final workspace = _optionalMap(json['workspace']);
    return PromptWorkspaceOperation(
      id: _requiredString(json, 'id'),
      status: .parse(json['status']),
      phase: _optionalString(json['phase']) ?? '',
      workspace: workspace == null || _optionalString(workspace['id']) == null
          ? null
          : workspace,
      agentTabId: _optionalString(_optionalMap(json['agent'])?['tabId']),
      setupTabId: _optionalString(_optionalMap(json['setup'])?['tabId']),
      warnings: <String>[
        for (final warning in _list(json['warnings']))
          if (warning is String && warning.trim().isNotEmpty) warning,
      ],
      errorMessage: _optionalString(error?['message']),
      retryable: error?['retryable'] == true,
    );
  }

  bool get isRunning => status == PromptWorkspaceOperationStatus.running;

  bool get hasWorkspace => workspace != null;

  /// The failure as the job card shows it.
  String get failureMessage => switch (status) {
    .cancelled => 'Workspace creation was cancelled.',
    .needsInput =>
      errorMessage ?? 'The runtime needs more input to create this workspace.',
    _ => errorMessage ?? 'Workspace creation failed.',
  };
}

/// The job card phase for a runtime phase, using the same text as the
/// client-side pipeline so both paths read alike.
String promptWorkspacePhaseLabel(String phase) => switch (phase) {
  'resolvingProject' || 'generatingIdentity' => 'Generating workspace identity',
  'checkingBranch' => 'Checking generated branch',
  'creatingWorkspace' || 'assigningSection' => 'Creating workspace',
  _ => 'Starting agent',
};

/// `workspace.promptStart.*` on the runtime that owns New Workspace from
/// Prompt when it advertises
/// [aleraRuntimeHostPromptWorkspaceServiceCapability].
class PromptWorkspaceServiceClient(
  final RuntimeHostClient _client, {
  final Future<void> Function()? beforeAccess,
  final Duration pollInterval = const Duration(seconds: 1),
  final Duration eventSafetyInterval = const Duration(seconds: 10),
  final int maxConsecutiveReadFailures = 3,
}) {
  Future<bool> isSupported() async {
    await beforeAccess?.call();
    final client = _client;
    if (client is! RuntimeHostCapabilityClient) {
      return false;
    }
    try {
      return await (client as RuntimeHostCapabilityClient)
          .supportsRuntimeCapability(
            aleraRuntimeHostPromptWorkspaceServiceCapability,
          );
    } on Object {
      return false;
    }
  }

  Future<PromptWorkspaceOperation> start(Map<String, Object?> payload) =>
      _call('workspace.promptStart.start', payload);

  Future<PromptWorkspaceOperation> get(String id) =>
      _call('workspace.promptStart.get', <String, Object?>{'id': id});

  Future<PromptWorkspaceOperation> retryLaunch(String id) =>
      _call('workspace.promptStart.retryLaunch', <String, Object?>{'id': id});

  /// Follows [operation] until it leaves `running`. Each
  /// `promptWorkspaceOperationsChanged` for it triggers a read; until one
  /// arrives the operation is polled every [pollInterval], since an older or
  /// disconnected event stream would otherwise leave the job waiting forever.
  Future<PromptWorkspaceOperation> follow(
    PromptWorkspaceOperation operation, {
    void Function(PromptWorkspaceOperation operation)? onUpdate,
  }) async {
    var current = operation;
    onUpdate?.call(current);
    if (!current.isRunning) {
      return current;
    }
    var wake = Completer<void>();
    var eventsSeen = false;
    final subscription = _client.runtimeEvents.listen((event) {
      if (event.name != aleraPromptWorkspaceOperationsChangedEvent ||
          event.payload['id'] != current.id) {
        return;
      }
      eventsSeen = true;
      if (!wake.isCompleted) {
        wake.complete();
      }
    });
    var failures = 0;
    try {
      while (current.isRunning) {
        await Future.any(<Future<void>>[
          wake.future,
          Future.pause(eventsSeen ? eventSafetyInterval : pollInterval),
        ]);
        wake = Completer<void>();
        try {
          current = await get(current.id);
          failures = 0;
        } on Object {
          failures += 1;
          if (failures >= maxConsecutiveReadFailures) {
            rethrow;
          }
          continue;
        }
        onUpdate?.call(current);
      }
      return current;
    } finally {
      await subscription.cancel();
    }
  }

  Future<PromptWorkspaceOperation> _call(
    String type,
    Map<String, Object?> payload,
  ) async {
    await beforeAccess?.call();
    final response = await _client.runtimeRequest(type, payload);
    if (response is! Map) {
      throw const FormatException('Runtime response must be a JSON object.');
    }
    return PromptWorkspaceOperation.fromJson(
      Map<String, Object?>.from(response),
    );
  }
}

Map<String, Object?>? _optionalMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.of(value) : const <Object?>[];

String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _requiredString(Map<String, Object?> json, String key) =>
    _optionalString(json[key]) ??
    (throw FormatException('Runtime response is missing "$key".'));
