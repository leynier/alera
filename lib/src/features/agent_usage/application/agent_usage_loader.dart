import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';

class AgentUsageRequest {
  const AgentUsageRequest({
    required this.hostId,
    required this.target,
    required this.settings,
    required this.sinceDay,
    required this.untilDay,
  });

  final String hostId;
  final SshTarget? target;
  final AgentQuotaHostSettings settings;
  final String sinceDay;
  final String untilDay;
}

abstract interface class AgentUsageLoader {
  Future<Map<String, Object?>> fetch(AgentUsageRequest request);
}
