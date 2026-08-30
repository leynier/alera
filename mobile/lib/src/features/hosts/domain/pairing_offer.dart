import 'dart:convert';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_endpoint_rules.dart';

class const PairingOffer({
  required final int version,
  required final String pairingId,
  required final String endpoint,
  required final String runtimeId,
  required final String hostName,
  required final String pairingSecret,
  required final DateTime expiresAt,
  final String? serverPublicKeyB64,
  final String? endpointNetwork,
}) {
  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  static PairingOffer parse(String input) {
    final value = jsonDecode(input.trim());
    if (value is! Map<String, Object?>) {
      throw const FormatException('Pairing offer must be a JSON object');
    }
    return PairingOffer.fromJson(value);
  }

  factory fromJson(Map<String, Object?> json) {
    final version = json.requiredInt('v');
    if (version != aleraMobileProtocolVersion) {
      throw FormatException('Unsupported pairing version $version');
    }
    final expiresAt = DateTime.parse(json.requiredString('expiresAt'));
    final endpoint = json.requiredString('endpoint');
    final endpointNetwork = json.optionalString('endpointNetwork');
    validatePairingEndpoint(endpoint, endpointNetwork: endpointNetwork);
    final offer = PairingOffer(
      version: version,
      pairingId: json.requiredString('pairingId'),
      endpoint: endpoint,
      runtimeId: json.requiredString('runtimeId'),
      hostName: json.requiredString('hostName'),
      pairingSecret: json.requiredString('pairingSecret'),
      serverPublicKeyB64: json.optionalString('serverPublicKeyB64'),
      endpointNetwork: endpointNetwork,
      expiresAt: expiresAt,
    );
    if (offer.isExpired) {
      throw const FormatException('Pairing offer expired');
    }
    return offer;
  }
}
