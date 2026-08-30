import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_loader.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeAgentUsageLoader implements AgentUsageLoader {
  const RuntimeAgentUsageLoader(this._runtimeClient, this._proxyClient);

  final RuntimeHostClient _runtimeClient;
  final RuntimeProxyClient _proxyClient;

  @override
  Future<Map<String, Object?>> fetch(AgentUsageRequest request) async {
    final payload = <String, Object?>{
      'sinceDay': request.sinceDay,
      'untilDay': request.untilDay,
      'includeGrok': true,
    };
    if (request.hostId == 'local') {
      return _mapValue(
        await _runtimeClient.runtimeRequest(
          'agentUsage.snapshot',
          payload,
          const Duration(seconds: 90),
        ),
      );
    }
    return _proxyClient.request(
      hostId: request.hostId,
      target: request.target,
      type: 'agentUsage.fetch',
      timeout: const Duration(seconds: 90),
      payload: <String, Object?>{
        ...payload,
        'claudeDefaultEnabled': request.settings.claudeDefaultShowInUsage,
        'claudeProfiles': <Map<String, String>>[
          for (final profile in request.settings.claudeProfiles)
            if (profile.showInUsage)
              <String, String>{
                'alias': profile.usageLabel,
                'profile': profile.profile,
              },
        ],
      },
    );
  }
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is! Map) {
    throw const FormatException('Agent usage response must be an object.');
  }
  return Map<String, Object?>.from(value);
}
