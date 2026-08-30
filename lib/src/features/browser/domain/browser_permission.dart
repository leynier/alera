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

final class const BrowserPermissionRequest({
  required final String requestId,
  required final String pageId,
  required final String origin,
  required final BrowserPermissionType permission,
  required final DateTime requestedAt,
  final bool userGesture = false,
}) {
  factory fromJson(Map<String, Object?> json) {
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

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'pageId': pageId,
    'origin': origin,
    'permission': permission.name,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'userGesture': userGesture,
  };
}

final class const BrowserPermissionPolicy({
  final Map<BrowserPermissionType, BrowserPermissionDecision> decisions =
      const <BrowserPermissionType, BrowserPermissionDecision>{},
}) {
  BrowserPermissionDecision decisionFor(BrowserPermissionType permission) {
    if (permission == BrowserPermissionType.displayCapture) {
      return BrowserPermissionDecision.deny;
    }
    return decisions[permission] ?? BrowserPermissionDecision.ask;
  }
}
