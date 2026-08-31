import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const PairedDeviceCredentials({
  required final String deviceId,
  required final String displayName,
  required final String runtimeId,
  required final String deviceToken,
}) {
  factory fromJson(Map<String, Object?> json) {
    return PairedDeviceCredentials(
      deviceId: json.requiredString('deviceId'),
      displayName: json.requiredString('displayName'),
      runtimeId: json.requiredString('runtimeId'),
      deviceToken: json.requiredString('deviceToken'),
    );
  }
}
