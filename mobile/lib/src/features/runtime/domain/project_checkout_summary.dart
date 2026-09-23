import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const ProjectCheckoutSummary({
  required final String hostId,
  required final String path,
  final String? hostName,
}) {
  String get label => hostId == 'local' ? 'Paired Device' : hostName ?? path;

  factory fromJson(Map<String, Object?> json) => ProjectCheckoutSummary(
    hostId: json.requiredString('hostId'),
    path: json.requiredString('path'),
    hostName: json.optionalString('hostName'),
  );
}
