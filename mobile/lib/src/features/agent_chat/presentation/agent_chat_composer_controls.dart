import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_model_picker_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_settings_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_usage_button.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The instance a chat runs on, from the catalog when it has loaded.
AgentChatProviderInstance? agentChatInstanceOf(
  List<AgentChatProviderInstance>? providers,
  AgentChatViewState view,
) {
  final id = view.selection?.providerInstanceId;
  for (final instance in providers ?? const <AgentChatProviderInstance>[]) {
    if (instance.id == id) return instance;
  }
  return null;
}

/// What the chip says: the model, or the agent when it uses its default.
String agentChatSelectionLabel(
  AgentChatViewState view,
  AgentChatProviderInstance? instance,
) {
  final selection = view.selection;
  if (selection == null) return agentChatNoAgentLabel;
  final agent =
      instance?.label ??
      agentChatProviderName(
        view.thread.provider.isEmpty
            ? selection.providerInstanceId
            : view.thread.provider,
      );
  final model = selection.model;
  final base = model == null
      ? agent
      : instance?.modelById(model)?.label ?? model;
  return view.session.interactionMode == AgentChatInteractionMode.plan
      ? '$base · Plan'
      : base;
}

/// The composer's agent and model chip, the chat settings button and the
/// context ring. Picking under another agent before the first message just
/// switches; with history it asks once, because the conversation is handed
/// over; while the chat is busy other agents are shown but not pickable.
class const AgentChatComposerControls({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String? remoteHostId,
  required final AgentChatViewState view,
  required final bool enabled,
  required final Future<void> Function(AgentChatSelection selection) onSelect,
  required final Future<void> Function(AgentChatConfiguration configuration)
  onConfigure,
  required final VoidCallback onOpenProviderSettings,
  final Future<void> Function(bool enabled)? onFileCheckpointing,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogProvider = agentChatProvidersProvider(hostId, workspaceId);
    final catalog = ref.watch(catalogProvider);
    final providers = catalog.value;
    final instance = agentChatInstanceOf(providers, view);
    final loading = providers == null && catalog.isLoading;
    final failed = providers == null && catalog.hasError;
    final label = agentChatSelectionLabel(view, instance);
    final unready =
        view.unselected ||
        (instance != null && (!instance.enabled || !instance.available));
    final effort =
        ref
            .watch(
              agentChatCapabilityProvider(
                hostId,
                AgentChatWire.effortCapability,
              ),
            )
            .value ??
        false;
    final model = instance?.modelById(view.selection?.model);
    final checkpoints =
        view.session.capabilities.nativeHistory.fileCheckpointing &&
        (ref
                .watch(
                  agentChatCapabilityProvider(
                    hostId,
                    AgentChatWire.fileCheckpointsCapability,
                  ),
                )
                .value ??
            false);
    final tunable =
        checkpoints ||
        (instance != null &&
            (instance.runtimeModes.length > 1 ||
                instance.supportsPlanMode ||
                (effort && (model?.reasoningEfforts.isNotEmpty ?? false))));
    final chip = TextButton.icon(
      key: const Key('agent-chat-model-chip'),
      onPressed: !enabled
          ? null
          : providers != null
          ? () => unawaited(_pick(context, ref, providers))
          : failed
          ? () => ref.invalidate(catalogProvider)
          : null,
      icon: view.selection == null
          ? const Icon(AleraIcons.agent)
          : AgentIdentityIcon(
              agentType: agentChatAgentType(
                instance?.provider ?? view.thread.provider,
              ),
              size: AleraTokens.space16,
              color: unready
                  ? AleraTokens.warning
                  : AleraTokens.foregroundMuted,
              showTooltip: false,
            ),
      label: Text(label, overflow: .ellipsis),
    );
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        Flexible(
          // A failed catalog turns the chip into its own Try Again, so the
          // row never grows a control the phone has no room for.
          child: switch (loading
              ? agentChatLoadingAgentsLabel
              : failed
              ? agentChatTryAgainLabel
              : null) {
            final String hint => Tooltip(message: hint, child: chip),
            null => chip,
          },
        ),
        if (tunable)
          IconButton(
            tooltip: 'Chat Settings',
            visualDensity: .compact,
            onPressed: enabled
                ? () => unawaited(
                    showAgentChatSettingsSheet(
                      context,
                      current: AgentChatSettingsCurrent(
                        runtimeMode: view.session.runtimeMode,
                        interactionMode: view.session.interactionMode,
                        instance: instance,
                        model: model,
                        reasoningEffort: view.session.reasoningEffort,
                        effortSupported: effort,
                        fileCheckpointing: checkpoints
                            ? view.session.fileCheckpointing
                            : null,
                        canChangeFileCheckpointing: view.canSwitchProvider,
                      ),
                      onConfigure: onConfigure,
                      onFileCheckpointing: onFileCheckpointing,
                    ),
                  )
                : null,
            icon: const Icon(AleraIcons.tune),
          ),
        AgentChatUsageButton(usage: view.thread.usage),
      ],
    );
  }

  /// What the composer's `/` commands can do in this chat right now: the
  /// model picker and mode commands follow this chip and its settings, and
  /// `/usage` the usage ring.
  AgentChatSlashCommandState slashCommandState(WidgetRef ref) {
    final catalog = ref.read(agentChatProvidersProvider(hostId, workspaceId));
    final providers = catalog.value;
    final usage = view.thread.usage;
    return AgentChatSlashCommandState(
      modelPickerAvailable: enabled && providers != null,
      modelPickerBlockedReason: providers != null
          ? null
          : catalog.hasError
          ? 'The agents could not be loaded.'
          : 'The agents are still loading.',
      planModeSupported:
          agentChatInstanceOf(providers, view)?.supportsPlanMode ?? false,
      interactionMode: view.session.interactionMode,
      usageAvailable: usage.contextFraction != null || usage.windows.isNotEmpty,
      providerCommands: view.session.commands,
    );
  }

  /// Runs a local `/` command picked in the composer, through the same
  /// picker, settings and sheet as the controls themselves.
  Future<void> runSlashCommand(
    BuildContext context,
    WidgetRef ref,
    AgentChatSlashCommand command,
  ) async {
    switch (command) {
      case AgentChatSlashCommand.model:
        final providers = ref
            .read(agentChatProvidersProvider(hostId, workspaceId))
            .value;
        if (providers != null) await _pick(context, ref, providers);
      case AgentChatSlashCommand.plan || AgentChatSlashCommand.standard:
        await onConfigure(
          AgentChatConfiguration(
            interactionMode: agentChatSlashCommandInteractionMode(command),
          ),
        );
      case AgentChatSlashCommand.usage:
        await showAgentChatUsageSheet(context, view.thread.usage);
    }
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    List<AgentChatProviderInstance> providers,
  ) async {
    final preferences =
        ref.read(agentChatPreferencesProvider(hostId, remoteHostId)).value ??
        const AgentChatPreferences();
    final current = view.selection;
    final picked = await showAgentChatModelPicker(
      context,
      providers: providers,
      preferences: preferences,
      current: current,
      canSwitchProvider: view.canSwitchProvider,
      onOpenProviderSettings: onOpenProviderSettings,
    );
    if (picked == null || picked == current || !context.mounted) return;
    final switching =
        current == null ||
        picked.providerInstanceId != current.providerInstanceId;
    switch (agentChatPickDecision(
      neverSent: view.neverSent || view.unselected,
      switchesProvider: switching,
      canSwitchProvider: view.canSwitchProvider,
    )) {
      case AgentChatPickDecision.blocked:
        return;
      case AgentChatPickDecision.confirmHandoff:
        final name =
            _labelOf(providers, picked.providerInstanceId) ??
            agentChatProviderName(picked.providerInstanceId);
        if (!await confirmAgentChatSwitch(context, name)) return;
      case AgentChatPickDecision.apply:
        break;
    }
    await onSelect(picked);
  }

  String? _labelOf(List<AgentChatProviderInstance> providers, String id) {
    for (final instance in providers) {
      if (instance.id == id) return instance.label;
    }
    return null;
  }
}
