import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_more_menu.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _RunNowOption { withoutPrecheck, queue, parallel }

/// Name, state, description and the lifecycle actions of one automation.
/// [onBack] returns to the catalog when the page is too narrow to show both.
class const AutomationDetailHeader({
  required final AutomationRecord automation,
  final VoidCallback? onBack,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final automation = this.automation;
    final actions = AutomationActions(ref);
    final state = automation.state;
    final status = automationStateLabel(automation);
    final hasActiveRuns = automation.activeRunCount > 0;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (onBack case final back?) ...<Widget>[
              AleraIconButton(
                tooltip: 'Back To Automations',
                icon: AleraIcons.back,
                onPressed: back,
              ),
              const SizedBox(width: AleraTokens.space8),
            ],
            Flexible(
              child: Text(
                automation.name,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w600),
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ),
            const SizedBox(width: AleraTokens.space12),
            AutomationToneBadge(label: status.label, tone: status.tone),
          ],
        ),
        if (automation.description.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            automation.description.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
        const SizedBox(height: AleraTokens.space12),
        Wrap(
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
                child: Text(
                  hasActiveRuns ? 'Pause · Runs Keep Going' : 'Pause',
                ),
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
            if (automation.isEditable)
              OutlinedButton.icon(
                onPressed: () => unawaited(
                  showAutomationComposerDialog(
                    context,
                    ref,
                    request: AutomationAuthoringRequest(editId: automation.id),
                  ),
                ),
                icon: const Icon(AleraIcons.edit, size: AleraTokens.iconMd),
                label: Text(
                  automation.attention == null ? 'Edit' : 'Fix Problem',
                ),
              ),
            AutomationMoreMenuButton(automation: automation),
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
