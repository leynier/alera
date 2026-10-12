import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/shared/format_timestamp.dart';
import 'package:flutter/material.dart';

/// When Alera last reached the host, the last error it reported, and the way
/// to the logs that explain it.
class const RemoteHostDiagnosticsGroup({
  super.key,
  required final SshTarget target,
  required final ValueChanged<String> onCopyError,
  required final VoidCallback onOpenLogs,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkedAt = target.lastCheckedAt;
    final lastError = target.lastError;
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return AleraSettingsGroup(
      title: 'Diagnostics',
      children: <Widget>[
        AleraSettingRow(
          title: 'Last Checked',
          child: Text(
            checkedAt == null ? 'Never' : formatTimestamp(checkedAt),
            textAlign: TextAlign.end,
            style: valueStyle,
          ),
        ),
        if (lastError != null)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Last Error',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foreground,
                        ),
                      ),
                    ),
                    AleraIconButton(
                      tooltip: 'Copy Error',
                      icon: AleraIcons.copy,
                      onPressed: () => onCopyError(lastError),
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space4),
                SelectableText(lastError, style: AleraTokens.monoCompactStyle),
              ],
            ),
          ),
        AleraSettingRow(
          title: 'Logs',
          description: 'The Alera runtime on This Device logs every connection and install.',
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton(
              onPressed: onOpenLogs,
              child: const Text('Open Logs Folder'),
            ),
          ),
        ),
      ],
    );
  }
}
