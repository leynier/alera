import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_rail.dart';
import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

IconData activitySectionIcon(ActivitySection section) => switch (section) {
  ActivitySection.runs => AleraIcons.workspaceChildren,
  ActivitySection.questions => AleraIcons.inbox,
  ActivitySection.automations => AleraIcons.checks,
  ActivitySection.chatTasks => AleraIcons.agent,
};

/// Binds the Activity sections and their attention counts to [AleraRail].
class const ActivityRail({super.key, final bool compact = false})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(
      activityNavigationProvider.select((value) => value.section),
    );
    final attention = ref.watch(activityAttentionProvider);
    return AleraRail(
      key: const ValueKey<String>('activityRail'),
      compact: compact,
      selectedIndex: section.index,
      onSelected: (index) => ref
          .read(activityNavigationProvider.notifier)
          .showSection(ActivitySection.values[index]),
      items: <AleraRailItem>[
        for (final value in ActivitySection.values)
          AleraRailItem(
            icon: activitySectionIcon(value),
            label: value.label,
            count: attention.countFor(value),
            tone: value == ActivitySection.questions
                ? AleraBadgeTone.accent
                : AleraBadgeTone.attention,
          ),
      ],
    );
  }
}
