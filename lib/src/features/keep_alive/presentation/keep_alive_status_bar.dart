import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/keep_alive/application/keep_alive_providers.dart';
import 'package:alera/src/features/keep_alive/presentation/keep_alive_status_chip.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const KeepAliveStatusBarControl({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(keepAliveControllerProvider);
    final enabled = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.general.keepAliveEnabled,
      ),
    );
    return KeepAliveStatusChip(
      snapshot: snapshot,
      enabled: enabled,
      onPressed: () => unawaited(_toggle(context, ref)),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(keepAliveControllerProvider.notifier);
    try {
      await controller.toggle();
      if (!context.mounted) {
        return;
      }
      final snapshot = ref.read(keepAliveControllerProvider);
      if (snapshot.hasError && !snapshot.active) {
        AleraToast.show(
          context,
          message: 'Could not keep this computer awake. ${snapshot.error}',
          tone: .error,
        );
      }
    } catch (error, stackTrace) {
      AppLogger.recordError(
        error,
        stackTrace,
        context: 'KeepAliveStatusBarControl',
      );
      if (context.mounted) {
        AleraToast.show(
          context,
          message: 'Could not keep this computer awake.',
          tone: .error,
        );
      }
    }
  }
}
