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
  Future<void> _applyQueue = Future<void>.value();

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    backend.listen(onShow: _showWindow, onQuit: _quit);
  }

  Future<void> apply(DesktopPresenceSnapshot snapshot) {
    final pending = _applyQueue.then((_) => _applyNow(snapshot));
    _applyQueue = pending.catchError((Object error, StackTrace stackTrace) {
      _logger.warning('failed to apply desktop presence', error, stackTrace);
    });
    return _applyQueue;
  }

  Future<void> _applyNow(DesktopPresenceSnapshot snapshot) async {
    if (_last == snapshot) {
      return;
    }
    if ((_last?.trayVisible ?? false) && !snapshot.trayVisible) {
      final hidden = !await window.isVisible();
      final minimized = await window.isMinimized();
      if ((hidden || minimized) && !await _showAndFocus()) {
        return;
      }
    }
    try {
      await backend.apply(snapshot);
    } catch (error, stackTrace) {
      _logger.warning('failed to apply desktop presence', error, stackTrace);
      return;
    }
    _last = snapshot;
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

  Future<bool> _showAndFocus() async {
    try {
      if (!await window.isVisible()) {
        await window.show();
        if (!await window.isVisible()) {
          return false;
        }
      }
      if (await window.isMinimized()) {
        await window.restore();
      }
      await window.focus();
      return true;
    } catch (error, stackTrace) {
      _logger.warning('failed to show app window from tray', error, stackTrace);
      return false;
    }
  }

  void _quit() {
    unawaited(lifecycle.requestQuit());
  }
}
