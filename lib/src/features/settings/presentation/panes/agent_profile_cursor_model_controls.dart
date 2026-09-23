import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_profiles/domain/cursor_model_catalog.dart';
import 'package:alera/src/features/agent_profiles/domain/cursor_model_variant.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:flutter/material.dart';

const String _familyPrefix = 'family:';
const String _customPrefix = 'custom:';

/// Model, effort, thinking, and fast rows for a Cursor managed profile.
///
/// The stored value stays `managedConfig.model`. Each control rewrites that
/// field to a slug already present in [models].
List<Widget> cursorManagedModelRows({
  required List<ManagedAgentOption> models,
  required String modelId,
  required bool enabled,
  required bool modelsLoading,
  required VoidCallback? onRefreshModels,
  required ValueChanged<String?> onModelChanged,
}) {
  final catalog = CursorModelCatalog.fromOptions(models);
  final current = catalog.variantForModel(modelId);
  final family = current == null ? null : catalog.familyById(current.family);
  final selectedModel = _modelDropdownValue(modelId, current);
  final modelEntries = <AleraDropdownFieldEntry<String>>[
    const AleraDropdownFieldEntry<String>(value: '', label: 'Agent Default'),
    for (final item in catalog.families)
      AleraDropdownFieldEntry<String>(
        value: '$_familyPrefix${item.id}',
        label: item.label,
      ),
  ];
  if (!modelEntries.any((entry) => entry.value == selectedModel)) {
    modelEntries.add(
      AleraDropdownFieldEntry<String>(
        value: selectedModel,
        label: 'Custom: $modelId',
      ),
    );
  }
  return <Widget>[
    _dropdownRow(
      title: 'Model',
      description: 'Only lists model families Cursor published.',
      value: selectedModel,
      entries: modelEntries,
      enabled: enabled,
      filterable: true,
      filterHintText: 'Search Models',
      trailing: onRefreshModels == null
          ? null
          : AleraIconButton(
              tooltip: 'Refresh Models',
              icon: modelsLoading ? AleraIcons.loading : AleraIcons.refresh,
              onPressed: enabled && !modelsLoading ? onRefreshModels : null,
            ),
      onChanged: (value) => _onFamilyPicked(
        value: value,
        catalog: catalog,
        current: current,
        onModelChanged: onModelChanged,
      ),
    ),
    if (current != null && family != null && family.efforts.isNotEmpty)
      _dropdownRow(
        title: 'Effort',
        description: 'Only lists efforts Cursor published for this model.',
        value: current.effort ?? '',
        entries: <AleraDropdownFieldEntry<String>>[
          if (family.offersBareEffort)
            const AleraDropdownFieldEntry<String>(value: '', label: 'Default'),
          for (final effort in family.efforts)
            AleraDropdownFieldEntry<String>(
              value: effort,
              label: cursorEffortLabel(effort),
            ),
        ],
        enabled: enabled,
        onChanged: (value) {
          final slug = catalog.slugForEffort(
            current.family,
            effort: value.isEmpty ? null : value,
            thinking: current.thinking,
            fast: current.fast,
          );
          if (slug != null) {
            onModelChanged(slug);
          }
        },
      ),
    if (current != null && family != null && family.hasThinking)
      _checkRow(
        title: 'Thinking',
        description: 'Only available when Cursor published a thinking variant for this effort.',
        value: current.thinking,
        enabled: enabled && family.canToggleThinking(current),
        onChanged: (value) {
          final next = family.match(
            effort: current.effort,
            thinking: value,
            fast: current.fast,
          );
          if (next != null) {
            onModelChanged(next.id);
          }
        },
      ),
    if (current != null && family != null && family.hasFast)
      _checkRow(
        title: 'Fast',
        description: 'Only available when Cursor published a fast variant for this effort.',
        value: current.fast,
        enabled: enabled && family.canToggleFast(current),
        onChanged: (value) {
          final next = family.match(
            effort: current.effort,
            thinking: current.thinking,
            fast: value,
          );
          if (next != null) {
            onModelChanged(next.id);
          }
        },
      ),
  ];
}

String _modelDropdownValue(String modelId, CursorModelVariant? current) {
  if (modelId.trim().isEmpty) {
    return '';
  }
  if (current != null) {
    return '$_familyPrefix${current.family}';
  }
  return '$_customPrefix$modelId';
}

void _onFamilyPicked({
  required String value,
  required CursorModelCatalog catalog,
  required CursorModelVariant? current,
  required ValueChanged<String?> onModelChanged,
}) {
  if (value.isEmpty) {
    onModelChanged(null);
    return;
  }
  if (!value.startsWith(_familyPrefix)) {
    return;
  }
  final slug = catalog.slugForFamily(
    value.substring(_familyPrefix.length),
    previous: current,
  );
  if (slug != null) {
    onModelChanged(slug);
  }
}

Widget _dropdownRow({
  required String title,
  required String description,
  required String value,
  required List<AleraDropdownFieldEntry<String>> entries,
  required bool enabled,
  required ValueChanged<String> onChanged,
  bool filterable = false,
  String filterHintText = 'Search',
  Widget? trailing,
}) {
  return AleraSettingRow(
    title: title,
    description: description,
    child: Row(
      children: <Widget>[
        Expanded(
          child: AleraDropdownField<String>(
            key: ValueKey<String>('cursor-$title:$value'),
            value: value,
            entries: entries,
            enabled: enabled,
            filterable: filterable,
            filterHintText: filterHintText,
            onChanged: onChanged,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AleraTokens.space8),
          trailing,
        ],
      ],
    ),
  );
}

Widget _checkRow({
  required String title,
  required String description,
  required bool value,
  required bool enabled,
  required ValueChanged<bool> onChanged,
}) {
  return AleraSettingRow(
    title: title,
    description: description,
    child: Align(
      alignment: Alignment.centerRight,
      child: AleraCheckbox(
        key: ValueKey<String>('cursor-$title:$value'),
        value: value,
        enabled: enabled,
        onChanged: onChanged,
      ),
    ),
  );
}
