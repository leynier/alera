import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

class const AppWindowLifecycleScope({super.key, required final Widget child})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<AppWindowLifecycleScope> createState() =>
      _AppWindowLifecycleScopeState();
}

class _AppWindowLifecycleScopeState
    extends ConsumerState<AppWindowLifecycleScope> {
  final Logger _logger = Logger('AppWindowLifecycleScope');
  bool _startRequested = false;

  // Reading providers through ref is unsafe in dispose(), so the coordinator
  // started here is kept in a field for the matching stop() call.
  AppWindowLifecycleCoordinator? _startedCoordinator;

  @override
  Widget build(BuildContext context) {
    if (supportsDesktopAppWindowState) {
      final db = ref.watch(aleraDatabaseProvider);
      if (db.hasValue && !_startRequested) {
        _startRequested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          final coordinator = ref.read(appWindowLifecycleCoordinatorProvider);
          _startedCoordinator = coordinator;
          unawaited(
            coordinator.start().catchError((
              Object error,
              StackTrace stackTrace,
            ) {
              _logger.warning(
                'failed to start app window lifecycle',
                error,
                stackTrace,
              );
            }),
          );
        });
      }
    }
    return widget.child;
  }

  @override
  void dispose() {
    final coordinator = _startedCoordinator;
    if (coordinator != null) {
      unawaited(coordinator.stop());
    }
    super.dispose();
  }
}
