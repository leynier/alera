import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/application/agent_provider_settings_providers.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_models_section.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_secret_dialog.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_settings_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One agent on one host. From the phone: turn it on or off, choose it for
/// new chats, manage its models, and set or clear its secrets. How it is
/// launched is shown but edited on the desktop, like Agent Profiles.
class const AgentProviderDetailScreen({
  super.key,
  required final String hostId,
  required final String? remoteHostId,
  required final String instanceId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentProviderDetailScreen> createState() =>
      _AgentProviderDetailScreenState();
}

class _AgentProviderDetailScreenState
    extends ConsumerState<AgentProviderDetailScreen>
    with AgentProviderSettingsFeedback {
  AgentProviderCatalogProvider get _catalog =>
      agentProviderCatalogProvider(widget.hostId, widget.remoteHostId);

  AgentProviderInstancesProvider get _instances =>
      agentProviderInstancesProvider(widget.hostId, widget.remoteHostId);

  AgentChatPreferencesProvider get _preferences =>
      agentChatPreferencesProvider(widget.hostId, widget.remoteHostId);

  @override
  void reloadSettings() => ref
    ..invalidate(_catalog)
    ..invalidate(_instances)
    ..invalidate(_preferences);

  Future<AgentProviderSettingsActions> _actions() async =>
      AgentProviderSettingsActions(
        await ref.read(
          agentProviderSettingsRepositoryProvider(widget.hostId).future,
        ),
        widget.remoteHostId,
      );

  Future<void> _write(String what, Future<void> Function() write) =>
      runSettingsWrite(what, () async {
        await write();
        reloadSettings();
      });

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(_catalog).value;
    final snapshot = ref.watch(_instances).value;
    final preferences = ref.watch(_preferences).value;
    AgentChatProviderInstance? instance;
    for (final candidate in catalog ?? const <AgentChatProviderInstance>[]) {
      if (candidate.id == widget.instanceId) instance = candidate;
    }
    AgentChatProviderInstanceEnvelope? envelope;
    for (final candidate in snapshot?.instances ?? const []) {
      if (candidate.providerInstanceId == widget.instanceId) {
        envelope = candidate;
      }
    }
    final current = instance;
    return Scaffold(
      appBar: AppBar(title: Text(current?.label ?? 'Agent')),
      body: SafeArea(
        child: current == null
            ? catalog == null
                  ? const Center(child: CircularProgressIndicator())
                  : const AleraEmptyState(
                      icon: AleraIcons.agent,
                      title: 'Agent removed',
                      message: 'This agent is no longer on the host.',
                    )
            : ListView(
                padding: AleraTokens.pagePadding,
                children: <Widget>[
                  ..._identity(current, snapshot),
                  ..._setup(current),
                  if (preferences != null)
                    _defaultForNewChats(current, preferences),
                  const SizedBox(height: AleraTokens.spaceXl),
                  AgentProviderModelsSection(
                    instance: current,
                    envelope: envelope,
                    preferences: preferences,
                    onDefaultModel: snapshot == null
                        ? null
                        : (model) => _write(
                            'Could not change the default model.',
                            () async => (await _actions()).setDefaultModel(
                              snapshot,
                              current.id,
                              model,
                            ),
                          ),
                    onCustomModels: snapshot == null
                        ? null
                        : (models) => _write(
                            'Could not change the custom models.',
                            () async => (await _actions()).setCustomModels(
                              snapshot,
                              current.id,
                              models,
                            ),
                          ),
                    onModelPreferences: preferences == null
                        ? null
                        : (models) => _write(
                            'Could not change the model list.',
                            () async => (await _actions()).setModelPreferences(
                              preferences,
                              current.id,
                              models,
                            ),
                          ),
                  ),
                  if (envelope != null) ...<Widget>[
                    ..._launch(envelope),
                    ..._secrets(snapshot!, envelope),
                  ],
                ],
              ),
      ),
    );
  }

  List<Widget> _identity(
    AgentChatProviderInstance instance,
    AgentChatProviderSettingsSnapshot? snapshot,
  ) {
    final status = agentProviderStatusOf(instance);
    final auth = instance.auth;
    return <Widget>[
      Card(
        child: Column(
          children: <Widget>[
            SwitchListTile(
              title: const Text('Enabled'),
              subtitle: const Text('Offer this agent for Agent Chat tabs.'),
              value: instance.enabled,
              onChanged: snapshot == null
                  ? null
                  : (enabled) => unawaited(
                      _write(
                        'Could not change the agent.',
                        () async => (await _actions()).setEnabled(
                          snapshot,
                          instance.id,
                          enabled: enabled,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: AleraTokens.contentPadding,
              child: Column(
                spacing: AleraTokens.space8,
                children: <Widget>[
                  AleraKeyValueRow(label: 'Status', value: status.label),
                  if (auth.label case final label?)
                    AleraKeyValueRow(label: 'Account', value: label),
                  AleraKeyValueRow(
                    label: 'Checked',
                    value: agentProviderCheckedLabel(
                      auth.checkedAt ?? instance.checkedAt,
                      DateTime.now(),
                    ),
                  ),
                  if (instance.version case final version?)
                    AleraKeyValueRow(label: 'Version', value: version),
                  AleraKeyValueRow(label: 'Instance', value: instance.id),
                  if (status == AgentProviderStatus.setupRequired)
                    const AleraKeyValueRow(
                      label: 'Setup',
                      value: agentProviderSetupRequiredDetail,
                    )
                  else if (instance.unavailableReason case final reason?
                      when !instance.available)
                    AleraKeyValueRow(label: 'Problem', value: reason),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Sign In, Install and Update run on the host. The phone shows the
  /// command the host verified, for a terminal there, then Refresh.
  List<Widget> _setup(AgentChatProviderInstance instance) {
    if (instance.setup.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: AleraTokens.spaceXl),
      Text('Setup', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AleraTokens.spaceSm),
      const AleraNotice(
        icon: AleraIcons.terminal,
        message: 'Run these in a terminal on the host, then refresh the list.',
      ),
      const SizedBox(height: AleraTokens.spaceSm),
      Card(
        child: Column(
          children: <Widget>[
            for (final command in instance.setup)
              ListTile(
                title: Text(command.label),
                subtitle: Text(command.command, style: AleraTokens.monoStyle),
                trailing: IconButton(
                  tooltip: 'Copy Command',
                  onPressed: () => unawaited(_copy(command.command)),
                  icon: const Icon(AleraIcons.copy),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _defaultForNewChats(
    AgentChatProviderInstance instance,
    AgentChatPreferences preferences,
  ) {
    final isDefault =
        preferences.defaultSelection?.providerInstanceId == instance.id;
    return Padding(
      padding: const EdgeInsets.only(top: AleraTokens.spaceXl),
      child: Card(
        child: SwitchListTile(
          title: const Text('Default For New Chats'),
          subtitle: const Text(
            'New chats on this host start with this agent unless the '
            'project names another.',
          ),
          value: isDefault,
          onChanged: !instance.enabled
              ? null
              : (on) => unawaited(
                  _write(
                    'Could not change the default agent.',
                    () async => (await _actions()).setDefaultSelection(
                      preferences,
                      on
                          ? AgentChatSelection(providerInstanceId: instance.id)
                          : null,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _launch(AgentChatProviderInstanceEnvelope envelope) {
    final variables = <AgentChatProviderEnvironmentEntry>[
      for (final entry in envelope.environment)
        if (!entry.sensitive) entry,
    ];
    return <Widget>[
      const SizedBox(height: AleraTokens.spaceXl),
      Text('Launch', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AleraTokens.spaceSm),
      const AleraNotice(
        icon: AleraIcons.info,
        message: 'How this agent starts is edited on the desktop.',
      ),
      const SizedBox(height: AleraTokens.spaceSm),
      Card(
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            spacing: AleraTokens.space8,
            children: <Widget>[
              AleraKeyValueRow(
                label: 'Executable',
                // ACP registry agents have no default executable to fall
                // back on; the host reports Setup Required until one is set.
                value:
                    envelope.executable ??
                    (envelope.provider == 'acpRegistry'
                        ? 'Not Set'
                        : 'Default'),
              ),
              if (envelope.args.isNotEmpty)
                AleraKeyValueRow(
                  label: 'Arguments',
                  value: envelope.args.join(' '),
                ),
              for (final entry in variables)
                AleraKeyValueRow(label: entry.name, value: entry.value ?? ''),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _secrets(
    AgentChatProviderSettingsSnapshot snapshot,
    AgentChatProviderInstanceEnvelope envelope,
  ) {
    final secrets = <({String name, String wireName, bool saved})>[
      for (final entry in envelope.environment)
        if (entry.sensitive)
          (name: entry.name, wireName: entry.name, saved: entry.secretSaved),
      for (final option in envelope.secretOptions)
        (
          name: option.name,
          wireName: agentProviderSecretOptionName(option.name),
          saved: option.secretSaved,
        ),
    ];
    if (secrets.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: AleraTokens.spaceXl),
      Text('Secrets', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AleraTokens.spaceSm),
      Card(
        child: Column(
          children: <Widget>[
            for (final secret in secrets)
              ListTile(
                leading: const Icon(AleraIcons.hidden),
                title: Text(secret.name, style: AleraTokens.monoStyle),
                subtitle: Text(secret.saved ? 'Saved' : 'Not set'),
                trailing: Wrap(
                  children: <Widget>[
                    TextButton(
                      onPressed: () =>
                          unawaited(_setSecret(snapshot, envelope, secret)),
                      child: Text(secret.saved ? 'Replace' : 'Set'),
                    ),
                    if (secret.saved)
                      TextButton(
                        onPressed: () => unawaited(
                          _write(
                            'Could not clear the secret.',
                            () async => (await _actions()).clearSecret(
                              snapshot,
                              envelope.providerInstanceId,
                              secret.wireName,
                            ),
                          ),
                        ),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Future<void> _setSecret(
    AgentChatProviderSettingsSnapshot snapshot,
    AgentChatProviderInstanceEnvelope envelope,
    ({String name, String wireName, bool saved}) secret,
  ) async {
    final value = await showAgentProviderSecretDialog(
      context,
      name: secret.name,
      replacing: secret.saved,
    );
    if (value == null) return;
    await _write(
      'Could not save the secret.',
      () async => (await _actions()).setSecret(
        snapshot,
        envelope.providerInstanceId,
        secret.wireName,
        value,
      ),
    );
  }

  Future<void> _copy(String command) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: command));
    messenger?.showSnackBar(const SnackBar(content: Text('Command copied')));
  }
}
