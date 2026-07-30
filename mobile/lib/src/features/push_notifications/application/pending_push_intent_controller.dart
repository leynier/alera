import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pending_push_intent_controller.g.dart';

@Riverpod(keepAlive: true)
class PendingPushIntentController extends _$PendingPushIntentController {
  @override
  PushNavigationIntent? build() => null;

  void setIntent(PushNavigationIntent intent) {
    state = intent;
  }

  void clear() {
    state = null;
  }
}
