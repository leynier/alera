import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_confirmations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Picks the agent profile that runs each new tab.
Future<void> showMobileAutomationAgentSheet(
  BuildContext context,
  WidgetRef ref,
  MobileAutomationComposerControllerProvider provider,
  MobileAutomationContext names,
) async {
  if (names.profiles.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No agent profiles yet. Add one in Alera on the paired computer.',
        ),
      ),
    );
    return;
  }
  final current = ref.read(provider).draft.field(.agentProfileId);
  final picked = await showAleraActionSheet<String>(
    context,
    entries: <AleraActionSheetEntry<String>>[
      for (final profile in names.profiles)
        AleraActionSheetEntry<String>(
          value: profile.id,
          label: profile.name,
          leading: Icon(
            profile.id == current ? AleraIcons.check : AleraIcons.agent,
          ),
        ),
    ],
  );
  if (picked == null) return;
  ref
      .read(provider.notifier)
      .update((draft) => draft.withTargetField(.agentProfileId, picked));
}

/// Whether later runs return to what the first run created, plus the bound
/// destination of an automation being edited.
Future<void> showMobileAutomationReuseSheet(
  BuildContext context,
  MobileAutomationComposerControllerProvider provider,
  MobileAutomationContext names,
) => showMobileAutomationComposerSheet(
  context,
  title: 'Reuse',
  builder: (context, close) =>
      _ReuseEditor(provider: provider, names: names, close: close),
);

class const _ReuseEditor({
  required final MobileAutomationComposerControllerProvider provider,
  required final MobileAutomationContext names,
  required final VoidCallback close,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final draft = state.draft;
    final editing = state.editing;
    final bound = editing?.boundTarget;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        if (automationReusePolicyIsFixed(draft.targetType))
          Text(
            'Every run continues the chosen conversation while it is available.',
            style: muted,
          )
        else
          for (final policy in applicableReusePolicies(draft.targetType))
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: AleraTokens.minTapTarget,
              title: Text(policy.label),
              subtitle: Text(policy.description),
              selected: policy == draft.reusePolicy,
              trailing: policy == draft.reusePolicy
                  ? const Icon(AleraIcons.check, size: AleraTokens.iconMd)
                  : null,
              onTap: () {
                ref
                    .read(provider.notifier)
                    .update((current) => current.copyWith(reusePolicy: policy));
                close();
              },
            ),
        if (bound != null) ...<Widget>[
          const Divider(height: AleraTokens.spaceXl),
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.link,
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.spaceSm),
              Expanded(
                child: Text(
                  'Bound to ${editing?.boundTargetSummary ?? names.workspaceName(bound.workspaceId)}',
                  style: muted,
                ),
              ),
              TextButton(
                onPressed: () => unawaited(() async {
                  if (!await confirmMobileAutomationUnbind(context)) return;
                  await ref.read(provider.notifier).unbind();
                }()),
                child: const Text('Unbind'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
