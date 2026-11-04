import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_status.dart';

class const AgentChatModelOption({
  required final String? id,
  required final String label,
  final bool isDefault = false,
  final List<String> reasoningEfforts = const <String>[],
  final String? defaultReasoningEffort,
  final int? contextWindow,
  final AgentChatModelsSource? source,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['id']);
    return AgentChatModelOption(
      id: id,
      label: agentChatJsonString(json['label']) ?? id ?? 'Provider Default',
      isDefault: agentChatJsonBool(json['isDefault']),
      reasoningEfforts: agentChatJsonStringList(json['reasoningEfforts']),
      defaultReasoningEffort: agentChatJsonString(
        json['defaultReasoningEffort'],
      ),
      contextWindow: agentChatJsonInt(json['contextWindow']),
      source: json['source'] == null
          ? null
          : AgentChatModelsSource.fromJson(json['source']),
    );
  }
}

/// Where a provider's model list came from. Without cheap discovery the
/// runtime lists the configured model or a single provider default entry.
enum AgentChatModelsSource {
  discovered,
  discoveredAndConfigured,
  configured,
  providerDefault;

  static AgentChatModelsSource fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatModelsSource.values,
    AgentChatModelsSource.providerDefault,
  );
}

String agentChatModelsSourceLabel(AgentChatModelsSource source) =>
    switch (source) {
      .discovered => 'Discovered',
      .discoveredAndConfigured => 'Discovered And Configured',
      .configured => 'Configured',
      .providerDefault => 'Provider Default Only',
    };

/// One configured provider the runtime can start chats with, and whether it
/// can right now. [available] alone does not prove verified sign-in. The default
/// instance of a provider has [id] equal to [provider].
class const AgentChatProviderInstance({
  required final String id,
  required final String provider,
  required final String label,
  final bool available = true,
  final bool enabled = true,

  /// Host configuration is needed before installation can be checked.
  final bool setupRequired = false,
  final bool? installed,
  final String? version,
  final DateTime? checkedAt,
  final AgentChatProviderAuth auth = const AgentChatProviderAuth(),
  final List<AgentChatProviderSetupCommand> setup =
      const <AgentChatProviderSetupCommand>[],
  final String? unavailableReason,
  final bool custom = false,
  final AgentChatModelsSource modelsSource =
      AgentChatModelsSource.providerDefault,
  final AgentChatCapabilities capabilities = const AgentChatCapabilities(),
  final List<AgentChatRuntimeMode> runtimeModes =
      const <AgentChatRuntimeMode>[],
  final List<AgentChatInteractionMode> interactionModes =
      const <AgentChatInteractionMode>[],
  final List<AgentChatModelOption> models = const <AgentChatModelOption>[],
  final String? defaultModel,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['providerInstanceId'] ?? json['id']);
    if (id == null) {
      throw const FormatException('Agent chat provider has no instance id.');
    }
    final provider = agentChatJsonString(json['provider']) ?? id;
    return AgentChatProviderInstance(
      id: id,
      provider: provider,
      label: agentChatJsonString(json['label']) ?? provider,
      available: agentChatJsonBool(json['available'], true),
      enabled: agentChatJsonBool(json['enabled'], true),
      setupRequired: agentChatJsonBool(json['setupRequired']),
      installed: json['installed'] is bool ? json['installed'] as bool : null,
      version: agentChatJsonString(json['version']),
      checkedAt: agentChatJsonDate(json['checkedAt']),
      auth: AgentChatProviderAuth.fromJson(json['auth']),
      setup: agentChatProviderSetupFromJson(json['setup']),
      unavailableReason: agentChatJsonString(json['unavailableReason']),
      custom: agentChatJsonBool(json['custom']),
      modelsSource: AgentChatModelsSource.fromJson(json['modelsSource']),
      capabilities: AgentChatCapabilities.fromJson(json['capabilities']),
      runtimeModes: AgentChatRuntimeMode.listFromJson(json['runtimeModes']),
      interactionModes: AgentChatInteractionMode.listFromJson(
        json['interactionModes'],
      ),
      models: <AgentChatModelOption>[
        for (final model in agentChatJsonList(json['models']))
          if (model is Map) AgentChatModelOption.fromJson(model),
      ],
      defaultModel: agentChatJsonString(json['defaultModel']),
    );
  }

  AgentChatModelOption? modelById(String? id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// The model a new chat starts with: the runtime's default, else the model
  /// the catalog marks as default, else the first one.
  AgentChatModelOption? get initialModel =>
      modelById(defaultModel) ??
      models.where((model) => model.isDefault).firstOrNull ??
      models.firstOrNull;

  bool get supportsPlanMode =>
      interactionModes.contains(AgentChatInteractionMode.plan);
}

List<AgentChatProviderInstance> agentChatProvidersFromJson(Object? value) {
  final json = agentChatJsonMap(value);
  final list = value is List ? value : agentChatJsonList(json['providers']);
  return <AgentChatProviderInstance>[
    for (final provider in list)
      if (provider is Map) AgentChatProviderInstance.fromJson(provider),
  ];
}
