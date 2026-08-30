import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:logging/logging.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'paired_hosts_controller.g.dart';

@riverpod
class PairedHostsController extends _$PairedHostsController {
  @override
  Future<List<PairedHostProfile>> build() {
    return ref.watch(hostRepositoryProvider).loadHosts();
  }

  Future<void> savePairedHost(
    PairedHostProfile host,
    String deviceToken,
  ) async {
    await ref.read(hostRepositoryProvider).savePairedHost(host, deviceToken);
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeHost(String hostId) async {
    await ref.read(hostRepositoryProvider).removeHost(hostId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateHostAlias(String hostId, String? alias) async {
    final normalized = alias?.trim();
    await ref
        .read(hostRepositoryProvider)
        .updateHostAlias(
          hostId,
          normalized == null || normalized.isEmpty ? null : normalized,
        );
    ref.invalidateSelf();
    await future;
  }
}

@riverpod
class AvailableHosts extends _$AvailableHosts {
  final Map<String, List<PairedHostProfile>> _remoteHosts = {};

  @override
  Future<List<PairedHostProfile>> build() async {
    final logger = Logger('AvailableHosts');
    // Credential rotation must not tear down the host list and its connections.
    final accountIdsFuture = ref
        .watch(
          cloudAccountsControllerProvider.selectAsync(
            (sessions) =>
                (sessions.map((session) => session.account.id).toList()..sort())
                    .join('\n'),
          ),
        )
        .catchError((Object error, StackTrace stackTrace) {
          logger.warning(
            'could not load cloud accounts for host discovery',
            error,
            stackTrace,
          );
          return '';
        });
    final pairedFuture = ref.watch(pairedHostsControllerProvider.future);
    var backgrounded = false;
    ref.listen(appLifecycleControllerProvider, (_, next) {
      if (next == AppLifecycleState.paused) backgrounded = true;
      if (next == AppLifecycleState.resumed && backgrounded) {
        backgrounded = false;
        ref.invalidateSelf();
      }
    });
    final paired = await pairedFuture;
    final byRuntime = <String, PairedHostProfile>{
      for (final host in paired) host.runtimeId: host,
    };
    final accountIds = await accountIdsFuture;
    _remoteHosts.removeWhere((id, _) => !accountIds.split('\n').contains(id));
    if (!ref.mounted || accountIds.isEmpty) {
      return byRuntime.values.toList(growable: false);
    }
    final api = ref.watch(aleraRelayCloudApiProvider);
    final accounts = ref.read(cloudAccountsControllerProvider.notifier);
    final discoveries = await Future.wait(
      accountIds.split('\n').map((accountId) async {
        try {
          final session = await accounts.sessionForRequest(accountId);
          if (session == null) return <PairedHostProfile>[];
          final runtimes = await accounts.withSession(
            accountId,
            api.discoverRuntimes,
          );
          final hosts = runtimes
              .map(
                (runtime) => PairedHostProfile.fromCloudRuntime(
                  accountId,
                  runtime,
                ).withDiscovery(stale: false, at: DateTime.now().toUtc()),
              )
              .toList();
          if (ref.mounted) _remoteHosts[accountId] = hosts;
          return hosts;
        } on Object catch (error, stackTrace) {
          logger.warning(
            'could not discover remote runtimes for $accountId',
            error,
            stackTrace,
          );
          // A temporary discovery outage does not revoke a known host or its connection.
          return (_remoteHosts[accountId] ?? <PairedHostProfile>[])
              .map((host) => host.withDiscovery(stale: true))
              .toList();
        }
      }),
    );
    for (final remote in discoveries.expand((hosts) => hosts)) {
      final pairedHost = byRuntime[remote.runtimeId];
      byRuntime[remote.runtimeId] = pairedHost == null
          ? remote
          : pairedHost
                .withCloudAccount(remote.accountId!)
                .withDiscovery(
                  stale: remote.discoveryStale,
                  at: remote.discoveredAt,
                );
    }
    return byRuntime.values.toList(growable: false);
  }
}
