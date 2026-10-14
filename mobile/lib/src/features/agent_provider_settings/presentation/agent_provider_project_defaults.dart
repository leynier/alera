import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_model_picker_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:flutter/material.dart';

/// Per-project agent for new chats. A project default wins over Default For
/// New Chats, so a repository that needs one agent gets it everywhere.
class const AgentProviderProjectDefaults({
  super.key,
  required final List<ProjectSummary> projects,
  required final List<AgentChatProviderInstance> providers,
  required final AgentChatPreferences preferences,
  required final Future<void> Function(
    String projectId,
    AgentChatSelection? selection,
  )
  onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        const SizedBox(height: AleraTokens.spaceXl),
        Text(
          'Project Defaults',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Column(
            children: <Widget>[
              for (final project in projects)
                _row(context, project, preferences.projectDefaults[project.id]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ProjectSummary project,
    AgentChatSelection? selection,
  ) => ListTile(
    key: ValueKey<String>('project-default-${project.id}'),
    title: Text(project.name, overflow: .ellipsis),
    subtitle: Text(
      selection == null ? 'Uses Default For New Chats' : _label(selection),
      overflow: .ellipsis,
    ),
    trailing: selection == null
        ? const Icon(AleraIcons.chevronRight)
        : IconButton(
            tooltip: 'Clear Project Default',
            onPressed: () => unawaited(onChanged(project.id, null)),
            icon: const Icon(AleraIcons.close),
          ),
    onTap: () async {
      final picked = await showAgentChatModelPicker(
        context,
        providers: providers,
        preferences: preferences,
        current: selection,
        canSwitchProvider: true,
      );
      if (picked != null) await onChanged(project.id, picked);
    },
  );

  String _label(AgentChatSelection selection) {
    AgentChatProviderInstance? instance;
    for (final candidate in providers) {
      if (candidate.id == selection.providerInstanceId) instance = candidate;
    }
    return <String>[
      instance?.label ?? selection.providerInstanceId,
      if (selection.model case final model?)
        instance?.modelById(model)?.label ?? model,
    ].join(' · ');
  }
}
