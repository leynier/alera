class MobileDevice {
  const MobileDevice({
    required this.id,
    required this.displayName,
    required this.permission,
    required this.pairedAt,
    this.publicKeyB64,
    this.lastSeenAt,
    this.revokedAt,
  });

  factory MobileDevice.fromJson(Map<String, Object?> json) {
    return MobileDevice(
      id: _requiredString(json, 'id'),
      displayName: _requiredString(json, 'displayName'),
      publicKeyB64: _optionalString(json['publicKeyB64']),
      permission: _requiredString(json, 'permission'),
      pairedAt: _dateTime(json['pairedAt']),
      lastSeenAt: _optionalDateTime(json['lastSeenAt']),
      revokedAt: _optionalDateTime(json['revokedAt']),
    );
  }

  final String id;
  final String displayName;
  final String? publicKeyB64;
  final String permission;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

DateTime _dateTime(Object? value) {
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw const FormatException('date must be an ISO-8601 string.');
}

DateTime? _optionalDateTime(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  return null;
}
