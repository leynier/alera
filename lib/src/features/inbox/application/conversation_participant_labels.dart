import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'conversation_participant_labels.g.dart';

/// Readable names for terminal handles: the tab title and agent the sidebar
/// knows. A handle missing from the sidebar keeps its raw id.
@riverpod
Map<String, String> conversationParticipantLabels(Ref ref) {
  final tabsByWorkspace = ref.watch(
    workbenchControllerProvider.select((state) => state.tabsByWorkspace),
  );
  final statuses = ref.watch(agentStatusControllerProvider);
  return <String, String>{
    for (final tabs in tabsByWorkspace.values)
      for (final tab in tabs)
        if (tab.kind == WorkspaceTabKind.terminal)
          tab.terminalSessionId: _label(
            tab.title.trim(),
            statuses[tab.terminalSessionId] == null
                ? null
                : agentDisplayName(statuses[tab.terminalSessionId]!.agentType),
          ),
  };
}

/// Workspace names by id, for the conversation filter and rows.
@riverpod
Map<String, String> conversationWorkspaceNames(Ref ref) => ref.watch(
  workbenchControllerProvider.select(
    (state) => <String, String>{
      for (final workspaces in state.workspacesByProject.values)
        for (final workspace in workspaces) workspace.id: workspace.name,
    },
  ),
);

String participantLabel(Map<String, String> labels, String handle) =>
    labels[handle] ?? handle;

String _label(String title, String? agent) {
  if (agent == null) return title.isEmpty ? 'Terminal' : title;
  return title.isEmpty ? agent : '$title ($agent)';
}
