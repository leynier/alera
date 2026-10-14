import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_section.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// Opens Settings on Providers, on [hostId] (a workspace's host id, `local`
/// or null for This Device) and on [providerInstanceId] when given. It only
/// opens a dialog: it never selects a workspace or a tab.
Future<void> openAgentChatProviderSettings(
  BuildContext context, {
  String? hostId,
  String? providerInstanceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(
      initialSectionId: agentProviderSettingsSectionId,
      initialHostId: normalizedRemoteHostId(hostId),
      initialProviderInstanceId: providerInstanceId,
    ),
  );
}
