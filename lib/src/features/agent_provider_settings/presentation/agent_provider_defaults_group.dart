import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:flutter/material.dart';

const double _kControlWidth = 260;

/// A model a default can name; [id] is null for the provider default.
class const AgentProviderModelChoice({
  required final String? id,
  required final String label,
});

/// A project whose new chats default to this instance, by name.
class const AgentProviderProjectDefault({
  required final String projectId,
  required final String projectName,
  required final String? model,
});

/// Default For New Chats: whether this instance is the host-wide default for
/// new chats and with which model, plus the projects that default to it.
/// Every change here is a host preference and applies at once.
class const AgentProviderDefaultsGroup({
  super.key,
  required final String instanceLabel,
  required final bool isDefault,
  required final String? defaultModel,
  required final List<AgentProviderModelChoice> models,
  required final List<AgentProviderProjectDefault> projectDefaults,
  required final List<({String id, String name})> otherProjects,
  required final bool editable,
  required final void Function(bool useForNewChats, String? model) onSetDefault,
  required final void Function(String projectId, String? model)
  onSetProjectDefault,
  required final ValueChanged<String> onClearProjectDefault,
  final bool instanceEnabled = true,
  final String? unavailableReason,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = editable && instanceEnabled;
    final modelEntries = <AleraDropdownFieldEntry<String>>[
      for (final model in models)
        AleraDropdownFieldEntry<String>(
          value: model.id ?? '',
          label: model.label,
        ),
    ];
    return AleraSettingsGroup(
      title: 'Default For New Chats',
      description:
          unavailableReason ??
          (instanceEnabled
              ? 'A project default wins, then this default, then the last '
                    'provider you sent with.'
              : 'Turn this provider on to make it a default.'),
      children: <Widget>[
        AleraSettingRow(
          title: 'Use For New Chats',
          description: isDefault
              ? 'New chats on this host start with $instanceLabel.'
              : 'New chats start with another provider.',
          controlWidth: _kControlWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: isDefault,
              onChanged: canEdit
                  ? (value) => onSetDefault(value, defaultModel)
                  : null,
            ),
          ),
        ),
        if (isDefault)
          AleraSettingRow(
            title: 'Model',
            description: 'The model new chats start with.',
            controlWidth: _kControlWidth,
            child: AleraDropdownField<String>(
              value: defaultModel ?? '',
              entries: modelEntries,
              enabled: canEdit,
              filterable: modelEntries.length > 8,
              onChanged: (value) =>
                  onSetDefault(true, value.isEmpty ? null : value),
            ),
          ),
        for (final project in projectDefaults)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
              vertical: AleraTokens.space8,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.folderSpecial,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    project.projectName,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: _kControlWidth,
                  child: AleraDropdownField<String>(
                    value: project.model ?? '',
                    entries: modelEntries,
                    enabled: editable,
                    onChanged: (value) => onSetProjectDefault(
                      project.projectId,
                      value.isEmpty ? null : value,
                    ),
                  ),
                ),
                AleraIconButton(
                  tooltip: 'Stop Using For ${project.projectName}',
                  icon: AleraIcons.close,
                  onPressed: editable
                      ? () => onClearProjectDefault(project.projectId)
                      : null,
                ),
              ],
            ),
          ),
        if (otherProjects.isNotEmpty)
          AleraSettingRow(
            title: 'Use For A Project',
            description: 'New chats in that project start with $instanceLabel.',
            controlWidth: _kControlWidth,
            child: AleraDropdownField<String>(
              value: null,
              hintText: 'Choose Project',
              entries: <AleraDropdownFieldEntry<String>>[
                for (final project in otherProjects)
                  AleraDropdownFieldEntry<String>(
                    value: project.id,
                    label: project.name,
                  ),
              ],
              enabled: canEdit,
              filterable: otherProjects.length > 8,
              onChanged: (projectId) => onSetProjectDefault(projectId, null),
            ),
          ),
      ],
    );
  }
}
