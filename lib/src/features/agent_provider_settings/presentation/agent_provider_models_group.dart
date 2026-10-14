import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_model_rows.dart';
import 'package:flutter/material.dart';

/// The Models list of one instance: where the list came from, search, and
/// per-model visibility, order, favorites, default, and custom ids.
///
/// Visibility, order and favorites are host preferences and apply at once;
/// the default model and custom ids belong to the launch definition and wait
/// for Save.
class const AgentProviderModelsGroup({
  super.key,
  required final AgentProviderModelList models,
  required final String sourceLabel,
  required final String query,
  required final ValueChanged<String> onQueryChanged,
  required final bool preferencesEditable,
  required final bool launchEditable,
  required final void Function(String id, bool hidden) onSetHidden,
  required final void Function(String? id, bool favorite) onSetFavorite,
  required final void Function(String id, int delta) onMove,
  required final ValueChanged<String?> onMakeDefault,
  required final ValueChanged<String> onAddCustom,
  required final ValueChanged<String> onRemoveCustom,
  final String? preferencesUnavailableReason,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = models.hiddenCount == 0
        ? '${models.total} in picker'
        : '${models.visibleCount} of ${models.total} in picker, '
              '${models.hiddenCount} hidden';
    final rows = models.rows;
    return AleraSettingsGroup(
      title: 'Models',
      description: '$sourceLabel. $counts.',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              AleraSearchField(
                hintText: 'Filter models',
                dense: true,
                onChanged: onQueryChanged,
              ),
              if (preferencesUnavailableReason case final reason?) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                Text(
                  reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text(
              query.isEmpty
                  ? 'This host lists no models for the provider.'
                  : 'No models match "$query".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        for (var index = 0; index < rows.length; index++)
          _ModelRow(
            key: ValueKey<String>('model-${rows[index].id ?? '<default>'}'),
            row: rows[index],
            first: rows[index].id == models.firstMovableId,
            last: rows[index].id == models.lastMovableId,
            preferencesEditable: preferencesEditable,
            launchEditable: launchEditable,
            orderable: query.isEmpty,
            onSetHidden: onSetHidden,
            onSetFavorite: onSetFavorite,
            onMove: onMove,
            onMakeDefault: onMakeDefault,
            onRemoveCustom: onRemoveCustom,
          ),
        _AddCustomModel(enabled: launchEditable, onAdd: onAddCustom),
      ],
    );
  }
}

class const _ModelRow({
  super.key,
  required final AgentProviderModelRow row,
  required final bool first,
  required final bool last,
  required final bool preferencesEditable,
  required final bool launchEditable,
  required final bool orderable,
  required final void Function(String id, bool hidden) onSetHidden,
  required final void Function(String? id, bool favorite) onSetFavorite,
  required final void Function(String id, int delta) onMove,
  required final ValueChanged<String?> onMakeDefault,
  required final ValueChanged<String> onRemoveCustom,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = row.id;
    final dimmed = row.hidden;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      child: Row(
        children: <Widget>[
          AleraIconButton(
            tooltip: row.favorite
                ? 'Remove From Favorites'
                : 'Add To Favorites',
            icon: AleraIcons.star,
            iconColor: row.favorite
                ? AleraTokens.accent
                : AleraTokens.foregroundFaint,
            onPressed: preferencesEditable
                ? () => onSetFavorite(id, !row.favorite)
                : null,
          ),
          const SizedBox(width: AleraTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(
                  row.label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: dimmed
                        ? AleraTokens.foregroundFaint
                        : AleraTokens.foreground,
                  ),
                ),
                if (id != null && id != row.label)
                  Text(
                    id,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: AleraTokens.monoCompactStyle,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (row.isDefault) ...<Widget>[
            const AleraBadge(label: 'Default', tone: .accent),
            const SizedBox(width: AleraTokens.space6),
          ],
          AleraBadge(label: row.source.label),
          const SizedBox(width: AleraTokens.space8),
          if (id != null && orderable) ...<Widget>[
            AleraIconButton(
              tooltip: 'Move Up',
              icon: AleraIcons.arrowUp,
              onPressed: preferencesEditable && !first
                  ? () => onMove(id, -1)
                  : null,
            ),
            AleraIconButton(
              tooltip: 'Move Down',
              icon: AleraIcons.arrowDown,
              onPressed: preferencesEditable && !last
                  ? () => onMove(id, 1)
                  : null,
            ),
          ],
          if (row.canHide)
            AleraIconButton(
              tooltip: row.hidden ? 'Show In Picker' : 'Hide From Picker',
              icon: row.hidden ? AleraIcons.hidden : AleraIcons.visible,
              onPressed: preferencesEditable
                  ? () => onSetHidden(id!, !row.hidden)
                  : null,
            ),
          PopupMenuButton<_ModelAction>(
            tooltip: 'More Model Actions',
            icon: const Icon(AleraIcons.more, size: AleraTokens.iconLg),
            enabled: launchEditable,
            onSelected: (action) {
              switch (action) {
                case _ModelAction.makeDefault:
                  onMakeDefault(id);
                case _ModelAction.removeCustom:
                  onRemoveCustom(id!);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_ModelAction>>[
              AleraDropdownEntry<_ModelAction>(
                value: _ModelAction.makeDefault,
                label: 'Use As Instance Default',
                detail:
                    'Chats on this provider start with it unless a '
                    'chat picks another model.',
                enabled: !row.isDefault,
              ),
              if (row.source == AgentProviderModelSource.custom)
                const AleraDropdownEntry<_ModelAction>(
                  value: _ModelAction.removeCustom,
                  label: 'Remove Custom Model',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ModelAction { makeDefault, removeCustom }

class const _AddCustomModel({
  required final bool enabled,
  required final ValueChanged<String> onAdd,
}) extends StatefulWidget {
  @override
  State<_AddCustomModel> createState() => _AddCustomModelState();
}

class _AddCustomModelState extends State<_AddCustomModel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final id = _controller.text.trim();
    if (id.isEmpty) {
      return;
    }
    widget.onAdd(id);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AleraTextField(
              controller: _controller,
              hintText: 'Custom model id, such as gpt-5.6-sol',
              dense: true,
              enabled: widget.enabled,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => OutlinedButton.icon(
              onPressed: widget.enabled && _controller.text.trim().isNotEmpty
                  ? _add
                  : null,
              icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
              label: const Text('Add Custom Model'),
            ),
          ),
        ],
      ),
    );
  }
}
