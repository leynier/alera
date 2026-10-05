import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_dialog.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_catalog_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_tabs.dart';
import 'package:alera/src/features/automations/presentation/automation_list_tile.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _MoreAction { clone, saveTemplate, pauseAndCancel, trash }

enum _RunNowOption { withoutPrecheck, queue, parallel }

class const AutomationDetailView({
  required final AutomationRecord automation,
  final String? selectedRunId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(automationDetailControllerProvider(automation.id));
    final theme = Theme.of(context);
    final state = automationStateLabel(automation);
    final value = detail.value;
    final names = ref.watch(automationWorkbenchContextProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space24,
        AleraTokens.space16,
        AleraTokens.space24,
        0,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  automation.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: .w600,
                  ),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
              const SizedBox(width: AleraTokens.space12),
              AutomationToneBadge(label: state.label, tone: state.tone),
            ],
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            '${automationScheduleLine(automation)} · ${automationTargetLine(automation, names)}',
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space16),
          _AutomationHeaderActions(automation: automation),
          const SizedBox(height: AleraTokens.space8),
          Expanded(
            child: value == null
                ? detail.hasError
                      ? AleraEmptyState(
                          icon: AleraIcons.error,
                          title: 'Automation Unavailable',
                          message: '${detail.error}',
                          action: FilledButton(
                            onPressed: () => ref.invalidate(
                              automationDetailControllerProvider(automation.id),
                            ),
                            child: const Text('Retry'),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator())
                : AutomationDetailTabs(
                    automation: automation,
                    detail: value,
                    selectedRunId: selectedRunId,
                  ),
          ),
        ],
      ),
    );
  }
}

class const _AutomationHeaderActions({
  required final AutomationRecord automation,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = AutomationActions(ref);
    final automation = this.automation;
    final state = automation.state;
    final editable = automation.isEditable;
    final hasActiveRuns = automation.activeRunCount > 0;
    Future<void> edit() => showAutomationAuthoringDialog(
      context,
      ref,
      request: AutomationAuthoringRequest(editId: automation.id),
    );
    return Wrap(
      spacing: AleraTokens.space8,
      runSpacing: AleraTokens.space8,
      crossAxisAlignment: .center,
      children: <Widget>[
        if (state == 'draft')
          FilledButton(
            onPressed: () => unawaited(actions.activate(automation)),
            child: const Text('Activate'),
          ),
        if (state == 'active')
          OutlinedButton(
            onPressed: () => unawaited(actions.pause(automation)),
            child: Text(hasActiveRuns ? 'Pause · Runs Keep Going' : 'Pause'),
          ),
        if (state == 'paused' || state == 'blocked')
          FilledButton(
            onPressed: () => unawaited(actions.resume(automation)),
            child: const Text('Resume'),
          ),
        if (state == 'trashed')
          FilledButton(
            onPressed: () => unawaited(actions.restore(automation)),
            child: const Text('Restore'),
          )
        else
          _RunNowButton(automation: automation),
        if (editable)
          OutlinedButton.icon(
            onPressed: () => unawaited(edit()),
            icon: const Icon(AleraIcons.edit, size: AleraTokens.iconMd),
            label: Text(automation.attention == null ? 'Edit' : 'Fix Problem'),
          ),
        PopupMenuButton<_MoreAction>(
          tooltip: 'More Actions',
          icon: const Icon(AleraIcons.more),
          onSelected: (action) => unawaited(switch (action) {
            _MoreAction.clone => showAutomationAuthoringDialog(
              context,
              ref,
              request: AutomationAuthoringRequest(cloneId: automation.id),
            ),
            _MoreAction.saveTemplate => saveAutomationTemplate(ref, automation),
            _MoreAction.pauseAndCancel => actions.pause(
              automation,
              cancelRuns: true,
            ),
            _MoreAction.trash => actions.trash(automation),
          }),
          itemBuilder: (_) => <PopupMenuEntry<_MoreAction>>[
            const AleraDropdownEntry(
              value: _MoreAction.clone,
              leading: Icon(AleraIcons.copy, size: AleraTokens.iconMd),
              label: 'Clone',
            ),
            const AleraDropdownEntry(
              value: _MoreAction.saveTemplate,
              leading: Icon(AleraIcons.file, size: AleraTokens.iconMd),
              label: 'Save As Template',
            ),
            if (state == 'active')
              const AleraDropdownEntry(
                value: _MoreAction.pauseAndCancel,
                leading: Icon(AleraIcons.blocked, size: AleraTokens.iconMd),
                label: 'Pause And Cancel Runs',
              ),
            if (state != 'trashed')
              const AleraDropdownEntry(
                value: _MoreAction.trash,
                leading: Icon(AleraIcons.delete, size: AleraTokens.iconMd),
                label: 'Move To Trash',
              ),
          ],
        ),
      ],
    );
  }
}

/// One click runs with the definition's own precheck and overlap policy; the
/// menu offers the explicit overrides.
class const _RunNowButton({required final AutomationRecord automation})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = AutomationActions(ref);
    final label = automation.isCompleted ? 'Run Again' : 'Run Now';
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: () => unawaited(actions.runNow(automation)),
          icon: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
          label: Text(label),
        ),
        PopupMenuButton<_RunNowOption>(
          tooltip: '$label Options',
          icon: const Icon(AleraIcons.chevronDown),
          onSelected: (option) => unawaited(switch (option) {
            _RunNowOption.withoutPrecheck => actions.runNow(
              automation,
              precheck: false,
            ),
            _RunNowOption.queue => actions.runNow(automation, overlap: 'queue'),
            _RunNowOption.parallel => actions.runNow(
              automation,
              overlap: 'forceParallel',
            ),
          }),
          itemBuilder: (_) => <PopupMenuEntry<_RunNowOption>>[
            if (automation.precheck != null)
              const AleraDropdownEntry(
                value: _RunNowOption.withoutPrecheck,
                label: 'Run Without Precheck',
              ),
            const AleraDropdownEntry(
              value: _RunNowOption.queue,
              label: 'Queue After Active Run',
            ),
            const AleraDropdownEntry(
              value: _RunNowOption.parallel,
              label: 'Run In Parallel',
            ),
          ],
        ),
      ],
    );
  }
}
