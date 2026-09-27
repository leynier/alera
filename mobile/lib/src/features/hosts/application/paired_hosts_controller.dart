import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
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

@Riverpod(keepAlive: true)
class AvailableHosts extends _$AvailableHosts {
  final Map<String, List<PairedHostProfile>> _remoteHosts = {};
  bool _publishedInitialLocalHosts = false;

  String _accountIds(AsyncValue<List<CloudAccountSession>> accounts) {
    final sessions = accounts.value;
    if (sessions == null) return '';
    return (sessions.map((session) => session.account.id).toList()..sort())
        .join('\n');
  }

  @override
  Future<List<PairedHostProfile>> build() async {
    final logger = Logger('AvailableHosts');
    final paired = await ref.watch(pairedHostsControllerProvider.future);

    var accountsState = ref.read(cloudAccountsControllerProvider);
    if (paired.isEmpty && accountsState.isLoading && !accountsState.hasValue) {
      // With no local host to show, an unresolved cloud account read is not a
      // confirmed empty catalog. Keep the first load pending until storage
      // resolves to accounts or an error.
      try {
        await ref.read(cloudAccountsControllerProvider.future);
      } on Object {
        // The settled error is logged from the AsyncValue below.
      }
      accountsState = ref.read(cloudAccountsControllerProvider);
    }
    if (accountsState.hasError) {
      logger.warning(
        'could not load cloud accounts for host discovery',
        accountsState.error,
        accountsState.stackTrace,
      );
    }
    var accountIds = _accountIds(accountsState);
    ref.listen(cloudAccountsControllerProvider, (_, next) {
      if (next.hasError) {
        logger.warning(
          'could not load cloud accounts for host discovery',
          next.error,
          next.stackTrace,
        );
      }
      final nextIds = _accountIds(next);
      if (nextIds == accountIds) return;
      accountIds = nextIds;
      ref.invalidateSelf();
    });

    var backgrounded = false;
    ref.listen(appLifecycleControllerProvider, (_, next) {
      if (next == AppLifecycleState.paused) backgrounded = true;
      if (next == AppLifecycleState.resumed && backgrounded) {
        backgrounded = false;
        ref.invalidateSelf();
      }
    });

    if (!_publishedInitialLocalHosts && paired.isNotEmpty) {
      _publishedInitialLocalHosts = true;
      if (accountIds.isNotEmpty && ref.mounted) {
        // Publish local hosts before optional network discovery even when cloud
        // accounts were already available at startup.
        unawaited(
          Future<void>(() {
            if (ref.mounted) ref.invalidateSelf();
          }),
        );
      }
      final published = <String, PairedHostProfile>{
        for (final host in paired) host.runtimeId: host,
      };
      final allowedAccounts = accountIds.split('\n').toSet();
      for (final entry in _remoteHosts.entries) {
        if (!allowedAccounts.contains(entry.key)) continue;
        for (final remote in entry.value) {
          published.putIfAbsent(remote.runtimeId, () => remote);
        }
      }
      return published.values.toList(growable: false);
    }

    final discoveryAccountIds = accountIds;
    final byRuntime = <String, PairedHostProfile>{
      for (final host in paired) host.runtimeId: host,
    };
    _remoteHosts.removeWhere(
      (id, _) => !discoveryAccountIds.split('\n').contains(id),
    );
    if (!ref.mounted || discoveryAccountIds.isEmpty) {
      return byRuntime.values.toList(growable: false);
    }
    final api = ref.watch(aleraRelayCloudApiProvider);
    final accounts = ref.read(cloudAccountsControllerProvider.notifier);
    final discoveries = await Future.wait(
      discoveryAccountIds.split('\n').map((accountId) async {
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
