import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_device_list_row.dart';
import 'package:flutter/material.dart';

/// What the Connected Apps list currently holds.
sealed class McpConnectedAppsView {
  const McpConnectedAppsView();
}

final class const McpConnectedAppsSignedOut() extends McpConnectedAppsView;

final class const McpConnectedAppsLoading() extends McpConnectedAppsView;

final class const McpConnectedAppsFailed(final String message)
    extends McpConnectedAppsView;

final class const McpConnectedAppsLoaded(final List<McpGrant> grants)
    extends McpConnectedAppsView;

/// MCP clients authorized for the account. Presentational: the pane loads the
/// grants and confirms revocations.
class const McpConnectedAppsGroup({
  super.key,
  required final McpConnectedAppsView view,
  required final VoidCallback onRefresh,
  required final ValueChanged<McpGrant> onRevoke,
  final Set<String> revokingIds = const <String>{},
  final String? error,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final view = this.view;
    final signedOut = view is McpConnectedAppsSignedOut;
    return AleraSettingsGroup(
      title: 'Connected Apps',
      description:
          'MCP clients you authorized with your Alera account. Revoking an app '
          'removes its access to every runtime it was granted.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Authorized Apps',
          description: 'Read from the Alera cloud each time this page opens.',
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: signedOut || view is McpConnectedAppsLoading
                  ? null
                  : onRefresh,
              icon: const Icon(AleraIcons.refresh, size: AleraTokens.iconMd),
              label: const Text('Refresh'),
            ),
          ),
        ),
        if (error case final String message)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: AleraInlineNotice(tone: .error, message: message),
          ),
        ...switch (view) {
          McpConnectedAppsSignedOut() => const <Widget>[
            AleraEmptyState(
              icon: AleraIcons.account,
              title: 'Not signed in',
              message: 'Sign in to an Alera account to see connected apps.',
            ),
          ],
          McpConnectedAppsLoading() => const <Widget>[
            AleraEmptyState(loading: true, message: 'Loading connected apps…'),
          ],
          McpConnectedAppsFailed(:final message) => <Widget>[
            AleraEmptyState(
              icon: AleraIcons.error,
              title: 'Connected apps unavailable',
              message: message,
            ),
          ],
          McpConnectedAppsLoaded(:final grants) when grants.isEmpty =>
            const <Widget>[
              AleraEmptyState(
                icon: AleraIcons.mcp,
                title: 'No connected apps',
                message:
                    'Add the MCP endpoint to Claude, ChatGPT, or another MCP '
                    'client and approve it to see it here.',
              ),
            ],
          McpConnectedAppsLoaded(:final grants) => <Widget>[
            for (final grant in grants)
              McpGrantListRow(
                grant: grant,
                revoking: revokingIds.contains(grant.id),
                onRevoke: () => onRevoke(grant),
              ),
          ],
        },
      ],
    );
  }
}

class const McpGrantListRow({
  super.key,
  required final McpGrant grant,
  required final VoidCallback onRevoke,
  final bool revoking = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedSmall = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.mcp,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Wrap(
                  spacing: AleraTokens.space6,
                  runSpacing: AleraTokens.space4,
                  crossAxisAlignment: .center,
                  children: <Widget>[
                    Text(
                      grant.clientName,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
                      ),
                    ),
                    for (final scope in grant.scopes) AleraChip(label: scope),
                  ],
                ),
                const SizedBox(height: AleraTokens.space4),
                Tooltip(
                  message: grant.allRuntimes || grant.runtimeIds.isEmpty
                      ? ''
                      : grant.runtimeIds.join('\n'),
                  child: Text(
                    mcpGrantDetail(grant),
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: mutedSmall,
                  ),
                ),
              ],
            ),
          ),
          AleraIconButton(
            tooltip: 'Revoke App',
            icon: AleraIcons.delete,
            iconColor: AleraTokens.error,
            onPressed: revoking ? null : onRevoke,
          ),
        ],
      ),
    );
  }
}

/// One line describing where an app redirects, which runtimes it reaches and
/// when it was last used.
String mcpGrantDetail(McpGrant grant) {
  final runtimes = grant.allRuntimes
      ? 'All runtimes'
      : switch (grant.runtimeIds.length) {
          0 => 'No runtimes',
          1 => '1 runtime',
          final count => '$count runtimes',
        };
  final lastUsed = grant.lastUsedAt;
  return <String>[
    ?grant.redirectHost,
    runtimes,
    lastUsed == null
        ? 'Never used'
        : 'Last used ${formatMobileTimestamp(lastUsed)}',
  ].join(' · ');
}
