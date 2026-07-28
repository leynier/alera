import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

class MobileEmulatorTarget {
  const MobileEmulatorTarget({required this.tabId, required this.workspaceId});

  final String tabId;
  final String workspaceId;

  Map<String, Object?> toTabRequest() => <String, Object?>{'tabId': tabId};
}

class MobileEmulatorDevice {
  const MobileEmulatorDevice({
    required this.id,
    required this.platform,
    required this.name,
    required this.state,
    required this.available,
    this.runtime,
  });

  final String id;
  final MobileEmulatorPlatform platform;
  final String name;
  final String state;
  final bool available;
  final String? runtime;

  static MobileEmulatorDevice? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    final name = value['name'];
    final platform = MobileEmulatorPlatform.fromJson(value['platform']);
    if (id is! String || name is! String || platform == null) {
      return null;
    }
    return MobileEmulatorDevice(
      id: id,
      platform: platform,
      name: name,
      state: value['state'] is String ? value['state'] as String : 'unknown',
      available: value['available'] != false,
      runtime: value['runtime'] is String ? value['runtime'] as String : null,
    );
  }
}

class MobileEmulatorCapability {
  const MobileEmulatorCapability({
    required this.available,
    required this.message,
  });

  final bool available;
  final String message;

  static MobileEmulatorCapability fromJson(Object? value) {
    if (value is! Map) {
      return const MobileEmulatorCapability(
        available: false,
        message: 'The Emulator Backend Is Unavailable.',
      );
    }
    return MobileEmulatorCapability(
      available: value['available'] == true,
      message: value['message'] is String
          ? value['message'] as String
          : 'The Emulator Backend Is Unavailable.',
    );
  }
}

class MobileEmulatorStream {
  const MobileEmulatorStream({
    required this.url,
    required this.codec,
    this.width,
    this.height,
  });

  final Uri url;
  final String codec;
  final int? width;
  final int? height;

  static MobileEmulatorStream? fromJson(Object? value) {
    if (value is! Map || value['url'] is! String) {
      return null;
    }
    final uri = Uri.tryParse(value['url'] as String);
    const loopbackHosts = <String>{'127.0.0.1', '::1', 'localhost'};
    if (uri == null ||
        uri.scheme != 'http' ||
        !loopbackHosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    return MobileEmulatorStream(
      url: uri,
      codec: value['codec'] is String ? value['codec'] as String : 'unknown',
      width: _positiveInt(value['width']),
      height: _positiveInt(value['height']),
    );
  }
}

class MobileEmulatorSession {
  const MobileEmulatorSession({
    required this.id,
    required this.state,
    required this.platform,
    required this.deviceId,
    this.stream,
  });

  final String id;
  final String state;
  final MobileEmulatorPlatform platform;
  final String deviceId;
  final MobileEmulatorStream? stream;

  bool get isReady => stream != null && state != 'failed';

  static MobileEmulatorSession? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'] ?? value['sessionId'];
    final platform = MobileEmulatorPlatform.fromJson(value['platform']);
    final deviceId = value['deviceId'];
    if (id is! String || platform == null || deviceId is! String) {
      return null;
    }
    return MobileEmulatorSession(
      id: id,
      state: value['state'] is String ? value['state'] as String : 'starting',
      platform: platform,
      deviceId: deviceId,
      stream: MobileEmulatorStream.fromJson(value['stream']),
    );
  }
}

class MobileEmulatorAttachment {
  const MobileEmulatorAttachment({required this.tab, required this.session});

  final WorkspaceTabRecord tab;
  final MobileEmulatorSession session;
}

enum MobileEmulatorRuntimeChangeAction { ignore, refresh, stopped }

MobileEmulatorRuntimeChangeAction resolveMobileEmulatorRuntimeChange({
  required String? reason,
  required bool leaseHeld,
}) {
  if (reason == 'shutdown') {
    return MobileEmulatorRuntimeChangeAction.stopped;
  }
  if (!leaseHeld) {
    return MobileEmulatorRuntimeChangeAction.ignore;
  }
  return MobileEmulatorRuntimeChangeAction.refresh;
}

class MobileEmulatorException implements Exception {
  const MobileEmulatorException({
    required this.code,
    required this.message,
    this.nextSteps = const <String>[],
  });

  final String code;
  final String message;
  final List<String> nextSteps;

  @override
  String toString() => message;
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) {
    return value;
  }
  return null;
}
