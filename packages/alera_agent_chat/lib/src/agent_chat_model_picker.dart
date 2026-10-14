import 'package:alera_agent_chat/src/agent_chat_composer_labels.dart';
import 'package:alera_agent_chat/src/agent_chat_preferences.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_selection.dart';

class const AgentChatPickerRow({
  required final AgentChatProviderInstance instance,
  required final AgentChatModelOption model,
  required final AgentChatSelection selection,
  final bool selected = false,
  final bool enabled = true,
  final String? disabledReason,
});

class const AgentChatPickerGroup({
  required final AgentChatProviderInstance instance,
  required final List<AgentChatPickerRow> rows,
});

/// The same grouped picker for desktop and phone. Search matches every word,
/// and hidden current models stay reachable even after catalog refreshes.
List<AgentChatPickerGroup> agentChatPickerGroups({
  required List<AgentChatProviderInstance> providers,
  AgentChatPreferences preferences = const AgentChatPreferences(),
  AgentChatSelection? currentSelection,
  String query = '',
  bool canSwitchProvider = true,
  String? switchDisabledReason,
}) {
  final terms = query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  final groups = <AgentChatPickerGroup>[];
  for (final instance in providers) {
    if (!instance.enabled &&
        instance.id != currentSelection?.providerInstanceId)
      continue;
    final isCurrentProvider =
        instance.id == currentSelection?.providerInstanceId;
    final modelPreferences =
        preferences.models[instance.id] ?? const AgentChatModelPreferences();
    final hidden = modelPreferences.hidden.toSet();
    final ranks = <String, int>{
      for (var i = 0; i < modelPreferences.order.length; i++)
        modelPreferences.order[i]: i,
    };
    final options = <AgentChatModelOption>[
      ...instance.models,
      if (!instance.models.any((model) => model.id == null))
        const AgentChatModelOption(
          id: null,
          label: agentChatProviderDefaultLabel,
          isDefault: true,
        ),
      if (isCurrentProvider &&
          currentSelection?.model != null &&
          instance.modelById(currentSelection!.model) == null)
        AgentChatModelOption(
          id: currentSelection.model,
          label: currentSelection.model!,
        ),
    ];
    final originalOrder = <AgentChatModelOption, int>{
      for (var i = 0; i < options.length; i++) options[i]: i,
    };
    options.sort((left, right) {
      final leftRank = ranks[left.id] ?? ranks.length + originalOrder[left]!;
      final rightRank = ranks[right.id] ?? ranks.length + originalOrder[right]!;
      return leftRank.compareTo(rightRank);
    });
    final rows = <AgentChatPickerRow>[];
    final seen = <String?>{};
    for (final model in options) {
      if (!seen.add(model.id)) continue;
      final selected = isCurrentProvider && currentSelection?.model == model.id;
      if (hidden.contains(model.id) && !selected) continue;
      final searchable =
          '${instance.label} ${instance.provider} ${instance.id} ${model.label} ${model.id ?? ''}'
              .toLowerCase();
      if (!terms.every(searchable.contains)) continue;
      final canSwitch = isCurrentProvider || canSwitchProvider;
      rows.add(
        AgentChatPickerRow(
          instance: instance,
          model: model,
          selection: AgentChatSelection(
            providerInstanceId: instance.id,
            model: model.id,
          ),
          selected: selected,
          enabled: instance.enabled && instance.available && canSwitch,
          disabledReason: !instance.enabled
              ? 'This provider is disabled.'
              : !instance.available
              ? instance.unavailableReason ?? 'This provider is unavailable.'
              : !canSwitch
              ? switchDisabledReason ?? agentChatSwitchBusyReason
              : null,
        ),
      );
    }
    if (rows.isNotEmpty)
      groups.add(
        AgentChatPickerGroup(
          instance: instance,
          rows: List.unmodifiableOf(rows),
        ),
      );
  }
  return List.unmodifiableOf(groups);
}
