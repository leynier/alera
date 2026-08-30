import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_command_line.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_launcher.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const UpdateSettingsSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aleraUpdateControllerProvider);
    final controller = ref.read(aleraUpdateControllerProvider.notifier);
    final theme = Theme.of(context);
    final packageInstall = ref.watch(packageManagerInstallProvider);
    final needsManualPath =
        state.status == AleraUpdateStatus.manualDownloadRequired ||
        state.status == AleraUpdateStatus.restartRequired ||
        (state.status == AleraUpdateStatus.error && state.latest != null);
    final upgradeCommand = needsManualPath
        ? packageManagerUpgradeCommand(
            update: state.latest,
            channel: state.config.channel,
            installMethod: packageInstall.method,
          )
        : null;
    final managerLabel = packageManagerLabel(packageInstall.method);
    final canRunUpgrade =
        needsManualPath &&
        state.status != AleraUpdateStatus.restartRequired &&
        packageInstall.canRunUpgrade &&
        !state.isBusy;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Text(
            'Updates',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: .start,
                children: <Widget>[
                  AleraStatusIndicator(
                    icon: _iconForStatus(state.status),
                    color: _colorForStatus(state.status),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(child: _UpdateStatusCopy(state: state)),
                ],
              ),
              if (state.status == AleraUpdateStatus.downloading ||
                  state.status == AleraUpdateStatus.applying) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                LinearProgressIndicator(
                  value: state.status == AleraUpdateStatus.downloading
                      ? state.progress
                      : null,
                ),
              ],
              if (upgradeCommand != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                _UpgradeCommand(command: upgradeCommand),
              ],
              if (canRunUpgrade) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                Text(
                  'Alera will close, let $managerLabel install the update, '
                  'and open again.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
              const SizedBox(height: AleraTokens.space16),
              Wrap(
                alignment: .end,
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed:
                        state.isBusy ||
                            state.status == AleraUpdateStatus.restartRequired
                        ? null
                        : controller.checkForUpdates,
                    icon: const Icon(AleraIcons.refresh, size: 16),
                    label: Text(
                      state.status == AleraUpdateStatus.checking
                          ? 'Checking'
                          : 'Check for Updates',
                    ),
                  ),
                  if (state.status == AleraUpdateStatus.manualDownloadRequired)
                    OutlinedButton.icon(
                      onPressed: controller.openDownloadPage,
                      icon: const Icon(AleraIcons.external, size: 16),
                      label: Text(
                        upgradeCommand == null
                            ? 'Download Manually'
                            : 'Installation Guide',
                      ),
                    ),
                  if (canRunUpgrade)
                    FilledButton.icon(
                      onPressed: controller.upgradeThroughPackageManager,
                      icon: const Icon(AleraIcons.download, size: 16),
                      label: Text('Update With $managerLabel'),
                    ),
                  if (state.status == AleraUpdateStatus.available)
                    FilledButton.icon(
                      onPressed: controller.installLatest,
                      icon: const Icon(AleraIcons.download, size: 16),
                      label: const Text('Install Update'),
                    ),
                  if (state.status == AleraUpdateStatus.restartRequired)
                    FilledButton.icon(
                      onPressed: controller.restartApp,
                      icon: const Icon(AleraIcons.restart, size: 16),
                      label: const Text('Restart Alera'),
                    ),
                  if (state.status == AleraUpdateStatus.error &&
                      state.latest != null &&
                      !packageInstall.canRunUpgrade)
                    FilledButton.icon(
                      onPressed: controller.installLatest,
                      icon: const Icon(AleraIcons.refresh, size: 16),
                      label: const Text('Try Again'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows the package-manager command that performs the update, for every
/// installation Alera detects but must not replace itself: Linux packages,
/// Chocolatey, and as the fallback when running the upgrade fails.
///
/// `Run Update` runs it in a terminal dialog rather than leaving the user to
/// paste it somewhere. These commands are the ones that need `sudo`, and a
/// dialog with a real PTY is somewhere a password can actually be typed.
class const _UpgradeCommand({required final String command})
    extends ConsumerWidget {
  Future<void> _run(BuildContext context, WidgetRef ref) async {
    await showCommandTerminalDialog(
      context,
      ref,
      CommandTerminalRequest(
        title: 'Update Alera',
        command: command,
        description: 'The update runs here. Answer any prompt in the terminal.',
      ),
    );
    if (!context.mounted) {
      return;
    }
    ref
        .read(aleraUpdateControllerProvider.notifier)
        .requireRestartAfterManualUpdate();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraCommandLine(
      command: command,
      trailing: Row(
        mainAxisSize: .min,
        children: <Widget>[
          AleraIconButton(
            tooltip: 'Copy Command',
            icon: AleraIcons.copy,
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: command))),
          ),
          const SizedBox(width: AleraTokens.space8),
          FilledButton.icon(
            onPressed: () => unawaited(_run(context, ref)),
            icon: const Icon(AleraIcons.terminal, size: 16),
            label: const Text('Run Update'),
          ),
        ],
      ),
    );
  }
}

