import 'dart:async';

import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_settings_controller.g.dart';

@riverpod
class HostSettingsController extends _$HostSettingsController {
  @override
  Future<PortableHostSettings> build(String hostId) async {
    final client = await ref.watch(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsPortableSettings) {
      throw UnsupportedError('Update The Runtime To Manage Settings.');
    }
    final subscription = client.events.listen((event) {
      if (event.name == 'runtimeSettingsChanged') {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    return client.loadPortableSettings();
  }

  Future<void> updateWorkspaceDirectory(String? value) {
    return _update(<String, Object?>{'workspaceDirectory': value});
  }

  Future<void> setConfirmProjectRemoval(bool value) {
    return _update(<String, Object?>{'confirmProjectRemoval': value});
  }

  Future<void> setConfirmWorkspaceRemoval(bool value) {
    return _update(<String, Object?>{'confirmWorkspaceRemoval': value});
  }

  Future<void> setAgentHook(String agent, bool value) async {
    final current = state.requireValue;
    final hooks = <String, bool>{...current.agentStatusHooks, agent: value};
    await _update(<String, Object?>{'agentStatusHooks': hooks});
  }

  Future<void> updateQuotas(QuotaSettings settings) {
    return _update(<String, Object?>{'agentQuotas': settings.toJson()});
  }

  Future<void> _update(Map<String, Object?> patch) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    state = await AsyncValue.guard(() => client.updatePortableSettings(patch));
  }
}
