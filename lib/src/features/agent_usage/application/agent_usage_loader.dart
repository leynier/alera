import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';

class const AgentUsageRequest({
  required final String hostId,
  required final SshTarget? target,
  required final AgentQuotaHostSettings settings,
  required final String sinceDay,
  required final String untilDay,
});

abstract interface class AgentUsageLoader {
  Future<Map<String, Object?>> fetch(AgentUsageRequest request);
}
