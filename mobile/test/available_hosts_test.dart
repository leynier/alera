import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_cloud_account_repository.dart';
import 'support/memory_host_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Local hosts remain available if account storage fails', () async {
    final accounts = _Accounts();
    final container = _container(accounts, _Discovery());
    addTearDown(container.dispose);
    container.listen(availableHostsProvider, (_, _) {});
    final hosts = container.read(availableHostsProvider.future);
    accounts.initial.completeError(StateError('Secure storage unavailable'));
    expect((await hosts).map((host) => host.id), ['paired']);
  });

  test('Initial discovery waits for accounts and credential rotation keeps hosts mounted', () async {
    final accounts = _Accounts();
    final api = _Discovery();
    final container = _container(accounts, api);
    addTearDown(container.dispose);
    final published = <List<PairedHostProfile>>[];
    container.listen(availableHostsProvider, (_, next) {
      if (!next.isLoading && next.hasValue) published.add(next.requireValue);
    });
    await pumpEventQueue();
    expect(published, isEmpty);
    expect(api.calls, 0);

    accounts.initial.complete([_session()]);
    final hosts = await container.read(availableHostsProvider.future);
    expect(hosts.map((host) => host.id), ['paired', 'remote']);
    expect(published, hasLength(1));
    expect(api.calls, 1);

    accounts.replace([_session(token: 'rotated')]);
    await pumpEventQueue();
    expect(api.calls, 1);
    expect(published, hasLength(1));
    expect(container.read(availableHostsProvider).requireValue, same(hosts));
  });

  test(
    'Discovery outages retain known hosts, but sign-out removes them',
    () async {
      final accounts = _Accounts()..initial.complete([_session()]);
      final api = _Discovery();
      final container = _container(accounts, api);
      addTearDown(container.dispose);
      container.listen(availableHostsProvider, (_, _) {});
      await container.read(availableHostsProvider.future);
      api.fail = true;
      container.invalidate(availableHostsProvider);
      final hosts = await container.read(availableHostsProvider.future);
      expect(hosts.map((host) => host.id), ['paired', 'remote']);

      accounts.replace([]);
      await pumpEventQueue();
      expect(
        (await container.read(availableHostsProvider.future))
            .map((host) => host.id),
        ['paired'],
      );
    },
  );

  test(
    'Resume refreshes discovery once and focus-only changes do not',
    () async {
      final accounts = _Accounts()..initial.complete([_session()]);
      final api = _Discovery();
      final lifecycle = _Lifecycle();
      final container = _container(accounts, api, lifecycle: lifecycle);
      addTearDown(container.dispose);
      container.listen(availableHostsProvider, (_, _) {});
      await container.read(availableHostsProvider.future);
      lifecycle.change(AppLifecycleState.inactive);
      lifecycle.change(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(api.calls, 1);
      lifecycle.change(AppLifecycleState.paused);
      lifecycle.change(AppLifecycleState.inactive);
      lifecycle.change(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(api.calls, 2);
    },
  );

  test('Expired credentials are refreshed before discovery', () async {
    final accounts = _Accounts()..initial.complete([_session(expired: true)]);
    final api = _Discovery();
    final container = _container(accounts, api);
    addTearDown(container.dispose);
    container.listen(availableHostsProvider, (_, _) {});
    await container.read(availableHostsProvider.future);
    expect(api.refreshes, 1);
    expect(api.discoveryTokens, ['fresh']);
    expect(api.calls, 1);
  });
}

ProviderContainer _container(
  _Accounts accounts,
  _Discovery api, {
  _Lifecycle? lifecycle,
}) {
  final repository = MemoryHostRepository();
  unawaited(
    repository.savePairedHost(
      PairedHostProfile(
        id: 'paired',
        displayName: 'Paired',
        endpoint: 'ws://localhost:1',
        runtimeId: 'paired',
        deviceId: 'phone',
        pairedAt: DateTime.utc(2026),
      ),
      'token',
    ),
  );
  return ProviderContainer(
    overrides: [
      hostRepositoryProvider.overrideWithValue(repository),
      cloudAccountRepositoryProvider.overrideWithValue(
        MemoryCloudAccountRepository(),
      ),
      cloudAccountsControllerProvider.overrideWith(() => accounts),
      aleraRelayCloudApiProvider.overrideWithValue(api),
      aleraCloudApiProvider.overrideWithValue(api),
      appLifecycleControllerProvider.overrideWith(
        () => lifecycle ?? _Lifecycle(),
      ),
    ],
  );
}

CloudAccountSession _session({String token = 'access', bool expired = false}) =>
    CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account',
        email: 'owner@example.com',
      ),
      accessToken: token,
      refreshToken: 'refresh',
      accessTokenExpiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2099),
    );

class _Accounts extends CloudAccountsController {
  final initial = Completer<List<CloudAccountSession>>();
  @override
  Future<List<CloudAccountSession>> build() => initial.future;
  void replace(List<CloudAccountSession> sessions) =>
      state = AsyncData(sessions);
}

class _Lifecycle extends AppLifecycleController {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;
  void change(AppLifecycleState next) => state = next;
}

class _Discovery implements AleraRelayCloudApi, AleraCloudApi {
  int calls = 0;
  int refreshes = 0;
  bool fail = false;
  final discoveryTokens = <String>[];
  @override
  Future<List<CloudRuntimeProfile>> discoverRuntimes(
    CloudAccountSession session,
  ) async {
    calls++;
    discoveryTokens.add(session.accessToken);
    if (fail) throw TimeoutException('Cloud unavailable');
    return [
      CloudRuntimeProfile(
        id: 'remote',
        name: 'Remote',
        lastSeenAt: DateTime.utc(2026),
        relayPublicKey: 'public',
        relayKeyVersion: 1,
      ),
    ];
  }

  @override
  Future<CloudAccountSession> refreshSession(
    CloudAccountSession session,
  ) async {
    refreshes++;
    return _session(token: 'fresh');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
