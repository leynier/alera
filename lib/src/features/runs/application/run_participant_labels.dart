import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_participant_labels.g.dart';

/// Readable names for the terminal handles in a run's timeline: the tab
/// title and agent the sidebar knows. Unknown handles keep their raw id.
@riverpod
Map<String, String> runParticipantLabels(Ref ref) {
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

String participantLabel(Map<String, String> labels, String handle) =>
    labels[handle] ?? handle;

String _label(String title, String? agent) {
  if (agent == null) return title.isEmpty ? 'Terminal' : title;
  return title.isEmpty ? agent : '$title ($agent)';
}
