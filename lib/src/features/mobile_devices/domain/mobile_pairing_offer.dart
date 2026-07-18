import 'dart:convert';

/// A pending pairing offer as listed by `mobile.status.get`. The pairing
/// secret is never included here; it is only returned once at creation time
/// as part of [MobilePairingOfferGrant].
class MobilePairingOffer {
  const MobilePairingOffer({
    required this.id,
    required this.endpoint,
    required this.createdAt,
    required this.expiresAt,
    this.expectedDeviceName,
  });

  factory MobilePairingOffer.fromJson(Map<String, Object?> json) {
    return MobilePairingOffer(
      id: _requiredString(json, 'id'),
      endpoint: _requiredString(json, 'endpoint'),
      expectedDeviceName: _optionalString(json['expectedDeviceName']),
      createdAt: _dateTime(json['createdAt']),
      expiresAt: _dateTime(json['expiresAt']),
    );
  }

  final String id;
  final String endpoint;
  final String? expectedDeviceName;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// The full pairing payload returned by `mobile.pairing.create`, including
/// the one-time pairing secret the mobile app scans or pastes.
class MobilePairingOfferGrant {
  const MobilePairingOfferGrant({
    required this.pairingId,
    required this.endpoint,
    required this.hostName,
    required this.expiresAt,
    required Map<String, Object?> rawPayload,
  }) : _rawPayload = rawPayload; // ignore: prefer_initializing_formals

  factory MobilePairingOfferGrant.fromJson(Map<String, Object?> json) {
    return MobilePairingOfferGrant(
      pairingId: _requiredString(json, 'pairingId'),
      endpoint: _requiredString(json, 'endpoint'),
      hostName: _requiredString(json, 'hostName'),
      expiresAt: _dateTime(json['expiresAt']),
      rawPayload: Map<String, Object?>.from(json),
    );
  }

  final String pairingId;
  final String endpoint;
  final String hostName;
  final DateTime expiresAt;

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
