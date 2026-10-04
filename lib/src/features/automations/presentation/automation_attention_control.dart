import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status bar entry that only appears while an automation needs attention.
class const AutomationAttentionControl({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      automationCatalogProvider.select(
        (value) => (value.value ?? const <AutomationRecord>[])
            .where(AutomationBucket.needsAttention.contains)
            .length,
      ),
    );
    if (count == 0) return const SizedBox.shrink();
    final label =
        'Open Automations · $count ${count == 1 ? 'Automation Needs' : 'Automations Need'} Attention';
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: () {
          final navigation = ref.read(automationsNavigationProvider.notifier);
          navigation.open(scope: AutomationScope.all);
          navigation.setFilters(
            const AutomationCatalogFilters(
              bucket: AutomationBucket.needsAttention,
            ),
          );
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                AleraIcons.checks,
                size: AleraTokens.iconSm,
                color: AleraTokens.warning,
              ),
              const SizedBox(width: AleraTokens.space4),
              Text(
                count > 999 ? '999+' : '$count',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AleraTokens.warning),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
