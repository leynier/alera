import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

class AppWindowLifecycleScope extends ConsumerStatefulWidget {
  const AppWindowLifecycleScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppWindowLifecycleScope> createState() =>
      _AppWindowLifecycleScopeState();
}

class _AppWindowLifecycleScopeState
    extends ConsumerState<AppWindowLifecycleScope> {
  final Logger _logger = Logger('AppWindowLifecycleScope');
  bool _startRequested = false;

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
          unawaited(
            ref.read(appWindowLifecycleCoordinatorProvider).start().catchError((
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
    if (_startRequested) {
      unawaited(ref.read(appWindowLifecycleCoordinatorProvider).stop());
    }
    super.dispose();
  }
}
