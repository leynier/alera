import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Binds the runtime stop-on-quit gate once a [BuildContext] is available.
class RuntimeHostQuitGateScope extends ConsumerStatefulWidget {
  const RuntimeHostQuitGateScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RuntimeHostQuitGateScope> createState() =>
      _RuntimeHostQuitGateScopeState();
}

class _RuntimeHostQuitGateScopeState
    extends ConsumerState<RuntimeHostQuitGateScope> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(appWindowLifecycleCoordinatorProvider).bindCloseGate(_closeGate);
    });
  }

  @override
  void dispose() {
    // Avoid invoking Riverpod during dispose; clear via a sync read if still
    // mounted is unsafe here, so leave the coordinator gate until process exit.
    super.dispose();
  }

  Future<bool> _closeGate() async {
    final stopOnQuit = ref
        .read(settingsControllerProvider)
        .terminal
        .stopRuntimeOnAppQuit;
    final allowed = await ref
        .read(runtimeHostLifecycleServiceProvider)
        .prepareAppQuit(
          stopOnQuit: stopOnQuit,
          confirmForce: _confirmForce,
        );
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
  Widget build(BuildContext context) => widget.child;
}
