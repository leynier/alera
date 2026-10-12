import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_attention_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/application/run_attention_link.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/activity/presentation/activity_rail.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/runs/application/run_board_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The status-bar tooltip: the total, plus every section the host could not
/// answer, since those are left out of the total rather than guessed.
String activityAttentionTooltip(ActivityAttention attention) {
  final total = attention.total;
  final parts = <String>[
    'Open Activity',
    if (total > 0)
      '$total ${total == 1 ? 'item needs' : 'items need'} attention',
    if (attention.unavailable.isNotEmpty)
      '${_sectionList(attention.unavailable)} unavailable',
  ];
  return parts.join(' · ');
}

String _sectionList(Set<ActivitySection> sections) {
  final labels = <String>[
    for (final section in ActivitySection.values)
      if (sections.contains(section)) section.label,
  ];
  if (labels.length == 1) return labels.single;
  return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
}

AleraAttentionTone activityAttentionTone(ActivityAttention attention) =>
    attention.hasBlockingWork
    ? AleraAttentionTone.warning
    : attention.questions > 0
    ? AleraAttentionTone.accent
    : AleraAttentionTone.muted;

/// Status-bar entry to Activity. Clicking opens the page where it was left;
/// the hover card lists what needs attention per section and deep-links.
class const ActivityAttentionControl({super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<ActivityAttentionControl> createState() =>
      _ActivityAttentionControlState();
}

class _ActivityAttentionControlState
    extends ConsumerState<ActivityAttentionControl> {
  final AleraHoverCardController _hoverCard = AleraHoverCardController();

  void _navigate(void Function(ActivityNavigation navigation) action) {
    _hoverCard.dismiss();
    action(ref.read(activityNavigationProvider.notifier));
  }

  void _openSection(ActivitySection section, ActivityAttention attention) =>
      _navigate((navigation) {
        final count = attention.countFor(section);
        switch (section) {
          case ActivitySection.runs:
            navigation.open(section);
            if (count > 0) navigation.filterRunBucket(RunBucket.attention);
          case ActivitySection.questions:
            navigation.openQuestions();
          case ActivitySection.automations:
            if (count > 0) {
              navigation.openAutomations(
                scope: AutomationScope.all,
                filters: const AutomationCatalogFilters(
                  bucket: AutomationBucket.needsAttention,
                ),
              );
            } else {
              navigation.open(section);
            }
        }
      });

  Future<void> _openRun(RunSummary run) {
    _hoverCard.dismiss();
    return openRunAttention(
      ref.read(runRepositoryProvider),
      ref.read(activityNavigationProvider.notifier),
      run.id,
      gateId: run.pendingGates.firstOrNull?.id,
      mounted: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final attention = ref.watch(activityAttentionProvider);
    return AleraHoverCard(
      controller: _hoverCard,
      // The chip runs its own InkWell, which would win the gesture arena over
      // the card's detector, and a click opens Activity instead of pinning.
      pinOnTap: false,
      semanticsLabel: 'Activity',
      card: _ActivityAttentionCard(
        attention: attention,
        runs:
            ref.watch(runBoardAttentionProvider).value?.items ??
            const <RunSummary>[],
        now: ref.watch(runClockProvider)(),
        onRun: (run) => unawaited(_openRun(run)),
        onSection: (section) => _openSection(section, attention),
        onViewAll: () => _navigate((navigation) => navigation.open()),
      ),
      child: AleraAttentionChip(
        key: const ValueKey<String>('activityAttentionChip'),
        icon: AleraIcons.workspaceChildren,
        count: attention.total,
        tone: activityAttentionTone(attention),
        tooltip: activityAttentionTooltip(attention),
        onPressed: () => _navigate((navigation) => navigation.open()),
      ),
    );
  }
}

class const _ActivityAttentionCard({
  required final ActivityAttention attention,
  required final List<RunSummary> runs,
  required final DateTime now,
  required final ValueChanged<RunSummary> onRun,
  required final ValueChanged<ActivitySection> onSection,
  required final VoidCallback onViewAll,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: AleraTokens.contextMenuWidth,
        padding: const EdgeInsets.all(AleraTokens.space8),
        decoration: BoxDecoration(
          color: AleraTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.border),
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space4),
              child: Text('Activity', style: theme.textTheme.titleSmall),
            ),
            for (final section in ActivitySection.values) ...<Widget>[
              HoverContainer(
                key: ValueKey<String>('activityAttention:${section.name}'),
                onTap: () => onSection(section),
                borderRadius: AleraTokens.radiusSm,
                padding: const EdgeInsets.all(AleraTokens.space6),
                child: Row(
                  children: <Widget>[
                    Icon(
                      activitySectionIcon(section),
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          Text(section.label, style: theme.textTheme.bodySmall),
                          Text(
                            _summary(section),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (section == ActivitySection.runs &&
                  !attention.unavailable.contains(section))
                for (final run in runs)
                  HoverContainer(
                    key: ValueKey<String>('activityAttentionRun:${run.id}'),
                    onTap: () => onRun(run),
                    borderRadius: AleraTokens.radiusSm,
                    padding: const EdgeInsets.fromLTRB(
                      AleraTokens.space24 + AleraTokens.space6,
                      AleraTokens.space4,
                      AleraTokens.space6,
                      AleraTokens.space4,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: <Widget>[
                        Text(
                          run.objective.isEmpty ? run.id : run.objective,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          <String>[
                            ?runAttentionLabel(run),
                            runAgeLabel(run.lastActivityAt, now),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onViewAll,
                child: const Text('View All'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(ActivitySection section) {
    if (attention.unavailable.contains(section)) {
      return 'Unavailable on this host';
    }
    final count = attention.countFor(section);
    final label = AleraAttentionChip.formatCount(count);
    return switch (section) {
      ActivitySection.runs =>
        count == 0
            ? 'No runs need attention'
            : '$label ${count == 1 ? 'run needs' : 'runs need'} attention',
      ActivitySection.questions =>
        count == 0
            ? 'No unread replies'
            : '$label unread ${count == 1 ? 'reply' : 'replies'}',
      ActivitySection.automations =>
        count == 0
            ? 'No automations need attention'
            : '$label ${count == 1 ? 'automation needs' : 'automations need'} attention',
    };
  }
}
