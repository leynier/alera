import 'package:alera/src/features/activity/presentation/activity_page.dart';
import 'package:alera/src/features/shell/application/shell_overlay_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows Activity over the retained workbench.
class ShellOverlayPageView extends ConsumerWidget {
  const ShellOverlayPageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(shellOverlayPageProvider)) {
        ShellOverlayPage.none => const SizedBox.shrink(),
        ShellOverlayPage.activity => const ActivityPage(),
      };
}
