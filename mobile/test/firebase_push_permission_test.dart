import 'package:alera_mobile/src/features/push_notifications/infra/push_messaging_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in <AuthorizationStatus>[
    AuthorizationStatus.denied,
    AuthorizationStatus.deniedPermanently,
  ]) {
    test('Firebase $status keeps push authorization denied', () async {
      final messaging = _PermissionMessaging(status);
      final service = FirebasePushMessagingService(messaging);

      expect(await service.requestPermission(), PushPermissionState.denied);
      expect(messaging.foregroundPresentationDisabled, isTrue);
    });
  }
}

class _PermissionMessaging(final AuthorizationStatus status)
    extends Fake
    implements FirebaseMessaging {
  bool foregroundPresentationDisabled = false;

  @override
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = false,
    bool badge = false,
    bool sound = false,
  }) async {
    foregroundPresentationDisabled = !alert && !badge && !sound;
  }

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async => _PermissionSettings(status);
}

class _PermissionSettings(final AuthorizationStatus _status)
    extends Fake
    implements NotificationSettings {
  @override
  AuthorizationStatus get authorizationStatus => _status;
}
