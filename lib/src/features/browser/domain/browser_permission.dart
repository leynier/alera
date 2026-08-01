enum BrowserPermissionType {
  geolocation,
  camera,
  microphone,
  notifications,
  clipboardRead,
  clipboardWrite,
  fullscreen,
  persistentStorage,
  pointerLock,
  webAuthn,
  displayCapture,
  unknown,
}

enum BrowserPermissionDecision { allow, deny, ask }

BrowserPermissionType browserPermissionTypeFromWire(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
    RegExp('[^a-z0-9]'),
    '',
  );
  return switch (normalized) {
    'geolocation' || 'location' => BrowserPermissionType.geolocation,
    'camera' || 'video' || 'videocapture' => BrowserPermissionType.camera,
    'microphone' ||
    'audio' ||
    'audiocapture' => BrowserPermissionType.microphone,
    'notifications' || 'notification' => BrowserPermissionType.notifications,
    'clipboardread' => BrowserPermissionType.clipboardRead,
    'clipboardwrite' => BrowserPermissionType.clipboardWrite,
    'fullscreen' => BrowserPermissionType.fullscreen,
    'persistentstorage' => BrowserPermissionType.persistentStorage,
    'pointerlock' => BrowserPermissionType.pointerLock,
    'webauthn' || 'publickeycredentials' => BrowserPermissionType.webAuthn,
    'displaycapture' ||
    'screen' ||
    'screencapture' => BrowserPermissionType.displayCapture,
    _ => BrowserPermissionType.unknown,
  };
}

final class BrowserPermissionRequest {
  const BrowserPermissionRequest({
    required this.requestId,
    required this.pageId,
    required this.origin,
    required this.permission,
    required this.requestedAt,
    this.userGesture = false,
  });

  factory BrowserPermissionRequest.fromJson(Map<String, Object?> json) {
    final requestedAt = DateTime.tryParse(json['requestedAt'] as String? ?? '');
    if (json['requestId'] is! String ||
        json['pageId'] is! String ||
        json['origin'] is! String ||
        requestedAt == null) {
      throw const FormatException('Browser permission request is invalid.');
    }
    return BrowserPermissionRequest(
      requestId: json['requestId']! as String,
      pageId: json['pageId']! as String,
      origin: json['origin']! as String,
      permission: BrowserPermissionType.values.firstWhere(
        (permission) => permission.name == json['permission'],
        orElse: () => BrowserPermissionType.unknown,
      ),
      requestedAt: requestedAt.toUtc(),
      userGesture: json['userGesture'] == true,
    );
  }

  final String requestId;
  final String pageId;
  final String origin;
  final BrowserPermissionType permission;
  final DateTime requestedAt;
  final bool userGesture;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'pageId': pageId,
    'origin': origin,
    'permission': permission.name,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'userGesture': userGesture,
  };
}

final class BrowserPermissionPolicy {
  const BrowserPermissionPolicy({
    this.decisions = const <BrowserPermissionType, BrowserPermissionDecision>{},
  });

  final Map<BrowserPermissionType, BrowserPermissionDecision> decisions;

  BrowserPermissionDecision decisionFor(BrowserPermissionType permission) {
    if (permission == BrowserPermissionType.displayCapture) {
      return BrowserPermissionDecision.deny;
    }
    return decisions[permission] ?? BrowserPermissionDecision.ask;
  }
}
