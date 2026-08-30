import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:flutter/widgets.dart';

class ControlledAppLifecycle extends AppLifecycleController {
  ControlledAppLifecycle([this.initialState = AppLifecycleState.paused]);

  final AppLifecycleState initialState;

  @override
  AppLifecycleState build() => initialState;

  void setLifecycleState(AppLifecycleState next) {
    state = next;
  }
}
