import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const MobileRuntimeStatus({
  required final int protocolVersion,
  required final List<MobileDeviceSummary> devices,
  required final List<Object?> activePairings,
}) {
  factory fromJson(Map<String, Object?> json) {
    return MobileRuntimeStatus(
      protocolVersion: json.requiredInt('protocolVersion'),
      devices: <MobileDeviceSummary>[
        for (final item in json.objectList('devices'))
          if (item is Map) MobileDeviceSummary.fromJson(asJsonMap(item)),
      ],
      activePairings: json.objectList('activePairings'),
    );
  }
}

class const MobileDeviceSummary({
  required final String id,
  required final String displayName,
  required final String permission,
  final DateTime? lastSeenAt,
  final DateTime? revokedAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    return MobileDeviceSummary(
      id: json.requiredString('id'),
      displayName: json.requiredString('displayName'),
      permission: json.requiredString('permission'),
      lastSeenAt: json.optionalDateTime('lastSeenAt'),
      revokedAt: json.optionalDateTime('revokedAt'),
    );
  }
}
