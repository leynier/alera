import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';

class RemoteHostEditor extends StatelessWidget {
  const RemoteHostEditor({
    super.key,
    required this.aliasController,
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.installDirController,
    required this.platform,
    required this.arch,
    required this.authKind,
    required this.hasSelection,
    required this.saving,
    required this.planning,
    required this.bootstrapping,
    required this.onPlatformChanged,
    required this.onArchChanged,
    required this.onAuthKindChanged,
    required this.onSave,
    required this.onRemove,
    required this.onPlan,
    required this.onBootstrap,
    required this.onCancel,
    this.error,
    this.plan,
    this.progress,
  });

  final TextEditingController aliasController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController installDirController;
  final String platform;
  final String arch;
  final SshAuthKind authKind;
  final bool hasSelection;
  final bool saving;
  final bool planning;
  final bool bootstrapping;
  final ValueChanged<String> onPlatformChanged;
  final ValueChanged<String> onArchChanged;
  final ValueChanged<SshAuthKind> onAuthKindChanged;
  final VoidCallback onSave;
  final VoidCallback? onRemove;
  final VoidCallback? onPlan;
  final VoidCallback? onBootstrap;
  final VoidCallback? onCancel;
  final String? error;
  final SshTargetBootstrapPlan? plan;
  final SshTargetBootstrapProgress? progress;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  keyboardType: TextInputType.number,
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
                      value: SshAuthKind.agent,
                      label: 'Agent',
                    ),
                    AleraDropdownFieldEntry<SshAuthKind>(
                      value: SshAuthKind.key,
                      label: 'Key',
                    ),
                    AleraDropdownFieldEntry<SshAuthKind>(
                      value: SshAuthKind.password,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        progress?.message ?? 'Remote runtime error',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: FontWeight.w600,
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

class _InlineFieldRow extends StatelessWidget {
  const _InlineFieldRow({required this.first, required this.second});

  final Widget first;
  final Widget second;

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
class _RemoteHostDropdown<T> extends StatelessWidget {
  const _RemoteHostDropdown({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  final String label;
  final Key fieldKey;
  final T value;
  final List<AleraDropdownFieldEntry<T>> entries;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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

class _RemoteHostPlanPanel extends StatelessWidget {
  const _RemoteHostPlanPanel({required this.plan});

  final SshTargetBootstrapPlan plan;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${plan.trust} from ${plan.artifactSource}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
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

class RemoteHostError extends StatelessWidget {
  const RemoteHostError({super.key, required this.message});

  final String message;

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
