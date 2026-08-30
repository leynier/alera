import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/configuration_sync/infra/mobile_configuration_target.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'configuration_sync_service.g.dart';

@riverpod
class ConfigurationSyncSelection extends _$ConfigurationSyncSelection {
  @override
  ({String? accountId, String? hostId}) build() =>
      (accountId: null, hostId: null);
  void selectAccount(String? accountId) =>
      state = (accountId: accountId, hostId: null);
  void selectHost(String? hostId) =>
      state = (accountId: state.accountId, hostId: hostId);
}

@riverpod
Future<ConfigurationSyncService> configurationSyncService(
  Ref ref,
  String accountId,
  String? hostId,
) async {
  final accounts = ref.read(cloudAccountsControllerProvider.notifier);
  final api = ref.read(aleraCloudApiProvider) as AleraConfigurationCloudApi;
  Future<void> ensureAccount() async {
    final session = await accounts.sessionForRequest(accountId);
    if (session == null) {
      throw StateError('Sign in to this Alera account again.');
    }
  }

  final cloud = RpcConfigurationCloud((action, payload) async {
    final session = await accounts.sessionForRequest(accountId);
    if (session == null) {
      throw StateError('Sign in to this Alera account again.');
    }
    return api.configurationRequest(session, action, payload);
  });
  if (hostId == null) {
    final installationId = await ref
        .read(cloudAccountRepositoryProvider)
        .getOrCreateInstallationId();
    return ConfigurationSyncService(
      retain: () => ref.keepAlive().close,
      cloud: cloud,
      target: MobileConfigurationTarget(
        accountId: accountId,
        label:
            'This Phone (${installationId.substring(0, installationId.length.clamp(0, 8))})',
        ensureAccount: ensureAccount,
        onApplied: () {
          if (!ref.mounted) return;
          ref.invalidate(mobileAiDictationSettingsControllerProvider);
          ref.invalidate(terminalAccessoryLayoutControllerProvider);
        },
      ),
    );
  }
  final client = await ref.watch(
    hostConnectionControllerProvider(hostId).future,
  );
  if (!client.runtimeCapabilities.contains('configurationSyncV1')) {
    throw StateError(
      'Update the connected runtime to synchronize its configuration.',
    );
  }
  final hosts = await ref.read(availableHostsProvider.future);
  final host = hosts.where((h) => h.id == hostId).firstOrNull;
  final target = RuntimeConfigurationTarget(
    accountId: accountId,
    label: 'Connected Device: ${host?.effectiveName ?? hostId}',
    request: (action, payload) => client.request(action, payload),
  );
  await target
      .read(); // The runtime verifies account ownership inside its transaction.
  return ConfigurationSyncService(
    cloud: cloud,
    target: target,
    retain: () => ref.keepAlive().close,
  );
}
