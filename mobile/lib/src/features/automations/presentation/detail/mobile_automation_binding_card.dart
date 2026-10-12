import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_confirmations.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';

/// Where a reusing automation returns to: not bound yet, bound (with Open
/// and Unbind), or bound to a workspace that is gone. Hidden for automations
/// that start fresh every run and for runtimes without reuse.
class const MobileAutomationBindingCard({
  required final String hostId,
  required final AutomationRecord automation,
  required final MobileAutomationContext names,
  required final MobileAutomationActions actions,
  required final bool supportsReuse,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final automation = this.automation;
    if (!supportsReuse || !automation.reusePolicy.reuses) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final bound = automation.boundTarget;
    final workspace = bound == null ? null : names.workspace(bound.workspaceId);
    final workspaceGone = bound != null && workspace == null;
    var summary =
        automation.boundTargetSummary ??
        (bound == null ? '' : names.workspaceName(bound.workspaceId));
    // The runtime marks what it could not find; mark a workspace this phone
    // no longer lists the same way.
    if (workspaceGone && !summary.contains('(missing)')) {
      summary = '$summary (missing)';
    }
    final stale = summary.contains('(missing)');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.link,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Text(
                  automation.reusePolicy.label,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space6),
            if (bound == null)
              Text(
                'Not bound yet. The next run creates its destination, and later runs return to it.',
                style: muted,
              )
            else if (stale)
              AleraNotice(
                icon: AleraIcons.warning,
                message: workspaceGone
                    ? 'Bound to $summary. The next run creates a new workspace.'
                    : 'Bound to $summary. The next run opens a new agent tab in this workspace.',
              )
            else
              Text('Bound to $summary', style: theme.textTheme.bodyMedium),
            if (bound != null) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceSm),
              Wrap(
                spacing: AleraTokens.spaceSm,
                children: <Widget>[
                  if (workspace != null)
                    OutlinedButton(
                      onPressed: () => unawaited(
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkspaceTabsScreen(
                              hostId: hostId,
                              workspace: workspace,
                              initialTabId: bound.tabId,
                              selectFallbackTab: bound.tabId == null,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  TextButton(
                    onPressed: () => unawaited(() async {
                      if (await confirmMobileAutomationUnbind(context)) {
                        await actions.unbind(automation);
                      }
                    }()),
                    child: const Text('Unbind'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
