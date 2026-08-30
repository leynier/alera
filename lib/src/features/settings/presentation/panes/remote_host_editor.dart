import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';

class const RemoteHostEditor({
  super.key,
  required final TextEditingController aliasController,
  required final TextEditingController hostController,
  required final TextEditingController portController,
  required final TextEditingController usernameController,
  required final TextEditingController installDirController,
  required final String platform,
  required final String arch,
  required final SshAuthKind authKind,
  required final bool hasSelection,
  required final bool saving,
  required final bool planning,
  required final bool bootstrapping,
  required final ValueChanged<String> onPlatformChanged,
  required final ValueChanged<String> onArchChanged,
  required final ValueChanged<SshAuthKind> onAuthKindChanged,
  required final VoidCallback onSave,
  required final VoidCallback? onRemove,
  required final VoidCallback? onPlan,
  required final VoidCallback? onBootstrap,
  required final VoidCallback? onCancel,
  final String? error,
  final SshTargetBootstrapPlan? plan,
  final SshTargetBootstrapProgress? progress,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressError = progress?.error;
    final statusDetail =
        error ??
        progressError ??
        (progress == null ? null : statusLabel(progress!.status));
    final statusIsError =
        error != null ||
        progressError != null ||
        progress?.status == SshBootstrapStatus.failed;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraSettingsGroup(
            title: 'Connection',
            description: 'SSH target used by the runtime host.',
            children: <Widget>[
              _InlineFieldRow(
                first: AleraTextField(
                  controller: aliasController,
                  labelText: 'Alias',
                  prefixIcon: AleraIcons.text,
                  enabled: !bootstrapping,
                ),
                second: AleraTextField(
                  controller: hostController,
                  labelText: 'Host',
                  prefixIcon: AleraIcons.public,
                  enabled: !bootstrapping,
                ),
              ),
              _InlineFieldRow(
                first: AleraTextField(
                  controller: usernameController,
                  labelText: 'Username',
                  prefixIcon: AleraIcons.ai,
                  enabled: !bootstrapping,
                ),
                second: AleraTextField(
                  controller: portController,
                  labelText: 'Port',
                  keyboardType: .number,
                  prefixIcon: AleraIcons.terminal,
                  enabled: !bootstrapping,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: _RemoteHostDropdown<SshAuthKind>(
                  label: 'Authentication',
                  fieldKey: ValueKey<String>('Authentication:${authKind.name}'),
                  value: authKind,
                  // Password stays listed but non-selectable: existing
                  // password-auth targets keep their value, new selections
                  // must use agent or key auth.
                  entries: const <AleraDropdownFieldEntry<SshAuthKind>>[
                    AleraDropdownFieldEntry<SshAuthKind>(
                      value: .agent,
                      label: 'Agent',
                    ),
                    AleraDropdownFieldEntry<SshAuthKind>(
                      value: .key,
                      label: 'Key',
                    ),
                    AleraDropdownFieldEntry<SshAuthKind>(
                      value: .password,
                      label: 'Password',
                      enabled: false,
                    ),
                  ],
                  onChanged: bootstrapping ? null : onAuthKindChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraSettingsGroup(
            title: 'Runtime Bootstrap',
            description: 'Install the Alera runtime sidecar on this host.',
            children: <Widget>[
              _InlineFieldRow(
                first: _RemoteHostDropdown<String>(
                  label: 'Platform',
                  fieldKey: ValueKey<String>('Platform:$platform'),
                  value: platform,
                  entries: const <AleraDropdownFieldEntry<String>>[
                    AleraDropdownFieldEntry<String>(value: '', label: 'Auto'),
                    AleraDropdownFieldEntry<String>(
                      value: 'macos',
                      label: 'macOS',
                    ),
                    AleraDropdownFieldEntry<String>(
                      value: 'linux',
                      label: 'Linux',
                    ),
                    AleraDropdownFieldEntry<String>(
                      value: 'windows',
                      label: 'Windows',
                    ),
                  ],
                  onChanged: bootstrapping ? null : onPlatformChanged,
                ),
                second: _RemoteHostDropdown<String>(
                  label: 'Architecture',
                  fieldKey: ValueKey<String>('Architecture:$arch'),
                  value: arch,
                  entries: const <AleraDropdownFieldEntry<String>>[
                    AleraDropdownFieldEntry<String>(value: '', label: 'Auto'),
                    AleraDropdownFieldEntry<String>(value: 'x64', label: 'x64'),
                    AleraDropdownFieldEntry<String>(
                      value: 'arm64',
                      label: 'arm64',
                    ),
                  ],
                  onChanged: bootstrapping ? null : onArchChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: AleraTextField(
                  controller: installDirController,
                  labelText: 'Install Directory',
                  hintText: 'Default per platform',
                  prefixIcon: AleraIcons.folder,
                  enabled: !bootstrapping,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Wrap(
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: <Widget>[
                    // The app theme styles FilledButton and gives enabled
                    // buttons the click cursor; ElevatedButton falls back to
                    // Material defaults here.
                    FilledButton.icon(
                      onPressed: saving || bootstrapping ? null : onSave,
                      icon: Icon(saving ? AleraIcons.loading : AleraIcons.save),
                      label: const Text('Save'),
                    ),
                    OutlinedButton.icon(
                      onPressed: hasSelection && !planning && !bootstrapping
                          ? onPlan
                          : null,
                      icon: Icon(
                        planning ? AleraIcons.loading : AleraIcons.info,
                      ),
                      label: const Text('Plan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: hasSelection && !saving && !bootstrapping
                          ? onBootstrap
                          : null,
                      icon: const Icon(AleraIcons.cloudUpload),
                      label: const Text('Bootstrap'),
                    ),
                    OutlinedButton.icon(
                      onPressed: bootstrapping ? onCancel : null,
                      icon: const Icon(AleraIcons.cancel),
                      label: const Text('Cancel'),
                    ),
                    TextButton.icon(
                      onPressed: saving || bootstrapping ? null : onRemove,
                      icon: const Icon(AleraIcons.delete),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (plan != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            _RemoteHostPlanPanel(plan: plan!),
          ],
          if (progress != null || error != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            AleraPanel(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        progress?.message ?? 'Remote runtime error',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: .w600,
                        ),
                      ),
                      const SizedBox(height: AleraTokens.space4),
                      Text(
                        statusDetail ?? 'Remote runtime error',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: !statusIsError
                              ? AleraTokens.foregroundMuted
                              : AleraTokens.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class const _InlineFieldRow({
  required final Widget first,
  required final Widget second,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Expanded(child: first),
          const SizedBox(width: AleraTokens.space12),
          Expanded(child: second),
        ],
      ),
    );
  }
}

/// Labeled [AleraDropdownField] used by the connection and bootstrap groups.
/// [fieldKey] keeps the `Label:value` key scheme so the field reseeds when
/// the selected target changes.
class const _RemoteHostDropdown<T>({
  required final String label,
  required final Key fieldKey,
  required final T value,
  required final List<AleraDropdownFieldEntry<T>> entries,
  required final ValueChanged<T>? onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        AleraDropdownField<T>(
          key: fieldKey,
          value: value,
          entries: entries,
          enabled: onChanged != null,
          onChanged: (next) => onChanged?.call(next),
        ),
      ],
    );
  }
}

class const _RemoteHostPlanPanel({required final SshTargetBootstrapPlan plan})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraSettingsGroup(
      title: 'Bootstrap Plan',
      description: '${plan.platform} ${plan.arch} to ${plan.installDir}',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                '${plan.trust} from ${plan.artifactSource}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w600,
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
              for (final step in plan.steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space4),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        AleraIcons.check,
                        size: 14,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Expanded(
                        child: Text(
                          step,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class const RemoteHostError({super.key, required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: AleraIcons.error,
      title: 'Remote hosts unavailable',
      message: message,
    );
  }
}

String statusLabel(SshBootstrapStatus status) {
  return switch (status) {
    SshBootstrapStatus.notInstalled => 'Not installed',
    SshBootstrapStatus.planned => 'Planned',
    SshBootstrapStatus.installing => 'Installing',
    SshBootstrapStatus.installed => 'Installed',
    SshBootstrapStatus.failed => 'Failed',
    SshBootstrapStatus.cancelled => 'Cancelled',
  };
}
