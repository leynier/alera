import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automation_workspace_tags.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_advanced_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String automationDraftTargetLine(
  AutomationDraft draft,
  AutomationWorkbenchContext names,
) {
  String? value(AutomationDraftField field) => draft.field(field);
  final profile = value(.agentProfileId) == null
      ? ''
      : ' with ${names.profileName(value(.agentProfileId))}';
  return switch (draft.targetType) {
    null => 'No target chosen',
    AutomationTargetType.freshTab =>
      'New agent tab in ${names.workspaceName(value(.workspaceId))}$profile',
    AutomationTargetType.projectWorktree =>
      'New workspace and worktree of ${names.projectName(value(.projectId))} from ${value(.sourceBranch) ?? 'its default branch'}$profile',
    AutomationTargetType.managedWorkspace =>
      'New worktree from ${names.workspaceName(value(.workspaceId))} on ${value(.sourceBranch) ?? 'its branch'}$profile',
    AutomationTargetType.projectCheckout =>
      'Project folder of ${names.projectName(value(.projectId))} on ${names.hostName(value(.hostId))}$profile',
    AutomationTargetType.existingTab =>
      'The agent conversation in ${names.workspaceName(value(.workspaceId))}',
  };
}

class AutomationReviewStep extends ConsumerStatefulWidget {
  const AutomationReviewStep({super.key, required this.provider});

  final AutomationAuthoringControllerProvider provider;

  @override
  ConsumerState<AutomationReviewStep> createState() =>
      _AutomationReviewStepState();
}

class _AutomationReviewStepState extends ConsumerState<AutomationReviewStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(widget.provider.notifier).checkReadiness());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final names = ref.watch(automationWorkbenchContextProvider);
    final draft = state.draft;
    final theme = Theme.of(context);
    final readiness = state.readiness;
    final rows = <(String, String)>[
      ('Name', draft.effectiveName),
      ('Prompt', draft.promptTemplate.trim()),
      ('When', draft.schedule.describe(timezone: draft.timezone)),
      ('Where', automationDraftTargetLine(draft, names)),
      if (names.workspace(draft.originWorkspaceId) case final origin?)
        ('Shown In', origin.name),
      if (draft.targetType?.createsWorkspace == true) ...<(String, String)>[
        if (draft.workspaceSectionId case final section?)
          ('Section', names.sectionName(section)),
        if (draft.workspaceTagIds.isNotEmpty)
          (
            'Tags',
            automationWorkspaceTagNames(
              draft.workspaceTagIds,
              ref.watch(automationWorkspaceTagsProvider).value,
            ),
          ),
      ],
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
            child: Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                SizedBox(
                  width: AleraTokens.automationInfoLabelWidth,
                  child: Text(label, style: theme.textTheme.bodySmall),
                ),
                Expanded(child: Text(value, maxLines: 4, overflow: .ellipsis)),
              ],
            ),
          ),
        const SizedBox(height: AleraTokens.space12),
        if (state.checking)
          const LinearProgressIndicator()
        else if (readiness == null)
          Text(
            'The runtime checks the target, agent profile and host when you save.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          )
        else if (readiness.issues.isEmpty)
          const AleraInlineNotice(
            message: 'Ready. The runtime found nothing to fix.',
          )
        else
          for (final issue in readiness.issues) ...<Widget>[
            AleraInlineNotice(
              tone: issue.isError ? .error : .warning,
              message: issue.action == null
                  ? issue.message
                  : '${issue.message} ${issue.action}',
            ),
            const SizedBox(height: AleraTokens.space6),
          ],
        const SizedBox(height: AleraTokens.space12),
        AutomationAdvancedSection(
          provider: widget.provider,
          initiallyExpanded: draft.numberErrors.isNotEmpty,
        ),
      ],
    );
  }
}
