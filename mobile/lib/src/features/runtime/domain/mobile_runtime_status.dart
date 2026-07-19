import 'package:alera_mobile/src/core/json_payload_fields.dart';

class MobileRuntimeStatus {
  const MobileRuntimeStatus({
    required this.protocolVersion,
    required this.devices,
    required this.activePairings,
  });

  final int protocolVersion;
  final List<MobileDeviceSummary> devices;
  final List<Object?> activePairings;

  factory MobileRuntimeStatus.fromJson(Map<String, Object?> json) {
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

class MobileDeviceSummary {
  const MobileDeviceSummary({
    required this.id,
    required this.displayName,
    required this.permission,
    this.lastSeenAt,
    this.revokedAt,
  });

  final String id;
  final String displayName;
  final String permission;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  factory MobileDeviceSummary.fromJson(Map<String, Object?> json) {
    return MobileDeviceSummary(
      id: json.requiredString('id'),
      displayName: json.requiredString('displayName'),
      permission: json.requiredString('permission'),
      lastSeenAt: json.optionalDateTime('lastSeenAt'),
      revokedAt: json.optionalDateTime('revokedAt'),
    );
  }
}
