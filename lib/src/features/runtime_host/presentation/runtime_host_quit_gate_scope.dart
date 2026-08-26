import 'package:alera/src/design_system/layout/alera_choice_dialog.dart';
import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_providers.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_quit_decision.dart';
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
    final client = ref.read(runtimeHostClientProvider);
    client.beginAppQuit();
    var closeCommitted = false;
    try {
      final keepRuntimeOpen = ref
          .read(settingsControllerProvider)
          .terminal
          .keepRuntimeOpenOnAppQuit;
      final allowed = await ref
          .read(runtimeHostLifecycleServiceProvider)
          .prepareAppQuit(
            keepRuntimeOpen: keepRuntimeOpen,
            confirmBusyQuit: _confirmBusyQuit,
          );
      if (!allowed) {
        return false;
      }
      // Mirror the Linux detach path for all platforms when quitting.
      client.dispose();
      closeCommitted = true;
      return true;
    } finally {
      if (!closeCommitted) {
        client.cancelAppQuit();
      }
    }
  }

  Future<RuntimeHostQuitDecision> _confirmBusyQuit({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return RuntimeHostQuitDecision.cancel;
    }
    final decision = await showDialog<RuntimeHostQuitDecision>(
      context: context,
      builder: (_) => AleraChoiceDialog<RuntimeHostQuitDecision>(
        title: title,
        message: message,
        primaryLabel: 'Quit And Leave Runtime Open',
        primaryValue: RuntimeHostQuitDecision.leaveRuntimeOpen,
        secondaryLabel: 'Force Stop And Quit',
        secondaryValue: RuntimeHostQuitDecision.forceStop,
        destructiveSecondary: true,
      ),
    );
    return decision ?? RuntimeHostQuitDecision.cancel;
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
