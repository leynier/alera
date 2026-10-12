import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/presentation/automation_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_destructive_actions.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a reusing automation returns to: not bound yet, bound (with Open
/// and Unbind), or bound to a workspace that is gone. Hidden for automations
/// that start fresh every run and for runtimes without reuse.
class const AutomationBindingCard({
  required final AutomationRecord automation,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reuse =
        ref.watch(automationRuntimeCapabilitiesProvider).value?.reuse ?? false;
    final automation = this.automation;
    if (!reuse || !automation.reusePolicy.reuses) {
      return const SizedBox.shrink();
    }
    final names = ref.watch(automationWorkbenchContextProvider);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final actions = AutomationActions(ref);
    final bound = automation.boundTarget;
    final workspaceGone =
        bound != null && names.workspace(bound.workspaceId) == null;
    var summary =
        automation.boundTargetSummary ??
        (bound == null ? '' : names.workspaceName(bound.workspaceId));
    // The runtime marks what it could not find; mark a workspace this client
    // no longer lists the same way.
    if (workspaceGone && !summary.contains('(missing)')) {
      summary = '$summary (missing)';
    }
    final stale = summary.contains('(missing)');
    Future<void> unbind() async {
      if (await confirmAutomationUnbind(context)) {
        await actions.unbind(automation);
      }
    }

    return AleraPanel(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
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
                  const SizedBox(width: AleraTokens.space8),
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
                AleraInlineNotice(
                  tone: .warning,
                  message: workspaceGone
                      ? 'Bound to $summary. The next run creates a new workspace.'
                      : 'Bound to $summary. The next run opens a new agent tab in this workspace.',
                )
              else
                Text('Bound to $summary', style: theme.textTheme.bodySmall),
              if (bound != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                Wrap(
                  spacing: AleraTokens.space8,
                  children: <Widget>[
                    if (!workspaceGone)
                      OutlinedButton(
                        onPressed: () =>
                            unawaited(actions.openBoundTarget(bound)),
                        child: const Text('Open'),
                      ),
                    TextButton(
                      onPressed: () => unawaited(unbind()),
                      child: const Text('Unbind'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
