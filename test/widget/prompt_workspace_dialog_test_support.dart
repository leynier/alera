part of 'prompt_workspace_dialog_test.dart';

class _PromptSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

Project _project({
  required String id,
  required String name,
  required DateTime now,
}) {
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/${name.toLowerCase()}',
    createdAt: now,
    updatedAt: now,
  );
}

AgentProfile _profile({
  required String id,
  required String name,
  String agentType = 'codex',
  String command = 'codex',
  required DateTime now,
}) {
  return AgentProfile(
    id: id,
    name: name,
    agentType: agentType,
    command: command,
    createdAt: now,
    updatedAt: now,
  );
}

Workspace _workspace({
  required String id,
  required String projectId,
  required String name,
  required String branch,
  required WorkspaceKind kind,
  required DateTime now,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: branch,
    path: '/repo/$projectId/$id',
    kind: kind,
    status: .active,
    createdAt: now,
    updatedAt: now,
  );
}
