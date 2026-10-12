import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/projects/domain/preferred_source_branch.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_project_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_automation_destinations.g.dart';

/// Source branches a project worktree can start from, with the one New
/// Workspace would preselect.
typedef MobileAutomationProjectBranches = ({
  List<String> branches,
  String? initial,
});

/// One agent conversation an automation can continue.
typedef MobileAutomationConversation = ({
  WorkspaceSummary workspace,
  WorkspaceTabSummary tab,
});

/// Agent tabs of [workspaceId] whose native conversation can be resumed.
@riverpod
Future<List<WorkspaceTabSummary>> mobileAutomationConversationTabs(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final tabs = await client.listTabs(workspaceId);
  return tabs
      .where((tab) => (tab.agentNativeSessionId ?? '').trim().isNotEmpty)
      .toList(growable: false);
}

/// Every resumable conversation on the host, for the Running Agents section
/// of the destination sheet. A workspace whose tabs fail to load is skipped.
@riverpod
Future<List<MobileAutomationConversation>> mobileAutomationConversations(
  Ref ref,
  String hostId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final workspaces = await client.listWorkspaces();
  final tabs = await Future.wait(<Future<List<WorkspaceTabSummary>>>[
    for (final workspace in workspaces)
      client
          .listTabs(workspace.id)
          .catchError((Object _) => const <WorkspaceTabSummary>[]),
  ]);
  return <MobileAutomationConversation>[
    for (final (index, workspace) in workspaces.indexed)
      for (final tab in tabs[index])
        if ((tab.agentNativeSessionId ?? '').trim().isNotEmpty)
          (workspace: workspace, tab: tab),
  ];
}

/// Registered project folders of a project, from the runtime checkout list.
@riverpod
Future<List<({String hostId, String path})>> mobileAutomationProjectFolders(
  Ref ref,
  String hostId,
  String projectId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final checkouts = await client.requestList('checkout.list', <String, Object?>{
    'projectId': projectId,
  });
  return <({String hostId, String path})>[
    for (final item in checkouts)
      if (automationJsonMap(item)['kind'] == 'project')
        (
          hostId: automationJsonString(automationJsonMap(item)['hostId']),
          path: automationJsonString(automationJsonMap(item)['path']),
        ),
  ];
}

@riverpod
Future<MobileAutomationProjectBranches> mobileAutomationProjectBranches(
  Ref ref,
  String hostId,
  String projectId,
) async {
  final client = await ref.watch(mobileAutomationClientProvider(hostId).future);
  final listed = await client.listBranches(projectId);
  String? preferred;
  if (client case final MobileRuntimeProjectClient projects) {
    try {
      final effective = await projects.effectiveProjectConfig(projectId);
      preferred = effective.config.preferredSourceBranch;
    } on Object {
      preferred = null;
    }
  }
  return (
    branches: listed.branches,
    initial: pickDefaultSourceBranch(listed.branches, preferred: preferred),
  );
}
