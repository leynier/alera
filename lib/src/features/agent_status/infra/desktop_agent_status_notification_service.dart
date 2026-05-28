// coverage:ignore-file
// Adapter over flutter_local_notifications. Notification decisions and
// activation payloads are covered at the application layer with fakes.
import 'dart:async';

import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String aleraWindowsNotificationAppName = kAleraAppName;
const String aleraWindowsNotificationAppUserModelId = 'Leynier.Alera';
const String aleraWindowsNotificationGuid =
    '6f03d61e-b22a-42fc-9e44-a02319d77f55';
const String _openAleraActionLabel = 'Open $kAleraAppName';

class DesktopAgentStatusNotificationService
    implements AgentStatusNotificationPresenter {
  DesktopAgentStatusNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initializing;
  bool _initialized = false;

  @override
  Future<void> initialize({
    required AgentStatusNotificationSelectionHandler onSelected,
  }) {
    if (_initialized) {
      return Future<void>.value();
    }
    return _initializing ??= _initialize(onSelected);
  }

  Future<void> _initialize(
    AgentStatusNotificationSelectionHandler onSelected,
  ) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestSoundPermission: true,
          requestBadgePermission: false,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: _openAleraActionLabel,
        ),
        windows: WindowsInitializationSettings(
          appName: aleraWindowsNotificationAppName,
          appUserModelId: aleraWindowsNotificationAppUserModelId,
          guid: aleraWindowsNotificationGuid,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) {
          return;
        }
        onSelected(payload);
      },
    );
    _initialized = true;
  }

  @override
  Future<void> show(AgentStatusNotification notification) async {
    if (!_initialized) {
      return;
    }
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(
          defaultActionName: _openAleraActionLabel,
          urgency: LinuxNotificationUrgency.normal,
        ),
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
        ),
      ),
      payload: notification.payload,
    );
  }
}
