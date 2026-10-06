import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shell_overlay_page.g.dart';

/// The full-width page that replaces the workbench, if any.
enum ShellOverlayPage { none, runBoard, automations, inbox }

@riverpod
ShellOverlayPage shellOverlayPage(Ref ref) {
  if (ref.watch(runBoardNavigationProvider.select((value) => value.visible))) {
    return ShellOverlayPage.runBoard;
  }
  if (ref.watch(
    automationsNavigationProvider.select((value) => value.visible),
  )) {
    return ShellOverlayPage.automations;
  }
  if (ref.watch(inboxNavigationProvider.select((value) => value.visible))) {
    return ShellOverlayPage.inbox;
  }
  return ShellOverlayPage.none;
}
