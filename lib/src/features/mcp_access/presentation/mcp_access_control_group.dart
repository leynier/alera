import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:flutter/material.dart';

const double _kAccessControlWidth = 320;
const double _kEndpointControlWidth = 340;

/// Access level, cloud link status and endpoint. Presentational: the pane owns
/// the runtime calls and passes their progress and failures in.
class const McpAccessControlGroup({
  super.key,
  required final McpAccessSettings settings,
  required final bool applying,
  required final ValueChanged<McpAccessLevel> onAccessSelected,
  required final VoidCallback onCopyEndpoint,
  final bool endpointCopied = false,
  final String? error,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final signedIn = settings.accountConnected;
    return AleraSettingsGroup(
      title: 'MCP Control',
      description:
          'MCP clients such as Claude or ChatGPT can list this runtime and run '
          'Alera commands on it through the Alera cloud. Tool arguments and '
          'results pass through the Alera cloud in transit and are not '
          'stored. An Alera account is required.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Access Level',
          description: _accessDescription(settings.access),
          controlWidth: _kAccessControlWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: AleraSegmentedButton<McpAccessLevel>(
              dense: true,
              segments: <ButtonSegment<McpAccessLevel>>[
                for (final level in McpAccessLevel.values)
                  ButtonSegment<McpAccessLevel>(
                    value: level,
                    label: Text(level.label),
                    // Off stays available so a signed-out runtime can still
                    // be switched off.
                    enabled: level == McpAccessLevel.off || signedIn,
                  ),
              ],
              selected: settings.access,
              onSelectionChanged: (level) {
                if (!applying && level != settings.access) {
                  onAccessSelected(level);
                }
              },
            ),
          ),
        ),
        if (!signedIn)
          const Padding(
            padding: EdgeInsets.all(AleraTokens.space12),
            child: AleraInlineNotice(
              tone: .warning,
              message:
                  'Sign in to an Alera account in Settings > Account to turn '
                  'on MCP Control.',
            ),
          ),
        if (error case final String message)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: AleraInlineNotice(tone: .error, message: message),
          ),
        _relayRow(),
        AleraSettingRow(
          title: 'MCP Endpoint',
          description:
              'Add this URL as a remote MCP server in your MCP client.',
          controlWidth: _kEndpointControlWidth,
          child: Row(
            children: <Widget>[
              const Expanded(
                child: SelectableText(
                  aleraRemoteMcpEndpoint,
                  maxLines: 1,
                  textAlign: .end,
                  style: AleraTokens.monoStyle,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              AleraIconButton(
                tooltip: endpointCopied ? 'Copied' : 'Copy Endpoint',
                icon: endpointCopied ? AleraIcons.check : AleraIcons.copy,
                onPressed: onCopyEndpoint,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _relayRow() {
    final relay = settings.relay;
    final (
      String label,
      AleraBadgeTone tone,
      String description,
    ) = switch (relay.state) {
      .connected => (
        'Connected',
        AleraBadgeTone.success,
        'Linked to the Alera cloud.',
      ),
      .connecting => (
        'Connecting',
        AleraBadgeTone.info,
        'Connecting to the Alera cloud…',
      ),
      .retrying => (
        'Error',
        AleraBadgeTone.error,
        'The Alera cloud is unreachable. Reconnecting automatically.',
      ),
      .blocked => (
        'Error',
        AleraBadgeTone.error,
        'Authorization failed. Review your Alera account sign-in.',
      ),
      .disabled => (
        'Off',
        AleraBadgeTone.neutral,
        'Not linked. The link opens while MCP Control or Remote Access is '
            'on and an Alera account is signed in.',
      ),
      .unknown => (
        'Unknown',
        AleraBadgeTone.neutral,
        'This runtime does not report its cloud link.',
      ),
    };
    final lastError = relay.lastError;
    return AleraSettingRow(
      title: 'Cloud Link',
      description: lastError == null || relay.state == .connected
          ? description
          : '$description Last error: $lastError',
      child: Align(
        alignment: Alignment.centerRight,
        child: AleraBadge(label: label, tone: tone),
      ),
    );
  }
}

String _accessDescription(McpAccessLevel access) {
  return switch (access) {
    .off => 'MCP clients cannot reach this runtime.',
    .read =>
      'MCP clients can run read-only tools. Tools that change anything are '
          'refused.',
    .full =>
      'MCP clients can run every Alera tool, including ones that start '
          'agents and change workspaces.',
  };
}
