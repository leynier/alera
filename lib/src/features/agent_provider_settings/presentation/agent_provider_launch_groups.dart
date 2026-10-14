import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_option_specs.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_form_fields.dart';
import 'package:flutter/material.dart';

const double _kControlWidth = 320;

/// What every launch group needs to edit a draft and its pending secrets.
class const AgentProviderDraftEditing({
  required final AgentProviderInstanceDraft draft,
  required final Map<String, AgentProviderPendingSecret> pendingSecrets,
  required final ValueChanged<AgentProviderInstanceDraft> onChanged,
  required final void Function(String name, String value) onSetSecret,
  required final ValueChanged<String> onClearSecret,
  required final ValueChanged<String> onUndoSecret,
  final bool enabled = true,
});

/// Label and identity of the instance.
class const AgentProviderIdentityGroup({
  super.key,
  required final AgentProviderDraftEditing editing,
  required final String defaultLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final draft = editing.draft;
    return AleraSettingsGroup(
      title: 'Identity',
      description: 'How this provider appears in the chat picker.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Label',
          description: 'Leave empty to use $defaultLabel.',
          controlWidth: _kControlWidth,
          child: AgentProviderTextField(
            key: ValueKey<String>('label-${draft.providerInstanceId}'),
            value: draft.label,
            hintText: defaultLabel,
            enabled: editing.enabled,
            onChanged: (value) =>
                editing.onChanged(draft.copyWith(label: value)),
          ),
        ),
      ],
    );
  }
}

/// Executable, arguments, and provider-specific options.
class const AgentProviderLaunchGroup({
  super.key,
  required final AgentProviderDraftEditing editing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final draft = editing.draft;
    final specs = agentProviderOptionSpecs(draft.provider);
    final executableCopy = _executableCopy(draft.provider);
    return AleraSettingsGroup(
      title: 'Launch',
      description:
          'How the runtime on this host starts the provider. Changes apply '
          'to the next chat start; running chats keep their process.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Executable',
          description: executableCopy.description,
          controlWidth: _kControlWidth,
          child: AgentProviderTextField(
            key: ValueKey<String>('executable-${draft.providerInstanceId}'),
            value: draft.executable,
            hintText: executableCopy.hint,
            enabled: editing.enabled,
            onChanged: (value) =>
                editing.onChanged(draft.copyWith(executable: value)),
          ),
        ),
        AleraSettingRow(
          title: 'Arguments',
          description: 'Added after the executable. Quote values with spaces.',
          controlWidth: _kControlWidth,
          child: AgentProviderTextField(
            key: ValueKey<String>('args-${draft.providerInstanceId}'),
            value: agentProviderJoinArguments(draft.args),
            hintText: 'No extra arguments',
            enabled: editing.enabled,
            onChanged: (value) => editing.onChanged(
              draft.copyWith(args: agentProviderSplitArguments(value)),
            ),
          ),
        ),
        for (final spec in specs) _OptionRow(spec: spec, editing: editing),
      ],
    );
  }
}

/// An ACP registry agent has no default executable: the host reports Setup
/// Required until one is set (`production_catalog.rs`), so the PATH fallback
/// every built-in provider has would be untrue for it.
({String description, String hint}) _executableCopy(String provider) =>
    switch (provider) {
      'acpRegistry' => (
        description:
            'Required. ACP agents have no default; enter a command on the '
            'host PATH or a full path.',
        hint: 'Command or full path',
      ),
      _ => (
        description: 'Leave empty to find it on the host PATH.',
        hint: 'Found on PATH',
      ),
    };

class const _OptionRow({
  required final AgentProviderOptionSpec spec,
  required final AgentProviderDraftEditing editing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final draft = editing.draft;
    final value = draft.options[spec.key];
    Map<String, Object?> withValue(Object? next) => <String, Object?>{
      for (final entry in draft.options.entries)
        if (entry.key != spec.key) entry.key: entry.value,
      spec.key: ?next,
    };
    final Widget control = switch (spec.kind) {
      .toggle => Align(
        alignment: Alignment.centerRight,
        child: Switch(
          value: value == true,
          onChanged: editing.enabled
              ? (next) => editing.onChanged(
                  draft.copyWith(options: withValue(next ? true : null)),
                )
              : null,
        ),
      ),
      .secret => AgentProviderSecretControl(
        key: ValueKey<String>('secret-${spec.secretName}'),
        name: spec.label,
        saved: draft.optionSecretSaved(spec.key),
        pending: editing.pendingSecrets[spec.secretName],
        enabled: editing.enabled,
        onSet: (secret) => editing.onSetSecret(spec.secretName, secret),
        onClear: () => editing.onClearSecret(spec.secretName),
        onUndo: () => editing.onUndoSecret(spec.secretName),
      ),
      .text => AgentProviderTextField(
        key: ValueKey<String>('option-${draft.providerInstanceId}-${spec.key}'),
        value: value is String ? value : '',
        enabled: editing.enabled,
        onChanged: (next) => editing.onChanged(
          draft.copyWith(
            options: withValue(next.trim().isEmpty ? null : next.trim()),
          ),
        ),
      ),
    };
    return AleraSettingRow(
      title: spec.label,
      description: spec.description,
      controlWidth: _kControlWidth,
      child: control,
    );
  }
}

