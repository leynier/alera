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
}

class DesktopPresenceSnapshot {
  const DesktopPresenceSnapshot({
    required this.trayVisible,
    required this.tooltip,
    required this.badgeCount,
  });

  final bool trayVisible;
  final String tooltip;
  final int badgeCount;

  @override
  bool operator ==(Object other) {
    return other is DesktopPresenceSnapshot &&
        other.trayVisible == trayVisible &&
        other.tooltip == tooltip &&
        other.badgeCount == badgeCount;
  }

  @override
  int get hashCode => Object.hash(trayVisible, tooltip, badgeCount);
}

abstract interface class DesktopPresenceBackend {
  void listen({required VoidCallback onShow, required VoidCallback onQuit});

  Future<void> apply(DesktopPresenceSnapshot snapshot);

  Future<void> destroy();
}

class MethodChannelDesktopPresenceBackend implements DesktopPresenceBackend {
  MethodChannelDesktopPresenceBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(desktopPresenceChannelName);

  final MethodChannel _channel;
  bool _listening = false;

  @override
  void listen({required VoidCallback onShow, required VoidCallback onQuit}) {
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
      }
      return null;
    });
  }

  @override
  Future<void> apply(DesktopPresenceSnapshot snapshot) async {
    await _channel.invokeMethod<void>(
      DesktopPresenceMethod.setTray,
      <String, Object?>{
        'visible': snapshot.trayVisible,
        'tooltip': snapshot.tooltip,
      },
    );
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
