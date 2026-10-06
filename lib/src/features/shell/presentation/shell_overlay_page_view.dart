import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/presentation/automations_page.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_page.dart';
import 'package:alera/src/features/shell/application/shell_overlay_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the Run Board, Automations or the inbox over the retained workbench.
class ShellOverlayPageView extends ConsumerWidget {
  const ShellOverlayPageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(shellOverlayPageProvider)) {
        ShellOverlayPage.none => const SizedBox.shrink(),
        ShellOverlayPage.runBoard => RunBoardPage(
          onReturnToWorkspace: () =>
              ref.read(runBoardNavigationProvider.notifier).close(),
        ),
        ShellOverlayPage.automations => AutomationsPage(
          onReturnToWorkspace: () =>
              ref.read(automationsNavigationProvider.notifier).close(),
        ),
        ShellOverlayPage.inbox => InboxPage(
          onReturnToWorkspace: () =>
              ref.read(inboxNavigationProvider.notifier).close(),
        ),
      };
}
