part of 'mobile_codex_controller.dart';

Map<String, Object?> _permissionSubset(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  final source = Map<String, Object?>.from(value);
  final result = <String, Object?>{};
  final fileSystem = _permissionObject(source['fileSystem'], const <String>[
    'entries',
    'globScanMaxDepth',
    'read',
    'write',
  ]);
  final network = _permissionObject(source['network'], const <String>[
    'enabled',
  ]);
  if (fileSystem.isNotEmpty) result['fileSystem'] = fileSystem;
  if (network.isNotEmpty) result['network'] = network;
  return result;
}

Map<String, Object?> _permissionObject(Object? value, List<String> keys) {
  if (value is! Map) return const <String, Object?>{};
  final source = Map<String, Object?>.from(value);
  return <String, Object?>{
    for (final key in keys)
      if (source.containsKey(key)) key: source[key],
  };
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _supportedEffort(MobileCodexModelOption? model, String requested) {
  final values = model?.reasoningEfforts ?? const <String>[];
  if (values.isEmpty || values.contains(requested)) return requested;
  final modelDefault = model?.defaultReasoningEffort;
  if (modelDefault != null && values.contains(modelDefault)) {
    return modelDefault;
  }
  for (final value in <String>['medium', 'high', 'low', 'xhigh']) {
    if (values.contains(value)) return value;
  }
  return values.first;
}

Map<String, Object?> _mobileConfigurationPayload(MobileCodexState state) =>
    <String, Object?>{
      'selectedModel': state.selectedModel,
      'reasoningEffort': state.reasoningEffort,
      'speedMode': state.speedMode,
      'permissionMode': state.permissionMode,
      'planMode': state.planMode,
      'collaborationMode': state.collaborationMode,
    };

MobileCodexState _applyMobileConfiguration(
  MobileCodexState state,
  Object? value,
) {
  if (value is! Map) return state;
  final json = Map<String, Object?>.from(value);
  final selectedModel = _string(json['selectedModel']);
  final reasoningEffort = _string(json['reasoningEffort']);
  final permissionMode = _string(json['permissionMode']);
  final collaborationMode = _string(json['collaborationMode']);
  return state.copyWith(
    selectedModel: selectedModel ?? state.selectedModel,
    reasoningEffort: reasoningEffort ?? state.reasoningEffort,
    speedMode: json['speedMode'] == 'fast' ? 'fast' : 'normal',
    permissionMode: switch (permissionMode) {
      'untrusted' ||
      'on-request' ||
      'auto-review' ||
      'never' => permissionMode!,
      _ => state.permissionMode,
    },
    planMode: json['planMode'] is bool
        ? json['planMode']! as bool
        : state.planMode,
    collaborationMode: collaborationMode,
  );
}

String _safeError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty
      ? 'Codex request failed. Check the runtime connection and retry.'
      : message;
}