class const _UpdateStatusCopy({required final AleraUpdateState state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = state.latest;
    final currentVersion = state.currentVersion?.trim();
    final currentBuildNumber = state.currentBuildNumber?.trim();
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          _titleForStatus(state.status),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foreground,
            fontWeight: .w500,
          ),
        ),
        if (currentVersion != null && currentVersion.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            _versionLabel(
              prefix: 'Current version',
              version: currentVersion,
              buildNumber: currentBuildNumber,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
        if (latest != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            _versionLabel(
              prefix: 'Update version',
              version: latest.version,
              buildNumber: latest.shortVersion > 0
                  ? '${latest.shortVersion}'
                  : null,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
        if (state.message != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            state.message!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }

  String _titleForStatus(AleraUpdateStatus status) {
    return switch (status) {
      AleraUpdateStatus.idle => 'Update status',
      AleraUpdateStatus.checking => 'Checking for updates',
      AleraUpdateStatus.notAvailable => 'No update available',
      AleraUpdateStatus.manualDownloadRequired => 'Manual update available',
      AleraUpdateStatus.available => 'Update available',
      AleraUpdateStatus.downloading => 'Downloading update',
      AleraUpdateStatus.applying => 'Installing update',
      AleraUpdateStatus.downloaded => 'Restarting Alera',
      AleraUpdateStatus.restartRequired => 'Restart Alera',
      AleraUpdateStatus.error => 'Update failed',
    };
  }
}

String _versionLabel({
  required String prefix,
  required String version,
  String? buildNumber,
}) {
  final build = buildNumber?.trim();
  return build == null || build.isEmpty
      ? '$prefix $version'
      : '$prefix $version (build $build)';
}

Color _colorForStatus(AleraUpdateStatus status) {
  return switch (status) {
    AleraUpdateStatus.error => AleraTokens.error,
    AleraUpdateStatus.downloaded => AleraTokens.success,
    AleraUpdateStatus.restartRequired => AleraTokens.info,
    AleraUpdateStatus.available ||
    AleraUpdateStatus.manualDownloadRequired ||
    AleraUpdateStatus.downloading ||
    AleraUpdateStatus.applying => AleraTokens.info,
    _ => AleraTokens.foregroundMuted,
  };
}

IconData _iconForStatus(AleraUpdateStatus status) {
  return switch (status) {
    AleraUpdateStatus.checking => AleraIcons.sync,
    AleraUpdateStatus.notAvailable => AleraIcons.check,
    AleraUpdateStatus.manualDownloadRequired => AleraIcons.downloadOffline,
    AleraUpdateStatus.available => AleraIcons.updateAvailable,
    AleraUpdateStatus.downloading => AleraIcons.downloading,
    AleraUpdateStatus.applying => AleraIcons.sync,
    AleraUpdateStatus.downloaded => AleraIcons.check,
    AleraUpdateStatus.restartRequired => AleraIcons.restart,
    AleraUpdateStatus.error => AleraIcons.error,
    AleraUpdateStatus.idle => AleraIcons.info,
  };
}
