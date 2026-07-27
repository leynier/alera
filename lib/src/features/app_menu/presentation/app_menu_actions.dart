import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_about_dialog.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Shared actions for the native macOS and in-window Windows/Linux menus.

typedef AppMenuPackageInfoLoader = Future<PackageInfo> Function();

Future<void> openAppMenuSettings(BuildContext context) {
  return openSettingsDialog(context);
}

Future<void> checkForUpdatesFromAppMenu(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = ref.read(aleraUpdateControllerProvider.notifier);
  await controller.checkForUpdates();
  if (!context.mounted) {
    return;
  }
  final state = ref.read(aleraUpdateControllerProvider);
  final message = state.message?.trim();
  if (message == null || message.isEmpty) {
    return;
  }
  AleraToast.show(
    context,
    message: message,
    tone: _toastToneForUpdateStatus(state.status),
  );
}

Future<void> showAppMenuAbout(
  BuildContext context,
  WidgetRef ref, {
  AppMenuPackageInfoLoader loadPackageInfo = PackageInfo.fromPlatform,
}) async {
  final info = await loadPackageInfo();
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AppMenuAboutDialog(
        info: info,
        onCheckForUpdates: () {
          // Close first: the update result surfaces as a toast under the
          // launcher context, not the dialog's.
          Navigator.of(dialogContext).pop();
          unawaited(checkForUpdatesFromAppMenu(context, ref));
        },
      );
    },
  );
}

/// Closes through the app-window lifecycle (flush state, then destroy).
Future<void> exitAppFromMenu(WidgetRef ref) {
  return ref.read(appWindowControllerProvider).close();
}

/// Invokes a text-editing intent on the primary focus, if any action handles it.
void invokeFocusedTextIntent(Intent intent, {BuildContext? focusContext}) {
  final targetContext = focusContext ?? primaryFocus?.context;
  if (targetContext == null) {
    return;
  }
  Actions.maybeInvoke<Intent>(targetContext, intent);
}

AleraToastTone _toastToneForUpdateStatus(AleraUpdateStatus status) {
  return switch (status) {
    AleraUpdateStatus.error => AleraToastTone.error,
    AleraUpdateStatus.available ||
    AleraUpdateStatus.manualDownloadRequired ||
    AleraUpdateStatus.downloaded => AleraToastTone.success,
    AleraUpdateStatus.idle ||
    AleraUpdateStatus.checking ||
    AleraUpdateStatus.notAvailable ||
    AleraUpdateStatus.downloading ||
    AleraUpdateStatus.applying => AleraToastTone.info,
  };
}
