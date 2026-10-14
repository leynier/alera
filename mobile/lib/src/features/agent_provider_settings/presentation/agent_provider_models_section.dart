import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Above this many models the section offers a filter.
const int _filterThreshold = 6;

enum _ModelAction { toggleHidden, moveUp, moveDown, makeDefault, remove }

/// The models an agent offers in the composer picker: where the list came
/// from, which are hidden from the picker and in what order, the instance's
/// default model, and model ids added by hand. The provider default row is
/// always shown, because a chat can always fall back to it.
class const AgentProviderModelsSection({
  super.key,
  required final AgentChatProviderInstance instance,
  required final AgentChatProviderInstanceEnvelope? envelope,
  required final AgentChatPreferences? preferences,
  required final Future<void> Function(String? model)? onDefaultModel,
  required final Future<void> Function(List<String> models)? onCustomModels,
  required final Future<void> Function(AgentChatModelPreferences models)?
  onModelPreferences,
}) extends StatefulWidget {
  @override
  State<AgentProviderModelsSection> createState() =>
      _AgentProviderModelsSectionState();
}

class _AgentProviderModelsSectionState
    extends State<AgentProviderModelsSection> {
  String _query = '';

  AgentChatModelPreferences get _models =>
      widget.preferences?.models[widget.instance.id] ??
      const AgentChatModelPreferences();

  /// Model ids in picker order: the saved order first, then the rest as the
  /// catalog lists them.
  List<String> get _ordered {
    final ids = <String>[for (final model in widget.instance.models) ?model.id];
    final saved = <String>[
      for (final id in _models.order)
        if (ids.contains(id)) id,
    ];
    return <String>[
      ...saved,
      for (final id in ids)
        if (!saved.contains(id)) id,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instance = widget.instance;
    final hidden = _models.hidden.toSet();
    final ordered = _ordered;
    final byId = <String, AgentChatModelOption>{
      for (final model in instance.models) ?model.id: model,
    };
    final terms = _query.toLowerCase().trim();
    final visible = <String>[
      for (final id in ordered)
        if (terms.isEmpty ||
            id.toLowerCase().contains(terms) ||
            (byId[id]?.label.toLowerCase().contains(terms) ?? false))
          id,
    ];
    final custom = widget.envelope?.customModels ?? const <String>[];
    final defaultModel = widget.envelope?.defaultModel ?? instance.defaultModel;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text('Models', style: theme.textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Text(
          '${agentChatModelsSourceLabel(instance.modelsSource)} · '
          '${ordered.length - hidden.length} shown · ${hidden.length} hidden',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        if (ordered.length > _filterThreshold) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          AleraSearchField(
            hintText: 'Filter models',
            dense: true,
            onChanged: (query) => setState(() => _query = query),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                title: const Text(agentChatProviderDefaultLabel),
                subtitle: const Text('Whatever the agent itself picks.'),
                trailing: defaultModel == null
                    ? const Icon(AleraIcons.check)
                    : TextButton(
                        onPressed: widget.onDefaultModel == null
                            ? null
                            : () => unawaited(widget.onDefaultModel!(null)),
                        child: const Text('Use As Default'),
                      ),
              ),
              for (final id in visible)
                _row(
                  id,
                  byId[id],
                  hidden: hidden.contains(id),
                  isDefault: id == defaultModel,
                  isCustom: custom.contains(id),
                  index: ordered.indexOf(id),
                  count: ordered.length,
                ),
            ],
          ),
        ),
        if (widget.onCustomModels != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(_addCustom(custom)),
              icon: const Icon(AleraIcons.add),
              label: const Text('Add Custom Model'),
            ),
          ),
      ],
    );
  }

  Widget _row(
    String id,
    AgentChatModelOption? model, {
    required bool hidden,
    required bool isDefault,
    required bool isCustom,
    required int index,
    required int count,
  }) {
    final label = model?.label ?? id;
    final canOrder = widget.onModelPreferences != null;
    return ListTile(
      key: ValueKey<String>('model-$id'),
      leading: Icon(
        hidden ? AleraIcons.hidden : AleraIcons.visible,
        color: hidden
            ? AleraTokens.foregroundFaint
            : AleraTokens.foregroundMuted,
      ),
      title: Text(
        label,
        overflow: .ellipsis,
        style: hidden
            ? const TextStyle(color: AleraTokens.foregroundMuted)
            : null,
      ),
      subtitle: Text(
        <String>[
          if (label != id) id,
          if (isDefault) 'Default',
          if (isCustom) 'Custom',
          if (hidden) 'Hidden From Picker',
        ].join(' · '),
        style: AleraTokens.monoStyle,
        overflow: .ellipsis,
      ),
      trailing: PopupMenuButton<_ModelAction>(
        tooltip: 'Model Actions',
        icon: const Icon(AleraIcons.more),
        onSelected: (action) => unawaited(_act(action, id, index)),
        itemBuilder: (context) => <PopupMenuEntry<_ModelAction>>[
          if (canOrder)
            PopupMenuItem<_ModelAction>(
              value: _ModelAction.toggleHidden,
              height: AleraTokens.minTapTarget,
              child: Text(hidden ? 'Show In Picker' : 'Hide From Picker'),
            ),
          if (canOrder && index > 0)
            const PopupMenuItem<_ModelAction>(
              value: _ModelAction.moveUp,
              height: AleraTokens.minTapTarget,
              child: Text('Move Up'),
            ),
          if (canOrder && index < count - 1)
            const PopupMenuItem<_ModelAction>(
              value: _ModelAction.moveDown,
              height: AleraTokens.minTapTarget,
              child: Text('Move Down'),
            ),
          if (widget.onDefaultModel != null && !isDefault)
            const PopupMenuItem<_ModelAction>(
              value: _ModelAction.makeDefault,
              height: AleraTokens.minTapTarget,
              child: Text('Use As Default'),
            ),
          if (widget.onCustomModels != null && isCustom)
            const PopupMenuItem<_ModelAction>(
              value: _ModelAction.remove,
              height: AleraTokens.minTapTarget,
              child: Text('Remove Custom Model'),
            ),
        ],
      ),
    );
  }

  Future<void> _act(_ModelAction action, String id, int index) async {
    final ordered = _ordered;
    switch (action) {
      case _ModelAction.toggleHidden:
        final hidden = _models.hidden.toSet();
        if (!hidden.remove(id)) hidden.add(id);
        await widget.onModelPreferences?.call(
          AgentChatModelPreferences(
            hidden: List.unmodifiableOf(hidden),
            order: _models.order,
          ),
        );
      case _ModelAction.moveUp || _ModelAction.moveDown:
        final target = action == _ModelAction.moveUp ? index - 1 : index + 1;
        final order = List<String>.of(ordered)
          ..[index] = ordered[target]
          ..[target] = id;
        await widget.onModelPreferences?.call(
          AgentChatModelPreferences(
            hidden: _models.hidden,
            order: List.unmodifiableOf(order),
          ),
        );
      case _ModelAction.makeDefault:
        await widget.onDefaultModel?.call(id);
      case _ModelAction.remove:
        await widget.onCustomModels?.call(<String>[
          for (final model in widget.envelope?.customModels ?? const <String>[])
            if (model != id) model,
        ]);
    }
  }

  Future<void> _addCustom(List<String> custom) async {
    final id = await showDialog<String>(
      context: context,
      builder: (context) => const AleraRenameDialog(
        title: 'Add Custom Model',
        labelText: 'Model ID',
        helperText: 'Exactly as the agent names it, for example gpt-5.',
        confirmLabel: 'Add',
      ),
    );
    final trimmed = id?.trim() ?? '';
    if (trimmed.isEmpty || custom.contains(trimmed)) return;
    await widget.onCustomModels?.call(<String>[...custom, trimmed]);
  }
}
