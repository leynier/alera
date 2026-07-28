import 'package:alera_mobile/src/features/push_notifications/infra/mobile_firebase_bootstrap.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/mobile_local_notification_service.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/push_messaging_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'push_notification_providers.g.dart';

@Riverpod(keepAlive: true)
PushMessagingService pushMessagingService(Ref ref) {
  return MobileFirebaseBootstrap.ready
      ? FirebasePushMessagingService()
      : const DisabledPushMessagingService();
}

@Riverpod(keepAlive: true)
MobileLocalNotificationService mobileLocalNotificationService(Ref ref) {
  return MobileFirebaseBootstrap.ready
      ? FlutterMobileLocalNotificationService()
      : const DisabledMobileLocalNotificationService();
}
