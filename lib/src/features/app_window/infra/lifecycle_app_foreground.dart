import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:flutter/widgets.dart';

/// [AppForeground] backed by the Flutter app lifecycle.
class LifecycleAppForeground implements AppForeground {
  LifecycleAppForeground() {
    try {
      _listener = AppLifecycleListener(onStateChange: _apply);
    } catch (_) {
      // No widgets binding, so there is no lifecycle to observe: a unit test,
      // or anything constructed before `runApp`. Reporting a permanent
      // foreground degrades to the behavior from before parking existed, which
      // is the safe direction. Going the other way would silently stop work
      // that nothing would ever restart.
      _listener = null;
    }
  }

  AppLifecycleListener? _listener;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  var _isForeground = true;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  void dispose() {
    _listener?.dispose();
    unawaited(_changes.close());
  }

  void _apply(AppLifecycleState state) {
    final next = _isForegroundState(state);
    if (next == _isForeground) {
      return;
    }
    _isForeground = next;
    _changes.add(next);
  }
}

/// On desktop `inactive` means the window merely lost focus, which happens
/// every time the user reads something in another app. Parking there would stop
/// updating state the user is about to look back at, so only states where the
/// window is actually gone from view count as background.
bool _isForegroundState(AppLifecycleState state) {
  return switch (state) {
    AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
  };
}
