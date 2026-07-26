import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lifecycle_controller.g.dart';

/// The app's foreground/background state.
///
/// `AppLifecycleListener` rather than a `WidgetsBindingObserver` so this stays a
/// generated provider instead of leaking lifecycle wiring into a widget.
@Riverpod(keepAlive: true)
class AppLifecycleController extends _$AppLifecycleController {
  @override
  AppLifecycleState build() {
    final listener = AppLifecycleListener(
      onStateChange: (next) => state = next,
    );
    ref.onDispose(listener.dispose);
    return SchedulerBinding.instance.lifecycleState ??
        AppLifecycleState.resumed;
  }
}
