import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/desktop_presence/application/desktop_presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Watches agent status and desktop settings so the tray icon and dock badge
/// stay in sync. Mounted once at the app root.
class DesktopPresenceScope extends ConsumerWidget {
  const DesktopPresenceScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (supportsDesktopAppWindowState) {
      ref.watch(desktopPresenceSyncProvider);
    }
    return child;
  }
}
