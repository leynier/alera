import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/mcp_access/presentation/mcp_access_settings_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:alera/src/features/webhooks/presentation/webhooks_settings.dart';
import 'package:flutter/material.dart';

const List<SettingsGroupSpec> mcpAccessGroups = <SettingsGroupSpec>[
  SettingsGroupSpec(id: 'control', title: 'MCP Control'),
  SettingsGroupSpec(id: 'runtime', title: 'Runtime Name'),
  SettingsGroupSpec(id: 'apps', title: 'Connected Apps'),
  SettingsGroupSpec(id: 'webhooks', title: 'Webhooks'),
];

const List<SettingsSearchEntry> mcpAccessSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'MCP Control',
    description: 'Let MCP clients reach this runtime through the Alera cloud.',
    keywords: <String>[
      'mcp',
      'model context protocol',
      'claude',
      'chatgpt',
      'cursor',
      'remote',
      'read only',
      'full control',
      'endpoint',
      'cloud',
    ],
    groupId: 'control',
  ),
  SettingsSearchEntry(
    title: 'Runtime Name',
    description: 'Name MCP clients use to pick this runtime.',
    keywords: <String>['rename', 'runtime', 'host name'],
    groupId: 'runtime',
  ),
  SettingsSearchEntry(
    title: 'Connected Apps',
    description: 'Review and revoke authorized MCP clients.',
    keywords: <String>['oauth', 'grant', 'revoke', 'apps', 'clients'],
    groupId: 'apps',
  ),
  SettingsSearchEntry(
    title: 'Webhooks',
    description: 'Send signed runtime events to your own HTTPS endpoint.',
    keywords: <String>[
      'webhook',
      'events',
      'callback',
      'signing secret',
      'notifications',
      'integrations',
    ],
    groupId: 'webhooks',
  ),
];

/// The MCP Access settings section. [paneKeys] resolves the dialog's stable
/// group keys so search jumps and subsection chips can scroll to each group.
SettingsSectionData mcpAccessSettingsSection({
  required Map<String, GlobalKey> Function(String, List<SettingsGroupSpec>)
  paneKeys,
}) {
  return SettingsSectionData(
    id: 'mcpAccess',
    title: 'MCP Access',
    description:
        'Remote MCP control, runtime name, connected apps and webhooks.',
    icon: AleraIcons.mcp,
    entries: mcpAccessSearchEntries,
    groups: mcpAccessGroups,
    builder: (_) {
      final groupKeys = paneKeys('mcpAccess', mcpAccessGroups);
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          McpAccessSettingsPane(groupKeys: groupKeys),
          const SizedBox(height: AleraTokens.space16),
          KeyedSubtree(
            key: groupKeys['webhooks'],
            child: const WebhooksSettings(),
          ),
        ],
      );
    },
  );
}
