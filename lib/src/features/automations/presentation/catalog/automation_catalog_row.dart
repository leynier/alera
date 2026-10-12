import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_more_menu.dart';
import 'package:alera/src/features/automations/presentation/automation_tone.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String automationScheduleLine(AutomationRecord automation) {
  if (automation.isCompleted) return 'Completed';
  final description = automationScheduleDescription(automation.schedule);
  final next = automation.nextRunAt;
  if (next == null || automation.state != 'active') return description;
  return '$description · next ${automationRelativeTime(next)}';
}

/// "Succeeded 5m ago" for the last run of a definition.
String automationLastRunLabel(AutomationLastRun run) {
  final status = automationRunStatusLabel(
    AutomationRunRecord(
      id: run.id,
      automationId: '',
      number: 0,
      status: run.status,
      trigger: '',
      summary: run.summary,
      error: null,
      scheduledAt: null,
      finishedAt: run.finishedAt,
    ),
  ).label;
  final finished = run.finishedAt;
  return finished == null
      ? status
      : '$status ${automationRelativeTime(finished)}';
}

/// One definition in the catalog. Hovering or focusing it reveals its quick
/// actions in space the row always reserves, so nothing shifts.
class AutomationCatalogRow extends ConsumerStatefulWidget {
  const AutomationCatalogRow({
    super.key,
    required this.automation,
    required this.names,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final AutomationRecord automation;
  final AutomationWorkbenchContext names;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  ConsumerState<AutomationCatalogRow> createState() =>
      _AutomationCatalogRowState();
}

class _AutomationCatalogRowState extends ConsumerState<AutomationCatalogRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final automation = widget.automation;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final state = automationStateLabel(automation);
    final lastRun = automation.lastRun;
    final readinessError = automation.isEditable
        ? automation.readiness?.errors.firstOrNull?.message
        : null;
    final alert = automation.attention?.message ?? readinessError;
    final details = Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                automation.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AleraTokens.space6),
            AutomationToneBadge(label: state.label, tone: state.tone),
          ],
        ),
        Text(
          automationScheduleLine(automation),
          maxLines: 1,
          overflow: .ellipsis,
          style: muted,
        ),
        Text(
          automationRecordTargetSummary(automation, widget.names),
          maxLines: 1,
          overflow: .ellipsis,
          style: muted,
        ),
        if (automation.boundTargetSummary case final bound?)
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.link,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space4),
              Flexible(
                child: Text(
                  'bound: $bound',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: muted,
                ),
              ),
            ],
          ),
        if (alert != null)
          Text(
            alert,
            maxLines: 2,
            overflow: .ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: automation.attention != null
                  ? AleraTokens.warning
                  : AleraTokens.error,
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: AleraActiveRail(
            active: widget.selected,
            child: Material(
              color: widget.selected
                  ? AleraActiveRail.selectedColor
                  : Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                    vertical: AleraTokens.space8,
                  ),
                  child: Row(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: AleraTokens.space6),
                        child: Tooltip(
                          message: lastRun == null
                              ? 'No runs yet'
                              : 'Last run: ${automationLastRunLabel(lastRun)}',
                          child: AleraStatusDot(
                            active: lastRun != null,
                            color: lastRun == null
                                ? null
                                : automationToneColor(
                                    automationRunStatusTone(lastRun.status),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Expanded(child: details),
                      Visibility(
                        visible: _hovered || _focused || widget.selected,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: _RowActions(
                          automation: automation,
                          onEdit: widget.onEdit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _RowActions({
  required final AutomationRecord automation,
  required final VoidCallback onEdit,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = AutomationActions(ref);
    final automation = this.automation;
    final (String, IconData, Future<void> Function())? toggle =
        switch (automation.state) {
          'draft' => (
            'Activate',
            AleraIcons.play,
            () => actions.activate(automation),
          ),
          'active' => (
            'Pause',
            AleraIcons.pause,
            () => actions.pause(automation),
          ),
          'paused' || 'blocked' => (
            'Resume',
            AleraIcons.play,
            () => actions.resume(automation),
          ),
          'trashed' => (
            'Restore',
            AleraIcons.restore,
            () => actions.restore(automation),
          ),
          _ => null,
        };
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (!automation.isTrashed)
          AleraIconButton(
            tooltip: automation.isCompleted ? 'Run Again' : 'Run Now',
            icon: AleraIcons.agent,
            onPressed: () => unawaited(actions.runNow(automation)),
          ),
        if (toggle case (final label, final icon, final run))
          AleraIconButton(
            tooltip: label,
            icon: icon,
            onPressed: () => unawaited(run()),
          ),
        if (automation.isEditable)
          AleraIconButton(
            tooltip: 'Edit',
            icon: AleraIcons.edit,
            onPressed: onEdit,
          ),
        AutomationMoreMenuButton(automation: automation),
      ],
    );
  }
}
