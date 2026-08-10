import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_endpoint_rules.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';

class PairedHostProfile {
  const PairedHostProfile({
    required this.id,
    required this.displayName,
    required this.endpoint,
    required this.runtimeId,
    required this.deviceId,
    required this.pairedAt,
    this.serverPublicKeyB64,
    this.endpointNetwork,
    this.alias,
  });

  final String id;
  final String displayName;
  final String endpoint;
  final String runtimeId;
  final String deviceId;
  final String? serverPublicKeyB64;
  final String? endpointNetwork;
  final DateTime pairedAt;

  /// Local, user-chosen name for this host. Never sent to the runtime; the
  /// desktop keeps advertising its own host name.
  final String? alias;

  String get effectiveName => alias ?? displayName;

  PairedHostProfile withAlias(String? alias) {
    return PairedHostProfile(
      id: id,
      displayName: displayName,
      endpoint: endpoint,
      runtimeId: runtimeId,
      deviceId: deviceId,
      pairedAt: pairedAt,
      serverPublicKeyB64: serverPublicKeyB64,
      endpointNetwork: endpointNetwork,
      alias: alias,
    );
  }

  factory PairedHostProfile.fromPairingResult(
    PairingOffer offer,
    PairedDeviceCredentials credentials,
  ) {
    // A pair response from a different runtime than the offer promised means
    // the endpoint reached the wrong host (for example a non-tailnet CGNAT
    // address); refuse to store credentials for it.
    if (credentials.runtimeId != offer.runtimeId) {
      throw const FormatException(
        'Pairing response runtime ID does not match the offer',
      );
    }
    return PairedHostProfile(
      id: offer.runtimeId,
      displayName: offer.hostName,
      endpoint: offer.endpoint,
      runtimeId: credentials.runtimeId,
      deviceId: credentials.deviceId,
      serverPublicKeyB64: offer.serverPublicKeyB64,
      endpointNetwork: offer.endpointNetwork,
      pairedAt: DateTime.now().toUtc(),
    );
  }

  factory PairedHostProfile.fromJson(Map<String, Object?> json) {
    final endpoint = json.requiredString('endpoint');
    final endpointNetwork = json.optionalString('endpointNetwork');
    validatePairingEndpoint(endpoint, endpointNetwork: endpointNetwork);
    return PairedHostProfile(
      id: json.requiredString('id'),
      displayName: json.requiredString('displayName'),
      endpoint: endpoint,
      runtimeId: json.requiredString('runtimeId'),
      deviceId: json.requiredString('deviceId'),
      serverPublicKeyB64: json.optionalString('serverPublicKeyB64'),
      endpointNetwork: endpointNetwork,
      pairedAt: DateTime.parse(json.requiredString('pairedAt')),
      alias: json.optionalString('alias'),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'displayName': displayName,
      'endpoint': endpoint,
      'runtimeId': runtimeId,
      'deviceId': deviceId,
      'serverPublicKeyB64': serverPublicKeyB64,
      if (endpointNetwork != null) 'endpointNetwork': endpointNetwork,
      'pairedAt': pairedAt.toUtc().toIso8601String(),
      if (alias != null) 'alias': alias,
    };
  }
}
