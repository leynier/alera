import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

/// Picks the agent and model for a chat in one list: a section per agent, a
/// row per model, searchable by either name. An agent that cannot run shows
/// why on its rows; Open Provider Settings fixes that from here. Returns the
/// picked selection, or null when dismissed.
Future<AgentChatSelection?> showAgentChatModelPicker(
  BuildContext context, {
  required List<AgentChatProviderInstance> providers,
  required AgentChatPreferences preferences,
  required AgentChatSelection? current,
  required bool canSwitchProvider,
  VoidCallback? onOpenProviderSettings,
}) => showModalBottomSheet<AgentChatSelection>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: AgentChatModelPickerPanel(
        providers: providers,
        preferences: preferences,
        current: current,
        canSwitchProvider: canSwitchProvider,
        onPicked: (selection) => Navigator.of(context).pop(selection),
        onOpenProviderSettings: onOpenProviderSettings == null
            ? null
            : () {
                Navigator.of(context).pop();
                onOpenProviderSettings();
              },
      ),
    ),
  ),
);

class const AgentChatModelPickerPanel({
  super.key,
  required final List<AgentChatProviderInstance> providers,
  required final AgentChatPreferences preferences,
  required final AgentChatSelection? current,
  required final bool canSwitchProvider,
  required final ValueChanged<AgentChatSelection> onPicked,
  final VoidCallback? onOpenProviderSettings,
}) extends StatefulWidget {
  @override
  State<AgentChatModelPickerPanel> createState() =>
      _AgentChatModelPickerPanelState();
}

class _AgentChatModelPickerPanelState extends State<AgentChatModelPickerPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final groups = agentChatPickerGroups(
      providers: widget.providers,
      preferences: widget.preferences,
      currentSelection: widget.current,
      query: _query,
      canSwitchProvider: widget.canSwitchProvider,
      switchDisabledReason: agentChatSwitchBusyReason,
    );
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            0,
            AleraTokens.space16,
            AleraTokens.space8,
          ),
          child: AleraSearchField(
            hintText: agentChatPickerSearchHint,
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        Flexible(
          child: groups.isEmpty
              ? AleraEmptyState(
                  icon: _query.isEmpty ? AleraIcons.agent : AleraIcons.search,
                  title: _query.isEmpty ? agentChatNoAgentLabel : null,
                  message: _query.isEmpty
                      ? 'Enable or install an agent on the host to chat.'
                      : 'No agent or model matches "$_query".',
                )
              : ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final group in groups) ..._group(context, group),
                  ],
                ),
        ),
        if (widget.onOpenProviderSettings case final open?) ...<Widget>[
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: open,
                icon: const Icon(AleraIcons.settings),
                label: const Text(agentChatOpenProviderSettingsLabel),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _group(BuildContext context, AgentChatPickerGroup group) {
    final instance = group.instance;
    final reason = !instance.enabled
        ? 'Off on this host'
        : instance.available
        ? null
        : instance.unavailableReason;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space12,
          AleraTokens.space16,
          AleraTokens.space4,
        ),
        child: Row(
          children: <Widget>[
            AgentIdentityIcon(
              agentType: agentChatAgentType(instance.provider),
              size: AleraTokens.space16,
              showTooltip: false,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                instance.label,
                style: Theme.of(context).textTheme.labelLarge,
                overflow: .ellipsis,
              ),
            ),
            if (reason != null)
              Flexible(
                child: Text(
                  reason,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                  overflow: .ellipsis,
                  textAlign: .end,
                ),
              ),
          ],
        ),
      ),
      for (final row in group.rows)
        AleraActiveRail(
          active: row.selected,
          child: ListTile(
            key: ValueKey<String>(
              'picker-${instance.id}-${row.model.id ?? ''}',
            ),
            minTileHeight: AleraTokens.minTapTarget,
            selected: row.selected,
            selectedTileColor: AleraActiveRail.selectedColor,
            enabled: row.enabled,
            title: Text(row.model.label, overflow: .ellipsis),
            subtitle: row.enabled || row.disabledReason == null
                ? null
                : Text(row.disabledReason!, overflow: .ellipsis),
            trailing: row.selected
                ? const Icon(AleraIcons.check, size: AleraTokens.space16)
                : null,
            onTap: row.selected ? null : () => widget.onPicked(row.selection),
          ),
        ),
    ];
  }
}
