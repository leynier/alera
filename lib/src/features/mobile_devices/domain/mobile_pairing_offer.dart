import 'dart:convert';

/// A pending pairing offer as listed by `mobile.status.get`. The pairing
/// secret is never included here; it is only returned once at creation time
/// as part of [MobilePairingOfferGrant].
class const MobilePairingOffer({
  required final String id,
  required final String endpoint,
  required final DateTime createdAt,
  required final DateTime expiresAt,
  final String? expectedDeviceName,
}) {
  factory fromJson(Map<String, Object?> json) {
    return MobilePairingOffer(
      id: _requiredString(json, 'id'),
      endpoint: _requiredString(json, 'endpoint'),
      expectedDeviceName: _optionalString(json['expectedDeviceName']),
      createdAt: _dateTime(json['createdAt']),
      expiresAt: _dateTime(json['expiresAt']),
    );
  }
}

/// The full pairing payload returned by `mobile.pairing.create`, including
/// the one-time pairing secret the mobile app scans or pastes.
class const MobilePairingOfferGrant({
  required final String pairingId,
  required final String endpoint,
  required final String hostName,
  required final DateTime expiresAt,
  required this._rawPayload,
}) {
  // ignore: prefer_initializing_formals

  factory fromJson(Map<String, Object?> json) {
    return MobilePairingOfferGrant(
      pairingId: _requiredString(json, 'pairingId'),
      endpoint: _requiredString(json, 'endpoint'),
      hostName: _requiredString(json, 'hostName'),
      expiresAt: _dateTime(json['expiresAt']),
      rawPayload: Map<String, Object?>.from(json),
    );
  }

  // The QR payload must round-trip the RPC response verbatim so the keys the
  // mobile app parses can never drift from what the runtime emitted.
  final Map<String, Object?> _rawPayload;

  String toQrJson() => jsonEncode(_rawPayload);
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
