import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> closeWorkspaceAgentTerminal(
  BuildContext context,
  WidgetRef ref,
  AgentPresenceSummary status, {
  required String hostId,
  required String workspaceId,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Close Agent Terminal'),
      content: Text(
        'Close The ${agentDisplayName(status.agentType)} Terminal?',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    final provider = tabsControllerProvider(hostId, workspaceId);
    final tabs = await ref.read(provider.future);
    final tab = tabs.where((item) => item.id == status.tabId).firstOrNull;
    if (tab == null) {
      throw StateError('The Agent Terminal Is No Longer Available.');
    }
    await ref.read(provider.notifier).closeTab(tab);
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could Not Close Agent Terminal: $error')),
      );
    }
  }
}

String agentDisplayName(String agentType) => switch (agentType) {
  'codex' => 'Codex',
  'claude' => 'Claude',
  'copilot' => 'Copilot',
  'cursor' => 'Cursor',
  'agy' => 'Agy',
  'opencode' => 'OpenCode',
  'pi' => 'Pi',
  'amp' => 'Amp',
  'grok' => 'Grok',
  _ => 'Agent',
};
