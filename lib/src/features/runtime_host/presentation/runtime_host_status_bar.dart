import 'dart:async';

import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_providers.dart';
import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_service.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/presentation/runtime_host_status_panel.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RuntimeHostStatusBarControl extends ConsumerStatefulWidget {
  const RuntimeHostStatusBarControl({super.key});

  @override
  ConsumerState<RuntimeHostStatusBarControl> createState() =>
      _RuntimeHostStatusBarControlState();
}

class _RuntimeHostStatusBarControlState
    extends ConsumerState<RuntimeHostStatusBarControl> {
  final AleraHoverCardController _hoverCard = AleraHoverCardController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(runtimeHostStatusProvider);
    final snapshot = statusAsync.value;
    final loading = statusAsync.isLoading && snapshot == null;

    return AleraHoverCard(
      controller: _hoverCard,
      // The chip runs its own InkWell, which would win the gesture arena over
      // the card's detector, so the chip drives pinning through the controller.
      pinOnTap: false,
      semanticsLabel: 'Runtime Host',
      card: RuntimeHostStatusPanel(
        snapshot: snapshot,
        loading: loading || statusAsync.isLoading,
        busy: _busy,
        onRefresh: () {
          ref.invalidate(runtimeHostStatusProvider);
        },
        onStart: () => unawaited(
          _runAction((_) async {
            await ref.read(runtimeHostLifecycleServiceProvider).start();
            ref.invalidate(runtimeHostStatusProvider);
          }),
        ),
        onStop: () => unawaited(
          _runAction((confirm) async {
            await ref
                .read(runtimeHostLifecycleServiceProvider)
                .stop(confirmForce: confirm);
            ref.invalidate(runtimeHostStatusProvider);
          }),
        ),
        onUpdate: () => unawaited(
          _runAction((confirm) async {
            await ref
                .read(runtimeHostLifecycleServiceProvider)
                .updateIfAvailable(confirmForce: confirm);
            ref.invalidate(runtimeHostStatusProvider);
          }),
        ),
      ),
      child: RuntimeHostStatusChip(
        snapshot: snapshot,
        loading: loading,
        onPressed: _hoverCard.togglePin,
      ),
    );
  }

  Future<void> _runAction(
    Future<void> Function(RuntimeHostForceConfirm confirm) action,
  ) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action(_confirmForce);
    } catch (error, stackTrace) {
      AppLogger.recordError(
        error,
        stackTrace,
        context: 'RuntimeHostStatusBarControl',
      );
      if (mounted) {
        AleraToast.show(
          context,
          message: _messageFor(error),
          tone: AleraToastTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _messageFor(Object error) {
    if (error is TerminalHostStartupException) {
      return 'Could not start the runtime host. Try again.';
    }
    return 'Runtime host action failed. Try again.';
  }

  Future<bool> _confirmForce({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
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
}

/// Presentational host for widget previews and tests.
class RuntimeHostStatusBarControlView extends StatelessWidget {
  const RuntimeHostStatusBarControlView({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.onPressed,
  });

  final RuntimeHostStatusSnapshot? snapshot;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return RuntimeHostStatusChip(
      snapshot: snapshot,
      loading: loading,
      onPressed: onPressed,
    );
  }
}
