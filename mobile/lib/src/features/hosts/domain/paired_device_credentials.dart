import 'package:alera_mobile/src/core/json_payload_fields.dart';

class PairedDeviceCredentials {
  const PairedDeviceCredentials({
    required this.deviceId,
    required this.displayName,
    required this.runtimeId,
    required this.deviceToken,
  });

  final String deviceId;
  final String displayName;
  final String runtimeId;
  final String deviceToken;

  factory PairedDeviceCredentials.fromJson(Map<String, Object?> json) {
    return PairedDeviceCredentials(
      deviceId: json.requiredString('deviceId'),
      displayName: json.requiredString('displayName'),
      runtimeId: json.requiredString('runtimeId'),
      deviceToken: json.requiredString('deviceToken'),
    );
  }
}
