import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// Sensitive values are deliberately discarded even if a malformed host sends
/// them. Writes use the separate write-only secret verbs.
class const AgentChatProviderEnvironmentEntry({
  required final String name,
  final bool sensitive = false,
  final String? value,
  final bool secretSaved = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final sensitive = agentChatJsonBool(json['sensitive']);
    return AgentChatProviderEnvironmentEntry(
      name: agentChatJsonText(json['name']),
      sensitive: sensitive,
      value: sensitive ? null : agentChatJsonString(json['value']),
      secretSaved: agentChatJsonBool(json['secretSaved']),
    );
  }

  AgentChatJson toJson() => <String, Object?>{
    'name': name,
    'sensitive': sensitive,
    if (!sensitive) 'value': ?value,
  };
}

class const AgentChatProviderInstanceEnvelope({
  required final String providerInstanceId,
  required final String provider,
  final String? label,
  final bool enabled = true,
  final String? executable,
  final List<String> args = const <String>[],
  final List<AgentChatProviderEnvironmentEntry> environment =
      const <AgentChatProviderEnvironmentEntry>[],
  final AgentChatJson options = const <String, Object?>{},
  final List<String> sensitiveOptions = const <String>[],
  final List<AgentChatProviderSecretOption> secretOptions =
      const <AgentChatProviderSecretOption>[],
  final List<String> customModels = const <String>[],
  final String? defaultModel,
  final int revision = 0,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(
      json['providerInstanceId'] ?? json['instanceId'],
    );
    if (id == null)
      throw const FormatException('Provider settings have no instance id.');
    final sensitiveOptions = agentChatJsonStringList(json['sensitiveOptions']);
    final secretOptions = <AgentChatProviderSecretOption>[
      for (final entry in agentChatJsonList(json['secretOptions']))
        if (entry is Map) AgentChatProviderSecretOption.fromJson(entry),
    ];
    final secretNames = <String>{
      ...sensitiveOptions,
      for (final option in secretOptions) option.name,
    };
    return AgentChatProviderInstanceEnvelope(
      providerInstanceId: id,
      provider: agentChatJsonText(json['provider']),
      label: agentChatJsonString(json['label']),
      enabled: agentChatJsonBool(json['enabled'], true),
      executable: agentChatJsonString(json['executable']),
      args: List.unmodifiableOf(agentChatJsonStringList(json['args'])),
      environment: List.unmodifiableOf(<AgentChatProviderEnvironmentEntry>[
        for (final entry in agentChatJsonList(json['environment']))
          if (entry is Map) AgentChatProviderEnvironmentEntry.fromJson(entry),
      ]),
      options: Map.unmodifiableOf(<String, Object?>{
        for (final entry in agentChatJsonMap(json['options']).entries)
          if (!secretNames.contains(entry.key)) entry.key: entry.value,
      }),
      sensitiveOptions: List.unmodifiableOf(sensitiveOptions),
      secretOptions: List.unmodifiableOf(secretOptions),
      customModels: List.unmodifiableOf(
        agentChatJsonStringList(json['customModels']),
      ),
      defaultModel: agentChatJsonString(json['defaultModel']),
      revision: agentChatJsonInt(json['revision']) ?? 0,
    );
  }

  /// A launch-definition write preserves declared secret keys while omitting
  /// response-only saved-state metadata and the envelope revision.
  AgentChatJson toJson() => AgentChatProviderInstanceEdit(
    providerInstanceId: providerInstanceId,
    provider: provider,
    label: label,
    enabled: enabled,
    executable: executable,
    args: args,
    environment: environment,
    options: options,
    sensitiveOptions: sensitiveOptions,
    customModels: customModels,
    defaultModel: defaultModel,
    resetDefaultModel: defaultModel == null,
  ).toJson();
}

/// Optional fields permit paired phones to edit models and enabled state
/// without accidentally writing launch definitions.
class const AgentChatProviderInstanceEdit({
  required final String providerInstanceId,
  final String? provider,
  final String? label,
  final bool? enabled,
  final String? executable,
  final List<String>? args,
  final List<AgentChatProviderEnvironmentEntry>? environment,
  final AgentChatJson? options,
  final List<String>? sensitiveOptions,
  final List<String>? customModels,
  final String? defaultModel,
  final bool resetDefaultModel = false,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'providerInstanceId': providerInstanceId,
    'provider': ?provider,
    'label': ?label,
    'enabled': ?enabled,
    'executable': ?executable,
    'args': ?args,
    if (environment != null)
      'environment': <AgentChatJson>[
        for (final entry in environment!) entry.toJson(),
      ],
    if (options != null)
      'options': <String, Object?>{
        for (final entry in options!.entries)
          if (!(sensitiveOptions?.contains(entry.key) ?? false))
            entry.key: entry.value,
      },
    'sensitiveOptions': ?sensitiveOptions,
    'customModels': ?customModels,
    if (resetDefaultModel || defaultModel != null)
      'defaultModel': agentChatJsonString(defaultModel),
  };
}

class const AgentChatProviderSecretOption({
  required final String name,
  final bool secretSaved = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatProviderSecretOption(
      name: agentChatJsonText(json['name']),
      secretSaved: agentChatJsonBool(json['secretSaved']),
    );
  }
}

class const AgentChatProviderSettingsSnapshot({
  final List<AgentChatProviderInstanceEnvelope> instances =
      const <AgentChatProviderInstanceEnvelope>[],
  final int revision = 0,
  final String? migrationError,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatProviderSettingsSnapshot(
      instances: List.unmodifiableOf(<AgentChatProviderInstanceEnvelope>[
        for (final instance in agentChatJsonList(json['instances']))
          if (instance is Map)
            AgentChatProviderInstanceEnvelope.fromJson(instance),
      ]),
      revision: agentChatJsonInt(json['revision']) ?? 0,
      migrationError: agentChatJsonString(json['migrationError']),
    );
  }
}

class const AgentChatProviderRemovalChat({
  required final String chatId,
  required final String title,
  required final String workspaceId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatProviderRemovalChat(
      chatId: agentChatJsonText(json['chatId']),
      title: agentChatJsonText(json['title']),
      workspaceId: agentChatJsonText(json['workspaceId']),
    );
  }
}

class const AgentChatProviderRemovalImpact({
  required final String providerInstanceId,
  final List<AgentChatProviderRemovalChat> openChats =
      const <AgentChatProviderRemovalChat>[],
  final int count = 0,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final chats = <AgentChatProviderRemovalChat>[
      for (final chat in agentChatJsonList(json['openChats']))
        if (chat is Map) AgentChatProviderRemovalChat.fromJson(chat),
    ];
    return AgentChatProviderRemovalImpact(
      providerInstanceId: agentChatJsonText(json['providerInstanceId']),
      openChats: List.unmodifiableOf(chats),
      count: agentChatJsonInt(json['count']) ?? chats.length,
    );
  }
}
