import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_dialog.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Agent dispatch', group: 'Agent task dispatch')
Widget agentTaskDispatchDialogPreview() {
  final now = DateTime.utc(2026, 9, 7);
  final tab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: 'workspace-1',
    title: 'Codex',
    createdAt: now,
    updatedAt: now,
  );
  return SizedBox(
    width: 440,
    height: 420,
    child: AgentTaskDispatchDialog(
      request: const AgentTaskDispatchRequest(
        workspaceId: 'workspace-1',
        prompt: 'Fix the failing pull request checks.',
        message: 'Choose a running agent or open a new tab from a profile.',
      ),
      catalog: AgentTaskDispatchCatalog(
        runningAgents: <WorkspaceAgentRun>[
          WorkspaceAgentRun(
            tab: tab,
            status: AgentStatusEntry(
              terminalSessionId: tab.terminalSessionId,
              workspaceId: tab.workspaceId,
              tabId: tab.id,
              agentType: .codex,
              state: .done,
              prompt: 'Previous turn',
              updatedAt: now,
              stateStartedAt: now,
            ),
          ),
        ],
        profiles: <AgentProfile>[
          AgentProfile(
            id: 'profile-1',
            name: 'Codex Builder',
            agentType: 'codex',
            command: 'codex',
            description: 'Implementation',
            createdAt: now,
            updatedAt: now,
          ),
          AgentProfile(
            id: 'profile-2',
            name: 'Claude Reviewer',
            agentType: 'claude',
            command: 'claude',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        defaultProfileId: 'profile-1',
      ),
    ),
  );
}
