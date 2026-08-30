import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

enum PushPermissionState { authorized, denied, notDetermined }

class const PushMessage({
  required final String title,
  required final String body,
  required final Map<String, Object?> data,
  final String? messageId,
}) {
  PushNavigationIntent? get navigationIntent {
    try {
      return PushNavigationIntent.fromData(data);
    } on FormatException {
      return null;
    }
  }

  factory fromRemote(RemoteMessage message) {
    final data = <String, Object?>{...message.data};
    return PushMessage(
      title:
          message.notification?.title ??
          _string(data['title']) ??
          'Alera needs attention',
      body:
          message.notification?.body ??
          _string(data['body']) ??
          'Open Alera to review the latest activity.',
      data: data,
      messageId: message.messageId,
    );
  }
}

abstract interface class PushMessagingService {
  bool get isAvailable;
  Stream<String> get tokenRefresh;
  Stream<PushMessage> get foregroundMessages;
  Stream<PushNavigationIntent> get openedIntents;

  Future<PushPermissionState> requestPermission();
  Future<String?> token();
  Future<PushNavigationIntent?> initialIntent();
}

class FirebasePushMessagingService([FirebaseMessaging? messaging])
    implements PushMessagingService {
  this : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  bool get isAvailable => true;

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get foregroundMessages {
    return FirebaseMessaging.onMessage.map(PushMessage.fromRemote);
  }

  @override
  Stream<PushNavigationIntent> get openedIntents {
    return FirebaseMessaging.onMessageOpenedApp
        .map(PushMessage.fromRemote)
        .map((message) => message.navigationIntent)
        .where((intent) => intent != null)
        .map((intent) => intent!);
  }

  @override
  Future<PushPermissionState> requestPermission() async {
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    final settings = await _messaging.requestPermission();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermissionState.authorized,
      AuthorizationStatus.denied => PushPermissionState.denied,
      AuthorizationStatus.notDetermined => PushPermissionState.notDetermined,
    };
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Future<PushNavigationIntent?> initialIntent() async {
    final message = await _messaging.getInitialMessage();
    return message == null
        ? null
        : PushMessage.fromRemote(message).navigationIntent;
  }
}

class const DisabledPushMessagingService() implements PushMessagingService {
  @override
  bool get isAvailable => false;

  @override
  Stream<PushMessage> get foregroundMessages => const Stream.empty();

  @override
  Stream<PushNavigationIntent> get openedIntents => const Stream.empty();

  @override
  Stream<String> get tokenRefresh => const Stream.empty();

  @override
  Future<PushNavigationIntent?> initialIntent() async => null;

  @override
  Future<PushPermissionState> requestPermission() async {
    return PushPermissionState.notDetermined;
  }

  @override
  Future<String?> token() async => null;
}

String? _string(Object? value) {
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}
