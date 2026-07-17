import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
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
  BuildContext context, {
  AppMenuPackageInfoLoader loadPackageInfo = PackageInfo.fromPlatform,
}) async {
  final info = await loadPackageInfo();
  if (!context.mounted) {
    return;
  }
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AleraDialog(
        maxWidth: 360,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(kAleraAppName, style: theme.textTheme.titleMedium),
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Version ${info.version} (${info.buildNumber})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
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
    AleraUpdateStatus.downloading => AleraToastTone.info,
  };
}