/// Environment variables the provider process starts with. Sensitive ones
/// are write-only secrets; plain ones are stored and shown as typed.
class const AgentProviderEnvironmentGroup({
  super.key,
  required final AgentProviderDraftEditing editing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = editing.draft;
    final entries = draft.environment;
    void replace(int index, AgentProviderEnvironmentDraft? entry) {
      final next = List<AgentProviderEnvironmentDraft>.of(entries);
      if (entry == null) {
        next.removeAt(index);
      } else {
        next[index] = entry;
      }
      editing.onChanged(draft.copyWith(environment: next));
    }

    return AleraSettingsGroup(
      title: 'Environment',
      description:
          'Variables set for the provider process. Mark API keys and tokens '
          'Secret: they are stored in the system keychain on this host and '
          'never shown again.',
      trailing: TextButton.icon(
        onPressed: editing.enabled
            ? () => editing.onChanged(
                draft.copyWith(
                  environment: <AgentProviderEnvironmentDraft>[
                    ...entries,
                    const AgentProviderEnvironmentDraft(name: ''),
                  ],
                ),
              )
            : null,
        icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
        label: const Text('Add Variable'),
      ),
      children: <Widget>[
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text(
              'No variables. The provider inherits the host login '
              'environment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        for (var index = 0; index < entries.length; index++)
          _EnvironmentRow(
            key: ValueKey<String>('env-${draft.providerInstanceId}-$index'),
            entry: entries[index],
            editing: editing,
            onChanged: (entry) => replace(index, entry),
            onRemove: () => replace(index, null),
          ),
      ],
    );
  }
}

class const _EnvironmentRow({
  super.key,
  required final AgentProviderEnvironmentDraft entry,
  required final AgentProviderDraftEditing editing,
  required final ValueChanged<AgentProviderEnvironmentDraft> onChanged,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = entry.name.trim();
    final secretName = agentProviderEnvironmentSecretName(name);
    final validName =
        name.isEmpty || agentProviderEnvironmentNamePattern.hasMatch(name);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          SizedBox(
            width: _kControlWidth * 0.6,
            child: AgentProviderTextField(
              value: entry.name,
              hintText: 'NAME',
              enabled: editing.enabled && !entry.secretSaved,
              errorText: validName ? null : 'Use letters, digits and _',
              onChanged: (value) => onChanged(entry.copyWith(name: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: entry.sensitive
                ? AgentProviderSecretControl(
                    name: name.isEmpty ? 'this variable' : name,
                    saved: entry.secretSaved,
                    pending: editing.pendingSecrets[secretName],
                    enabled: editing.enabled && name.isNotEmpty && validName,
                    onSet: (value) => editing.onSetSecret(secretName, value),
                    onClear: () => editing.onClearSecret(secretName),
                    onUndo: () => editing.onUndoSecret(secretName),
                  )
                : AgentProviderTextField(
                    value: entry.value,
                    hintText: 'Value',
                    enabled: editing.enabled,
                    onChanged: (value) =>
                        onChanged(entry.copyWith(value: value)),
                  ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Tooltip(
            message: entry.secretSaved
                ? 'Clear the saved value before making it plain text.'
                : 'Stored write-only in the host keychain',
            child: AleraCheckbox(
              value: entry.sensitive,
              label: 'Secret',
              enabled: editing.enabled && !entry.secretSaved,
              onChanged: (value) => onChanged(entry.copyWith(sensitive: value)),
            ),
          ),
          AleraIconButton(
            tooltip: 'Remove Variable',
            icon: AleraIcons.delete,
            onPressed: editing.enabled ? onRemove : null,
          ),
        ],
      ),
    );
  }
}
