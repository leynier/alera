import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_model_picker_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/application/agent_provider_settings_providers.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_detail_screen.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_project_defaults.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_settings_feedback.dart';
import 'package:alera_mobile/src/features/projects/application/projects_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings > Providers: the agents Agent Chat tabs can use on each host,
/// whether they are ready, and the defaults for new chats. This Device is
/// the paired runtime; each Remote Host behind it has its own list.
class const AgentProvidersScreen({
  super.key,
  required final String hostId,
  final String? initialRemoteHostId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentProvidersScreen> createState() =>
      _AgentProvidersScreenState();
}

class _AgentProvidersScreenState extends ConsumerState<AgentProvidersScreen>
    with AgentProviderSettingsFeedback {
  late String? _remoteHostId = widget.initialRemoteHostId;
  bool _refreshing = false;

  AgentProviderCatalogProvider get _catalog =>
      agentProviderCatalogProvider(widget.hostId, _remoteHostId);

  @override
  void reloadSettings() => ref
    ..invalidate(agentProviderInstancesProvider(widget.hostId, _remoteHostId))
    ..invalidate(agentChatPreferencesProvider(widget.hostId, _remoteHostId))
    ..invalidate(_catalog);

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await runSettingsWrite('Could not check the agents again.', () async {
      final settings = await ref.read(
        agentProviderSettingsRepositoryProvider(widget.hostId).future,
      );
      await AgentProviderSettingsActions(settings, _remoteHostId).refresh();
      ref.invalidate(_catalog);
    });
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(_catalog);
    final snapshot = ref
        .watch(agentProviderInstancesProvider(widget.hostId, _remoteHostId))
        .value;
    final preferences = ref
        .watch(agentChatPreferencesProvider(widget.hostId, _remoteHostId))
        .value;
    final hosts =
        ref
            .watch(workspaceHostsControllerProvider(widget.hostId))
            .value
            ?.byId
            .values
            .toList() ??
        const [];
    final providers = catalog.value;
    final projects =
        ref.watch(projectsControllerProvider(widget.hostId)).value?.projects ??
        const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : () => unawaited(_refresh()),
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: AleraTokens.space16,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                : const Icon(AleraIcons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: providers == null
            ? catalog.hasError
                  ? AleraEmptyState(
                      icon: AleraIcons.loadFailed,
                      title: 'Could not load agents',
                      message: agentChatErrorMessage(catalog.error!),
                      action: TextButton(
                        onPressed: () => ref.invalidate(_catalog),
                        child: const Text(agentChatTryAgainLabel),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AleraTokens.pagePadding,
                children: <Widget>[
                  const Text(
                    'Agents for Agent Chat tabs. For terminal tabs, use '
                    'Agent Profiles.',
                  ),
                  if (hosts.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AleraTokens.spaceMd),
                    Wrap(
                      spacing: AleraTokens.space8,
                      runSpacing: AleraTokens.space8,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('This Device'),
                          selected: _remoteHostId == null,
                          onSelected: (_) =>
                              setState(() => _remoteHostId = null),
                        ),
                        for (final host in hosts)
                          ChoiceChip(
                            label: Text(host.alias),
                            selected: _remoteHostId == host.id,
                            onSelected: (_) =>
                                setState(() => _remoteHostId = host.id),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AleraTokens.spaceSm),
                  Text(
                    agentProviderCheckedLabel(
                      agentProviderLastChecked(providers),
                      DateTime.now(),
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
                  if (snapshot?.migrationError case final error?) ...<Widget>[
                    const SizedBox(height: AleraTokens.spaceMd),
                    AleraNotice(icon: AleraIcons.warning, message: error),
                  ],
                  if (preferences != null) ...<Widget>[
                    const SizedBox(height: AleraTokens.spaceXl),
                    _DefaultForNewChats(
                      providers: providers,
                      preferences: preferences,
                      onChanged: (selection) => runSettingsWrite(
                        'Could not change the default agent.',
                        () async {
                          final settings = await ref.read(
                            agentProviderSettingsRepositoryProvider(
                              widget.hostId,
                            ).future,
                          );
                          await AgentProviderSettingsActions(
                            settings,
                            _remoteHostId,
                          ).setDefaultSelection(preferences, selection);
                          ref.invalidate(
                            agentChatPreferencesProvider(
                              widget.hostId,
                              _remoteHostId,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (preferences != null && _remoteHostId == null)
                    AgentProviderProjectDefaults(
                      projects: projects,
                      providers: providers,
                      preferences: preferences,
                      onChanged: (projectId, selection) => runSettingsWrite(
                        'Could not change the project default.',
                        () async {
                          final settings = await ref.read(
                            agentProviderSettingsRepositoryProvider(
                              widget.hostId,
                            ).future,
                          );
                          await AgentProviderSettingsActions(
                            settings,
                            _remoteHostId,
                          ).setProjectDefault(
                            preferences,
                            projectId,
                            selection,
                          );
                          ref.invalidate(
                            agentChatPreferencesProvider(
                              widget.hostId,
                              _remoteHostId,
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: AleraTokens.spaceXl),
                  Text(
                    'Agents',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AleraTokens.spaceSm),
                  Card(
                    child: Column(
                      children: <Widget>[
                        for (final instance in providers)
                          _ProviderRow(
                            instance: instance,
                            checking: _refreshing,
                            editable: snapshot != null,
                            onEnabled: (enabled) => runSettingsWrite(
                              'Could not change the agent.',
                              () => _setEnabled(snapshot!, instance, enabled),
                            ),
                            onOpen: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => AgentProviderDetailScreen(
                                  hostId: widget.hostId,
                                  remoteHostId: _remoteHostId,
                                  instanceId: instance.id,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _setEnabled(
    AgentChatProviderSettingsSnapshot snapshot,
    AgentChatProviderInstance instance,
    bool enabled,
  ) async {
    final settings = await ref.read(
      agentProviderSettingsRepositoryProvider(widget.hostId).future,
    );
    await AgentProviderSettingsActions(
      settings,
      _remoteHostId,
    ).setEnabled(snapshot, instance.id, enabled: enabled);
    ref
      ..invalidate(agentProviderInstancesProvider(widget.hostId, _remoteHostId))
      ..invalidate(_catalog);
  }
}

class const _DefaultForNewChats({
  required final List<AgentChatProviderInstance> providers,
  required final AgentChatPreferences preferences,
  required final Future<void> Function(AgentChatSelection? selection) onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final current = preferences.defaultSelection;
    AgentChatProviderInstance? instance;
    for (final candidate in providers) {
      if (candidate.id == current?.providerInstanceId) instance = candidate;
    }
    final label = current == null
        ? 'Remembered from the last new chat'
        : <String>[
            instance?.label ?? current.providerInstanceId,
            if (current.model case final model?)
              instance?.modelById(model)?.label ?? model,
          ].join(' · ');
    return Card(
      child: ListTile(
        leading: const Icon(AleraIcons.agent),
        title: const Text('Default For New Chats'),
        subtitle: Text(label, overflow: .ellipsis),
        trailing: current == null
            ? const Icon(AleraIcons.chevronRight)
            : IconButton(
                tooltip: 'Clear Default',
                onPressed: () => unawaited(onChanged(null)),
                icon: const Icon(AleraIcons.close),
              ),
        onTap: () async {
          final picked = await showAgentChatModelPicker(
            context,
            providers: providers,
            preferences: preferences,
            current: current,
            canSwitchProvider: true,
          );
          if (picked != null) await onChanged(picked);
        },
      ),
    );
  }
}

class const _ProviderRow({
  required final AgentChatProviderInstance instance,
  required final bool checking,
  required final bool editable,
  required final ValueChanged<bool> onEnabled,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = agentProviderStatusOf(instance, checking: checking);
    final version = instance.version;
    return ListTile(
      minTileHeight: AleraTokens.minTapTarget,
      leading: AgentIdentityIcon(
        agentType: agentChatAgentType(instance.provider),
        size: AleraTokens.space20,
        showTooltip: false,
      ),
      title: Text(instance.label, overflow: .ellipsis),
      subtitle: Text(
        <String>[status.label, ?version].join(' · '),
        style: TextStyle(
          color: status.healthy || status == AgentProviderStatus.off
              ? AleraTokens.foregroundMuted
              : AleraTokens.warning,
        ),
      ),
      trailing: Switch(
        value: instance.enabled,
        onChanged: editable ? onEnabled : null,
      ),
      onTap: onOpen,
    );
  }
}
