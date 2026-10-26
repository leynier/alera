import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';

class const AgentChatSelection({
  required final String providerInstanceId,
  final String? model,
  final AgentChatRuntimeMode? runtimeMode,
  final AgentChatInteractionMode? interactionMode,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['providerInstanceId']);
    if (id == null)
      throw const FormatException('Selection has no provider instance.');
    return AgentChatSelection(
      providerInstanceId: id,
      model: agentChatJsonString(json['model']),
      runtimeMode: AgentChatRuntimeMode.tryParse(json['runtimeMode']),
      interactionMode: AgentChatInteractionMode.tryParse(
        json['interactionMode'],
      ),
    );
  }

  AgentChatJson toJson() => <String, Object?>{
    'providerInstanceId': providerInstanceId,
    'model': ?agentChatJsonString(model),
    'runtimeMode': ?runtimeMode?.wire,
    'interactionMode': ?interactionMode?.wire,
  };

  AgentChatConfiguration configuration({bool switchProvider = false}) =>
      AgentChatConfiguration(
        providerInstanceId: switchProvider ? providerInstanceId : null,
        model: model,
        resetModel: agentChatJsonString(model) == null,
        runtimeMode: runtimeMode,
        interactionMode: interactionMode,
      );

  AgentChatCreateInput createInput({
    required String requestId,
    required String workspaceId,
    String? title,
  }) => AgentChatCreateInput(
    requestId: requestId,
    workspaceId: workspaceId,
    providerInstanceId: providerInstanceId,
    model: model,
    runtimeMode: runtimeMode,
    interactionMode: interactionMode,
    title: title,
  );

  @override
  bool operator ==(Object other) =>
      other is AgentChatSelection &&
      other.providerInstanceId == providerInstanceId &&
      other.model == model &&
      other.runtimeMode == runtimeMode &&
      other.interactionMode == interactionMode;

  @override
  int get hashCode =>
      Object.hash(providerInstanceId, model, runtimeMode, interactionMode);
}

/// A disabled, unavailable, or unconfigured instance cannot win precedence.
/// Unknown model ids remain valid for providers that accept custom model ids.
AgentChatSelection? resolveAgentChatSelection({
  required List<AgentChatProviderInstance> providers,
  AgentChatSelection? projectDefault,
  AgentChatSelection? launchingSelection,
  AgentChatSelection? defaultSelection,
  AgentChatSelection? rememberedSelection,
}) {
  final available = <String, AgentChatProviderInstance>{
    for (final instance in providers)
      if (instance.enabled && instance.available) instance.id: instance,
  };
  for (final selection in <AgentChatSelection?>[
    projectDefault,
    launchingSelection,
    defaultSelection,
    rememberedSelection,
  ]) {
    if (selection != null &&
        available.containsKey(selection.providerInstanceId)) {
      return selection;
    }
  }
  final instance = available.values.firstOrNull;
  return instance == null
      ? null
      : AgentChatSelection(providerInstanceId: instance.id);
}
