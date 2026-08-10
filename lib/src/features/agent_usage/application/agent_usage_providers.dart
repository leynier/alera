import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_usage_providers.g.dart';

@riverpod
Future<AgentUsageSnapshot> agentUsage(Ref ref, int days) async {
  final hostId = ref.watch(
    workbenchControllerProvider.select(
      (state) => state.activeWorkspace?.hostId ?? 'local',
    ),
  );
  final settings = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.agents.quotas.forHost(hostId),
    ),
  );
  final targets = ref.watch(sshTargetsProvider).value ?? const <SshTarget>[];
  final target = hostId == 'local'
      ? null
      : targets.where((candidate) => candidate.id == hostId).firstOrNull;
  final now = DateTime.now();
  final until = DateTime(now.year, now.month, now.day);
  final since = until.subtract(Duration(days: days - 1));
  final payload = <String, Object?>{
    'sinceDay': _usageDay(since),
    'untilDay': _usageDay(until),
  };
  final response = hostId == 'local'
      ? _mapValue(
          await ref
              .watch(runtimeHostClientProvider)
              .runtimeRequest(
                'agentUsage.snapshot',
                payload,
                const Duration(seconds: 90),
              ),
        )
      : await ref
            .watch(runtimeProxyClientProvider)
            .request(
              hostId: hostId,
              target: target,
              type: 'agentUsage.fetch',
              timeout: const Duration(seconds: 90),
              payload: <String, Object?>{
                ...payload,
                'claudeDefaultEnabled': settings.claudeDefaultEnabled,
                'claudeProfiles': <Map<String, String>>[
                  for (final profile in settings.claudeProfiles)
                    <String, String>{
                      'alias': profile.alias,
                      'profile': profile.profile,
                    },
                ],
              },
            );
  return AgentUsageSnapshot.fromJson(response);
}

String _usageDay(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is! Map) {
    throw const FormatException('Agent usage response must be an object.');
  }
  return Map<String, Object?>.from(value);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
