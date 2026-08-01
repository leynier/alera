import 'dart:convert';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_endpoint_rules.dart';

class PairingOffer {
  const PairingOffer({
    required this.version,
    required this.pairingId,
    required this.endpoint,
    required this.runtimeId,
    required this.hostName,
    required this.pairingSecret,
    required this.expiresAt,
    this.serverPublicKeyB64,
  });

  final int version;
  final String pairingId;
  final String endpoint;
  final String runtimeId;
  final String hostName;
  final String pairingSecret;
  final String? serverPublicKeyB64;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  static PairingOffer parse(String input) {
    final value = jsonDecode(input.trim());
    if (value is! Map<String, Object?>) {
      throw const FormatException('Pairing offer must be a JSON object');
    }
    return PairingOffer.fromJson(value);
  }

  factory PairingOffer.fromJson(Map<String, Object?> json) {
    final version = json.requiredInt('v');
    if (version != aleraMobileProtocolVersion) {
      throw FormatException('Unsupported pairing version $version');
    }
    final expiresAt = DateTime.parse(json.requiredString('expiresAt'));
    final endpoint = json.requiredString('endpoint');
    validatePairingEndpoint(endpoint);
    final offer = PairingOffer(
      version: version,
      pairingId: json.requiredString('pairingId'),
      endpoint: endpoint,
      runtimeId: json.requiredString('runtimeId'),
      hostName: json.requiredString('hostName'),
      pairingSecret: json.requiredString('pairingSecret'),
      serverPublicKeyB64: json.optionalString('serverPublicKeyB64'),
      expiresAt: expiresAt,
    );
    if (offer.isExpired) {
      throw const FormatException('Pairing offer expired');
    }
    return offer;
  }
}
