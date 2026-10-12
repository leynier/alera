import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';

/// One finding of the Add Host connection check, or a line of progress.
class const RemoteHostCheckLine({
  super.key,
  required final IconData icon,
  required final String text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// "What will be installed": where, for which platform, which version and
/// from where.
class const RemoteHostInstallPlanRows({
  super.key,
  required final SshTargetBootstrapPlan? plan,
  required final bool loading,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    if (plan == null) {
      return RemoteHostCheckLine(
        icon: loading ? AleraIcons.loading : AleraIcons.info,
        text: loading
            ? 'Preparing the install plan…'
            : 'The default install for this host.',
      );
    }
    final rows = <(String, String)>[
      ('Install Directory', plan.installDir),
      ('Platform', _platformLabel(plan)),
      ('Version', '${plan.version ?? 'Latest'} · ${plan.channel}'),
      ('Source', _sourceLabel(plan)),
    ];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Table(
        columnWidths: const <int, TableColumnWidth>{
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(),
        },
        children: <TableRow>[
          for (final (label, value) in rows)
            TableRow(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    right: AleraTokens.space16,
                    top: AleraTokens.space4,
                    bottom: AleraTokens.space4,
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space4,
                  ),
                  child: Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _platformLabel(SshTargetBootstrapPlan plan) {
    final os = HostOs.parse(plan.platform);
    if (os == HostOs.unknown) {
      return 'Detected during install';
    }
    final arch = plan.arch == 'auto' ? null : plan.arch;
    return '${os.label}${arch == null ? '' : ' $arch'}';
  }

  String _sourceLabel(SshTargetBootstrapPlan plan) {
    if (plan.trust == 'localOverride') {
      return 'Local archive (unsigned override)';
    }
    if (plan.artifactSource == 'localArchivePath') {
      return 'Local signed release archive';
    }
    return 'Signed release archive from GitHub Releases';
  }
}
