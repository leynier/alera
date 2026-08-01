import 'package:alera_mobile/src/core/json_payload_fields.dart';

final class RuntimeRestartResult {
  const RuntimeRestartResult({
    required this.forced,
    required this.activeSessions,
    required this.activeJobs,
    required this.activeAgents,
    required this.activePushSubscriptions,
  });

  factory RuntimeRestartResult.fromJson(Map<String, Object?> json) {
    return RuntimeRestartResult(
      forced: json['forced'] == true,
      activeSessions: json.requiredInt('activeSessions'),
      activeJobs: json.requiredInt('activeJobs'),
      activeAgents: json.requiredInt('activeAgents'),
      activePushSubscriptions: json.requiredInt('activePushSubscriptions'),
    );
  }

  final bool forced;
  final int activeSessions;
  final int activeJobs;
  final int activeAgents;
  final int activePushSubscriptions;
}

final class RuntimeRestartBusyException implements Exception {
  const RuntimeRestartBusyException({
    required this.activeAgents,
    required this.activeSessions,
    required this.activeJobs,
    required this.activePushSubscriptions,
  });

  static final RegExp _pattern = RegExp(
    r'Runtime host has (\d+) active agent\(s\), '
    r'(\d+) active terminal session\(s\), '
    r'(\d+) active background job\(s\), and '
    r'(\d+) active push subscription\(s\)',
  );

  static RuntimeRestartBusyException? tryParse(Object error) {
    final match = _pattern.firstMatch(error.toString());
    if (match == null) {
      return null;
    }
    return RuntimeRestartBusyException(
      activeAgents: int.parse(match.group(1)!),
      activeSessions: int.parse(match.group(2)!),
      activeJobs: int.parse(match.group(3)!),
      activePushSubscriptions: int.parse(match.group(4)!),
    );
  }

  final int activeAgents;
  final int activeSessions;
  final int activeJobs;
  final int activePushSubscriptions;

  String get confirmationMessage {
    final parts = <String>[
      if (activeAgents > 0) '$activeAgents open agent(s)',
      if (activeSessions > 0) '$activeSessions active terminal session(s)',
      if (activeJobs > 0) '$activeJobs active background job(s)',
      if (activePushSubscriptions > 0)
        '$activePushSubscriptions active push subscription(s)',
    ];
    return 'Runtime has ${parts.join(', ')}. Force restart terminates them.';
  }

  @override
  String toString() => confirmationMessage;
}
