import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RunBoardAttentionControl extends ConsumerWidget {
  const RunBoardAttentionControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(runBoardAttentionProvider);
    final count = snapshot.hasError ? null : snapshot.value?.attention;
    final label = count == null
        ? 'Open Run Board · Attention Unavailable'
        : 'Open Run Board · $count ${count == 1 ? 'Run Needs' : 'Runs Need'} Attention';
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: () => ref.read(runBoardNavigationProvider.notifier).open(),
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
            children: [
              const Icon(
                AleraIcons.workspaceChildren,
                size: AleraTokens.iconSm,
              ),
              const SizedBox(width: AleraTokens.space4),
              Text(
                count == null
                    ? '?'
                    : count > 999
                    ? '999+'
                    : '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: (count ?? 0) > 0
                      ? AleraTokens.warning
                      : AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
