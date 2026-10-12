import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shell_overlay_page.g.dart';

/// The full-width page that replaces the workbench, if any.
enum ShellOverlayPage { none, activity }

@riverpod
ShellOverlayPage shellOverlayPage(Ref ref) =>
    ref.watch(activityNavigationProvider.select((value) => value.visible))
    ? ShellOverlayPage.activity
    : ShellOverlayPage.none;
