import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

class const MobileEmulatorTarget({
  required final String tabId,
  required final String workspaceId,
}) {
  Map<String, Object?> toTabRequest() => <String, Object?>{'tabId': tabId};
}

class const MobileEmulatorDevice({
  required final String id,
  required final MobileEmulatorPlatform platform,
  required final String name,
  required final String state,
  required final bool available,
  final String? runtime,
}) {
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

class const MobileEmulatorCapability({
  required final bool available,
  required final String message,
}) {
  static MobileEmulatorCapability fromJson(Object? value) {
    if (value is! Map) {
      return const MobileEmulatorCapability(
        available: false,
        message: 'The emulator backend is unavailable.',
      );
    }
    return MobileEmulatorCapability(
      available: value['available'] == true,
      message: value['message'] is String
          ? value['message'] as String
          : 'The emulator backend is unavailable.',
    );
  }
}

class const MobileEmulatorStream({
  required final Uri url,
  required final String codec,
  final int? width,
  final int? height,
}) {
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

class const MobileEmulatorSession({
  required final String id,
  required final String state,
  required final MobileEmulatorPlatform platform,
  required final String deviceId,
  final MobileEmulatorStream? stream,
}) {
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

class const MobileEmulatorAttachment({
  required final WorkspaceTabRecord tab,
  required final MobileEmulatorSession session,
});

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

class const MobileEmulatorException({
  required final String code,
  required final String message,
  final List<String> nextSteps = const <String>[],
}) implements Exception {
  @override
  String toString() => message;
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) {
    return value;
  }
  return null;
}
