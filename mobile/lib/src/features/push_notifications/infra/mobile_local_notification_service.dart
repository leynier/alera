import 'dart:convert';

import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/push_messaging_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef PushNotificationSelectionHandler = void Function(
  PushNavigationIntent intent,
);

abstract interface class MobileLocalNotificationService {
  Future<void> initialize({
    required PushNotificationSelectionHandler onSelected,
  });

  Future<void> show(PushMessage message);
}

class FlutterMobileLocalNotificationService({
  FlutterLocalNotificationsPlugin? plugin,
}) implements MobileLocalNotificationService {
  this : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel attentionChannel =
      AndroidNotificationChannel(
        'alera_attention',
        'Agent attention',
        description: 'Agent waits, blocks, and decision gates.',
        importance: .high,
      );
  static const AndroidNotificationChannel activityChannel =
      AndroidNotificationChannel(
        'alera_activity',
        'Agent activity',
        description: 'Agent completion and terminal activity.',
        importance: .defaultImportance,
      );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize({
    required PushNotificationSelectionHandler onSelected,
  }) async {
    if (_initialized) {
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) {
          return;
        }
        _selectPayload(payload, onSelected);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      _selectPayload(launchPayload, onSelected);
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(attentionChannel);
    await android?.createNotificationChannel(activityChannel);
    _initialized = true;
  }

  void _selectPayload(
    String payload,
    PushNotificationSelectionHandler onSelected,
  ) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        onSelected(
          .fromData(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    } on FormatException {
      return;
    }
  }

  @override
  Future<void> show(PushMessage message) async {
    if (!_initialized) {
      return;
    }
    final event = message.navigationIntent?.eventKind ?? PushEventKind.unknown;
    final attention = event == PushEventKind.attention;
    final channel = attention ? attentionChannel : activityChannel;
    await _plugin.show(
      id: _notificationId(message),
      title: message.title,
      body: message.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: attention ? Priority.high : Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  int _notificationId(PushMessage message) {
    return (message.messageId ?? '${message.title}:${message.body}').hashCode &
        0x7fffffff;
  }
}

class const DisabledMobileLocalNotificationService()
    implements MobileLocalNotificationService {
  @override
  Future<void> initialize({
    required PushNotificationSelectionHandler onSelected,
  }) async {}

  @override
  Future<void> show(PushMessage message) async {}
}
