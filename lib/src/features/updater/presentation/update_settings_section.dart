import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aleraUpdateControllerProvider);
    final controller = ref.read(aleraUpdateControllerProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              fontWeight: FontWeight.w600,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AleraStatusIndicator(
                    icon: _iconForStatus(state.status),
                    color: _colorForStatus(state.status),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(child: _UpdateStatusCopy(state: state)),
                ],
              ),
              if (state.status == AleraUpdateStatus.downloading) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                LinearProgressIndicator(value: state.progress),
              ],
              const SizedBox(height: AleraTokens.space16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: state.isBusy ? null : controller.checkForUpdates,
                    icon: const Icon(AleraIcons.refresh, size: 16),
                    label: Text(
                      state.status == AleraUpdateStatus.checking
                          ? 'Checking'
                          : 'Check for updates',
                    ),
                  ),
                  if (state.status == AleraUpdateStatus.manualDownloadRequired)
                    FilledButton.icon(
                      onPressed: controller.openDownloadPage,
                      icon: const Icon(AleraIcons.external, size: 16),
                      label: const Text('Download manually'),
                    ),
                  if (state.status == AleraUpdateStatus.available)
                    FilledButton.icon(
                      onPressed: controller.installLatest,
                      icon: const Icon(AleraIcons.download, size: 16),
                      label: const Text('Download update'),
                    ),
                  if (state.status == AleraUpdateStatus.downloaded)
                    FilledButton.icon(
                      onPressed: controller.restartApp,
                      icon: const Icon(AleraIcons.restart, size: 16),
                      label: const Text('Restart Alera'),
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

class _UpdateStatusCopy extends StatelessWidget {
  const _UpdateStatusCopy({required this.state});

  final AleraUpdateState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = state.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _titleForStatus(state.status),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (latest != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Version ${latest.version} - Build ${latest.shortVersion}',
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
      AleraUpdateStatus.downloaded => 'Restart required',
      AleraUpdateStatus.error => 'Update check failed',
    };
  }
}

Color _colorForStatus(AleraUpdateStatus status) {
  return switch (status) {
    AleraUpdateStatus.error => AleraTokens.error,
    AleraUpdateStatus.downloaded => AleraTokens.success,
    AleraUpdateStatus.available ||
    AleraUpdateStatus.manualDownloadRequired ||
    AleraUpdateStatus.downloading => AleraTokens.info,
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
    AleraUpdateStatus.downloaded => AleraIcons.restart,
    AleraUpdateStatus.error => AleraIcons.error,
    AleraUpdateStatus.idle => AleraIcons.info,
  };
}
