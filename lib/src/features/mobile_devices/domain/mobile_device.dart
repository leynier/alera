class const MobileDevice({
  required final String id,
  required final String displayName,
  required final String permission,
  required final DateTime pairedAt,
  final String? publicKeyB64,
  final DateTime? lastSeenAt,
  final DateTime? revokedAt,
}) {
  factory fromJson(Map<String, Object?> json) {
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
