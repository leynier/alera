import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:flutter/widgets.dart';

class ControlledAppLifecycle([
  final AppLifecycleState initialState = AppLifecycleState.paused,
]) extends AppLifecycleController {
  @override
  AppLifecycleState build() => initialState;

  void setLifecycleState(AppLifecycleState next) {
    state = next;
  }
}
