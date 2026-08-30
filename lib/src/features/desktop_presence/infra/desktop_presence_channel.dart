import 'dart:async';

import 'package:flutter/services.dart';

const String desktopPresenceChannelName = 'dev.leynier.alera/desktop_presence';

abstract final class DesktopPresenceMethod {
  static const String setTray = 'setTray';
  static const String setBadgeCount = 'setBadgeCount';
  static const String destroy = 'destroy';
}

abstract final class DesktopPresenceEvent {
  static const String trayShow = 'trayShow';
  static const String trayQuit = 'trayQuit';
  static const String trayInstallationChanged = 'trayInstallationChanged';
}

class const DesktopPresenceSnapshot({
  required final bool trayVisible,
  required final String tooltip,
  required this.badgeCount,
  this.trayBadgeCount = 0,
}) {
  /// Dock, taskbar, or launcher-entry badge.
  final int badgeCount;

  /// Count drawn onto the tray icon itself. Only Linux paints it today.
  final int trayBadgeCount;

  @override
  bool operator ==(Object other) {
    return other is DesktopPresenceSnapshot &&
        other.trayVisible == trayVisible &&
        other.tooltip == tooltip &&
        other.badgeCount == badgeCount &&
        other.trayBadgeCount == trayBadgeCount;
  }

  @override
  int get hashCode =>
      Object.hash(trayVisible, tooltip, badgeCount, trayBadgeCount);
}

abstract interface class DesktopPresenceBackend {
  void listen({
    required VoidCallback onShow,
    required VoidCallback onQuit,
    void Function(bool installed)? onInstallationChanged,
  });

  Future<void> apply(DesktopPresenceSnapshot snapshot);

  Future<void> destroy();
}

class MethodChannelDesktopPresenceBackend({MethodChannel? channel})
    implements DesktopPresenceBackend {
  this : _channel = channel ?? const MethodChannel(desktopPresenceChannelName);

  final MethodChannel _channel;
  bool _listening = false;

  @override
  void listen({
    required VoidCallback onShow,
    required VoidCallback onQuit,
    void Function(bool installed)? onInstallationChanged,
  }) {
    if (_listening) {
      return;
    }
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case DesktopPresenceEvent.trayShow:
          onShow();
        case DesktopPresenceEvent.trayQuit:
          onQuit();
        case DesktopPresenceEvent.trayInstallationChanged:
          onInstallationChanged?.call(call.arguments == true);
      }
      return null;
    });
  }

  @override
  Future<void> apply(DesktopPresenceSnapshot snapshot) async {
    final installed = await _channel.invokeMethod<Object?>(
      DesktopPresenceMethod.setTray,
      <String, Object?>{
        'visible': snapshot.trayVisible,
        'tooltip': snapshot.tooltip,
        'badgeCount': snapshot.trayBadgeCount,
      },
    );
    if (snapshot.trayVisible && installed == false) {
      throw StateError('desktop tray was not installed');
    }
    await _channel.invokeMethod<void>(
      DesktopPresenceMethod.setBadgeCount,
      <String, Object?>{'count': snapshot.badgeCount},
    );
  }

  @override
  Future<void> destroy() {
    return _channel.invokeMethod<void>(DesktopPresenceMethod.destroy);
  }
}
