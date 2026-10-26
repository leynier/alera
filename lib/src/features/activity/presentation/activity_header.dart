import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/presentation/automations_section.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_tasks_section.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_dialog.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/presentation/ask_agent_dialog.dart';
import 'package:alera/src/features/inbox/presentation/questions_section.dart';
import 'package:alera/src/features/runs/presentation/new_run_dialog.dart';
import 'package:alera/src/features/runs/presentation/runs_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Title row of Activity: the app menu, the visible section's primary action,
/// the way back to the workspace and a refresh of the visible section.
class const ActivityHeader({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(
      activityNavigationProvider.select((value) => value.section),
    );
    final navigation = ref.read(activityNavigationProvider.notifier);
    return Wrap(
      spacing: AleraTokens.space12,
      runSpacing: AleraTokens.space8,
      crossAxisAlignment: .center,
      children: <Widget>[
        const AleraAppMenuButton(),
        Text('Activity', style: Theme.of(context).textTheme.titleLarge),
        _PrimaryAction(section: section),
        TextButton.icon(
          key: const ValueKey<String>('activityReturnToWorkspace'),
          onPressed: navigation.close,
          icon: const Icon(AleraIcons.back),
          label: const Text('Return to Workspace'),
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(AleraIcons.refresh),
          onPressed: () => _refresh(ref, section),
        ),
      ],
    );
  }

  void _refresh(WidgetRef ref, ActivitySection section) {
    switch (section) {
      case ActivitySection.runs:
        refreshRuns(ref, ref.read(activityNavigationProvider).runs);
      case ActivitySection.questions:
        refreshQuestions(ref);
      case ActivitySection.automations:
        ref.invalidate(automationCatalogProvider);
      case ActivitySection.chatTasks:
        refreshChatTasks(ref, ref.read(activityNavigationProvider).chatTasks);
    }
  }
}

class const _PrimaryAction({required final ActivitySection section})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const key = ValueKey<String>('activityPrimaryAction');
    const icon = Icon(AleraIcons.add, size: AleraTokens.iconMd);
    return switch (section) {
      ActivitySection.runs => FilledButton.icon(
        key: key,
        onPressed: () => unawaited(showNewRunDialog(context)),
        icon: icon,
        label: const Text('New Run'),
      ),
      ActivitySection.questions => FilledButton.icon(
        key: key,
        onPressed:
            ref.watch(
              inboxSummaryProvider.select(
                (value) => value.error is InboxUpdateRequired,
              ),
            )
            ? null
            : () => unawaited(showAskAgentDialog(context)),
        icon: icon,
        label: const Text('Ask Agent'),
      ),
      ActivitySection.automations => FilledButton.icon(
        key: key,
        onPressed: () =>
            unawaited(startAutomationAuthoringFromSection(context, ref)),
        icon: icon,
        label: const Text('New Automation'),
      ),
      ActivitySection.chatTasks => FilledButton.icon(
        key: key,
        onPressed: ref.watch(chatTasksSupportedProvider).value ?? false
            ? () => unawaited(showDelegateChatTaskDialog(context))
            : null,
        icon: icon,
        label: const Text('Delegate Task'),
      ),
    };
  }
}
