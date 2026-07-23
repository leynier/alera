import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Binds the runtime stop-on-quit gate once the app database is ready.
class RuntimeHostQuitGateScope extends ConsumerStatefulWidget {
  const RuntimeHostQuitGateScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RuntimeHostQuitGateScope> createState() =>
      _RuntimeHostQuitGateScopeState();
}

class _RuntimeHostQuitGateScopeState
    extends ConsumerState<RuntimeHostQuitGateScope> {
  bool _bound = false;

  Future<bool> _closeGate() async {
    final stopOnQuit = ref
        .read(settingsControllerProvider)
        .terminal
        .stopRuntimeOnAppQuit;
    final allowed = await ref
        .read(runtimeHostLifecycleServiceProvider)
        .prepareAppQuit(stopOnQuit: stopOnQuit, confirmForce: _confirmForce);
    if (!allowed) {
      return false;
    }
    // Mirror the Linux detach path for all platforms when quitting.
    ref.read(runtimeHostClientProvider).dispose();
    return true;
  }

  Future<bool> _confirmForce({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    if (!mounted) {
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        destructive: true,
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    if (supportsDesktopAppWindowState) {
      final db = ref.watch(aleraDatabaseProvider);
      if (db.hasValue && !_bound) {
        _bound = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          ref
              .read(appWindowLifecycleCoordinatorProvider)
              .bindCloseGate(_closeGate);
        });
      }
    }
    return widget.child;
  }
}
