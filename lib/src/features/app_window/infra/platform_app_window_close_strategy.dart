import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:logging/logging.dart';

final class PlatformAppWindowCloseStrategy({
  bool? isLinux,
  final Future<void> Function()? beforeLinuxExit,
  void Function(int)? exitProcess,
  final Duration linuxExitGracePeriod = const Duration(seconds: 1),
  Logger? logger,
}) implements AppWindowCloseStrategy {
  this
    : _isLinux = isLinux ?? Platform.isLinux,
      _exitProcess = exitProcess ?? exit,
      _logger = logger ?? Logger('PlatformAppWindowCloseStrategy');

  final bool _isLinux;

  final void Function(int) _exitProcess;

  final Logger _logger;

  @override
  Future<void> close(AppWindowController window) async {
    if (!_isLinux) {
      await window.setPreventClose(false);
      await window.destroy();
      return;
    }

    final beforeExit = beforeLinuxExit;
    if (beforeExit != null) {
      try {
        await beforeExit().timeout(linuxExitGracePeriod);
      } catch (error, stackTrace) {
        _logger.warning(
          'failed to detach runtime host before controlled Linux exit',
          error,
          stackTrace,
        );
      }
    }
    _exitProcess(0);
  }
}
