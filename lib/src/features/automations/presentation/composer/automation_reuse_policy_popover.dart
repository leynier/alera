import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/presentation/automation_destructive_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_popover_chip.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether later runs return to what the first run created. Only shown when
/// the runtime advertises [automationReuseCapability].
class const AutomationReusePolicyChip({
  required final AutomationComposerControllerProvider provider,
  required final bool hasError,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final fixed = automationReusePolicyIsFixed(draft.targetType);
    return AutomationPopoverChip(
      icon: AleraIcons.link,
      label: 'Reuse',
      value: fixed
          ? automationContinuesConversationLabel
          : draft.reusePolicy.label,
      tooltip: 'Reuse',
      hasError: hasError,
      width: AleraTokens.dialogCompactWidth,
      builder: (context, close) =>
          _ReusePolicyMenu(provider: provider, close: close),
    );
  }
}

class const _ReusePolicyMenu({
  required final AutomationComposerControllerProvider provider,
  required final VoidCallback close,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final draft = state.draft;
    final editing = state.editing;
    final names = ref.watch(automationWorkbenchContextProvider);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final bound = editing?.boundTarget;
    final children = <Widget>[
      if (automationReusePolicyIsFixed(draft.targetType))
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space8),
          child: Text(
            'Every run continues the chosen conversation while it is available.',
            style: muted,
          ),
        )
      else
        for (final policy in applicableReusePolicies(draft.targetType))
          AleraMenuItem(
            label: policy.label,
            subtitle: policy.description,
            selected: policy == draft.reusePolicy,
            onTap: () {
              ref
                  .read(provider.notifier)
                  .update((current) => current.copyWith(reusePolicy: policy));
              close();
            },
          ),
      if (bound != null) ...<Widget>[
        const Divider(height: AleraTokens.space12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          child: Row(
            children: <Widget>[
              const Icon(
                AleraIcons.link,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  'Bound to ${editing?.boundTargetSummary ?? names.workspaceName(bound.workspaceId)}',
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: muted,
                ),
              ),
              TextButton(
                onPressed: () => unawaited(() async {
                  if (!await confirmAutomationUnbind(context)) return;
                  await ref.read(provider.notifier).unbind();
                }()),
                child: const Text('Unbind'),
              ),
            ],
          ),
        ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space4),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: children,
      ),
    );
  }
}
