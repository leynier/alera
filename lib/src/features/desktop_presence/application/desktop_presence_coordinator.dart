import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/desktop_presence/infra/desktop_presence_channel.dart';
import 'package:logging/logging.dart';

class DesktopPresenceCoordinator {
  DesktopPresenceCoordinator({
    required this.backend,
    required this.window,
    required this.lifecycle,
    Logger? logger,
  }) : _logger = logger ?? Logger('DesktopPresenceCoordinator');

  final DesktopPresenceBackend backend;
  final AppWindowController window;
  final AppWindowLifecycleCoordinator lifecycle;
  final Logger _logger;

  DesktopPresenceSnapshot? _last;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    backend.listen(onShow: _showWindow, onQuit: _quit);
  }

  Future<void> apply(DesktopPresenceSnapshot snapshot) async {
    if (_last == snapshot) {
      return;
    }
    _last = snapshot;
    try {
      await backend.apply(snapshot);
    } catch (error, stackTrace) {
      _logger.warning('failed to apply desktop presence', error, stackTrace);
    }
  }

  Future<void> destroy() async {
    _last = null;
    try {
      await backend.destroy();
    } catch (error, stackTrace) {
      _logger.warning('failed to destroy desktop presence', error, stackTrace);
    }
  }

  void _showWindow() {
    unawaited(_showAndFocus());
  }

  Future<void> _showAndFocus() async {
    try {
      if (!await window.isVisible()) {
        await window.show();
      }
      if (await window.isMinimized()) {
        await window.restore();
      }
      await window.focus();
    } catch (error, stackTrace) {
      _logger.warning('failed to show app window from tray', error, stackTrace);
    }
  }

  void _quit() {
    unawaited(lifecycle.requestQuit());
  }
}
