import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:flutter/widgets.dart';

/// [AppForeground] backed by the Flutter app lifecycle.
///
/// With [requireFocus], an unfocused window (`inactive` on desktop) counts as
/// background too: for acknowledging something the user must actually be
/// looking at, rather than for parking work.
class LifecycleAppForeground({final bool requireFocus = false})
    implements AppForeground {
  this {
    try {
      _listener = AppLifecycleListener(onStateChange: _apply);
      final initial = WidgetsBinding.instance.lifecycleState;
      if (requireFocus && initial != null) {
        _isForeground = _isForegroundState(initial, requireFocus: true);
      }
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
    final next = _isForegroundState(state, requireFocus: requireFocus);
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
bool _isForegroundState(AppLifecycleState state, {required bool requireFocus}) {
  return switch (state) {
    AppLifecycleState.resumed => true,
    AppLifecycleState.inactive => !requireFocus,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
  };
}
