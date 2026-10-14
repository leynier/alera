import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_provider_model_picker.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Called with the agent and model picked and the label the chip shows for
/// it until the runtime reports the change.
typedef AgentChatChooseCallback = void Function(
  AgentChatSelection pick,
  String label,
);

/// What a compact chip reads for the provider default, where the full label
/// would push the composer's mode controls out of a narrow panel.
const String agentChatCompactProviderDefaultLabel = 'Default';

/// The model id shown under a picker row, or `null` when there is none or it
/// only repeats the label in another case or with other separators (the id
/// `gpt-6-sol` under `GPT-6-Sol`). Callers keep the id in the row's keywords
/// so it stays searchable.
String? agentChatModelSubtitle(AgentChatModelOption model) {
  final id = model.id;
  if (id == null) return null;
  List<String> words(String text) => <String>[
    for (final word in text.toLowerCase().split(RegExp('[^a-z0-9]+')))
      if (word.isNotEmpty) word,
  ];
  final idWords = words(id);
  final labelWords = words(model.label);
  if (idWords.isEmpty || idWords.length != labelWords.length) return id;
  for (var i = 0; i < idWords.length; i++) {
    if (idWords[i] != labelWords[i]) return id;
  }
  return null;
}

/// The rows of the agent and model picker: one section per agent, one row
/// per model, as the shared package groups them for desktop and phone.
List<AleraPickerSection<AgentChatSelection>> agentChatPickerSections(
  AgentChatComposerSettings settings,
) => <AleraPickerSection<AgentChatSelection>>[
  for (final group in agentChatPickerGroups(
    providers: settings.providers,
    preferences: settings.preferences,
    currentSelection: settings.currentSelection,
    canSwitchProvider: settings.canSwitchProvider,
    switchDisabledReason: settings.switchBlockedReason,
  ))
    AleraPickerSection<AgentChatSelection>(
      title: group.instance.label,
      rows: <AleraPickerRow<AgentChatSelection>>[
        for (final row in group.rows)
          AleraPickerRow<AgentChatSelection>(
            value: row.selection,
            title: row.model.label,
            subtitle: agentChatModelSubtitle(row.model),
            leading: AgentChatProviderIcon(
              provider: group.instance.provider,
              size: AleraTokens.iconMd,
            ),
            disabledReason: row.enabled
                ? null
                : row.disabledReason ?? agentChatSwitchBusyReason,
            keywords: <String>[
              '${group.instance.label} ${row.model.label} '
                  '${row.model.id ?? ''}',
            ],
          ),
      ],
    ),
];

/// The agent and model chip of the composer. Before the first message any
/// pick applies at once; after it, another agent asks once to hand the
/// conversation over; while a turn runs, other agents are disabled with the
/// reason. A catalog that is loading or failed keeps the chat's own labels on
/// a disabled chip, so the footer does not move.
///
/// A [compact] chip must have a bounded width: its label ellipsizes to fit,
/// the provider default reads [agentChatCompactProviderDefaultLabel] beside
/// the agent's icon, and the tooltip carries the full label.
class const AgentChatComposerModelPicker({
  super.key,
  required final AgentChatComposerSettings settings,
  required final bool enabled,
  required final AgentChatChooseCallback onChoose,
  final bool compact = false,
  final AleraPopoverController? controller,
  final VoidCallback? onRetryCatalog,
  final VoidCallback? onOpenProviderSettings,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final instance = settings.instance;
    final catalog = settings.catalog;
    final unavailable = instance != null && !instance.available
        ? instance.unavailableReason ?? 'This agent is unavailable.'
        : null;
    final label = settings.chipLabel;
    final picker = AleraProviderModelPicker<AgentChatSelection>(
      key: const ValueKey<String>('agent-chat-model-picker'),
      label: compact && label == agentChatProviderDefaultLabel
          ? agentChatCompactProviderDefaultLabel
          : label,
      shrinkLabel: compact,
      leading: settings.hasSelection
          ? AgentChatProviderIcon(provider: settings.provider)
          : null,
      sections: catalog == AgentChatCatalogState.ready
          ? agentChatPickerSections(settings)
          : const <AleraPickerSection<AgentChatSelection>>[],
      selectedValue: settings.currentSelection,
      controller: controller,
      enabled:
          enabled &&
          !settings.configuring &&
          catalog == AgentChatCatalogState.ready,
      loading: catalog == AgentChatCatalogState.loading,
      tooltip: switch (catalog) {
        AgentChatCatalogState.loading => '$agentChatLoadingAgentsLabel…',
        AgentChatCatalogState.failed => 'Agents could not be loaded.',
        AgentChatCatalogState.ready =>
          unavailable ??
              (settings.pendingModel != null
                  ? 'Applies to your next message'
                  : compact
                  ? '$label · Choose Model'
                  : 'Choose Model'),
      },
      searchHintText: agentChatPickerSearchHint,
      footerActionLabel: onOpenProviderSettings == null
          ? null
          : agentChatOpenProviderSettingsLabel,
      onFooterAction: onOpenProviderSettings,
      onSelected: (pick) => unawaited(_pick(context, pick)),
    );
    final trailing = switch (catalog) {
      AgentChatCatalogState.failed when onRetryCatalog != null =>
        AleraIconButton(
          key: const ValueKey<String>('agent-chat-catalog-retry'),
          tooltip: agentChatTryAgainLabel,
          icon: AleraIcons.refresh,
          iconSize: AleraTokens.iconSm,
          minSize: AleraTokens.iconButtonSm,
          onPressed: onRetryCatalog,
        ),
      AgentChatCatalogState.ready
          when unavailable != null && onOpenProviderSettings != null =>
        AleraIconButton(
          key: const ValueKey<String>('agent-chat-provider-settings'),
          tooltip: agentChatOpenProviderSettingsLabel,
          icon: AleraIcons.settings,
          iconSize: AleraTokens.iconSm,
          minSize: AleraTokens.iconButtonSm,
          onPressed: onOpenProviderSettings,
        ),
      _ => null,
    };
    if (trailing == null) return picker;
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (compact) Flexible(child: picker) else picker,
        trailing,
      ],
    );
  }

  Future<void> _pick(BuildContext context, AgentChatSelection pick) async {
    final target = settings.providers
        .where((instance) => instance.id == pick.providerInstanceId)
        .firstOrNull;
    if (target == null) return;
    final label = agentChatModelLabel(target, pick.model);
    final decision = agentChatPickDecision(
      neverSent: settings.neverSent || !settings.hasSelection,
      switchesProvider: target.id != settings.providerInstanceId,
      canSwitchProvider: settings.canSwitchProvider,
    );
    switch (decision) {
      case AgentChatPickDecision.blocked:
        return;
      case AgentChatPickDecision.confirmHandoff:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AleraConfirmDialog(
            title: agentChatSwitchAgentTitle(target.label),
            message: agentChatSwitchAgentMessage(target.label),
            confirmLabel: agentChatSwitchAgentConfirm,
          ),
        );
        if (confirmed != true) return;
        onChoose(pick, label);
      case AgentChatPickDecision.apply:
        onChoose(pick, label);
    }
  }
}
