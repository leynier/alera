import 'dart:async';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Concurrent 401 responses share one session refresh and never retry a second 401', () async {
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account-1',
        email: 'test@example.test',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(hours: 1),
      ),
    );
    final api = _RefreshApi(session);
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(
          _MemoryRepository(session),
        ),
        aleraCloudApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(cloudAccountsControllerProvider.notifier);
    final requests = <String>[];
    Future<String> request(CloudAccountSession value) async {
      requests.add(value.accessToken);
      if (value.accessToken == 'access') {
        throw const AleraCloudException('expired', statusCode: 401);
      }
      return value.accessToken;
    }

    final operations = Future.wait(
      List.generate(8, (_) => controller.withSession('account-1', request)),
    );
    await api.refreshStarted.future;
    api.refreshRelease.complete();
    expect(await operations, everyElement('rotated-access'));
    expect(api.refreshCalls, 1);
    expect(requests.where((value) => value == 'rotated-access'), hasLength(8));
    var attempts = 0;
    await expectLater(
      controller.withSession('account-1', (_) async {
        attempts++;
        throw const AleraCloudException('unauthorized', statusCode: 401);
      }),
      throwsA(isA<AleraCloudException>()),
    );
    expect(attempts, 2);
  });
  test('Remote Removal Failure Keeps The Local Session For Retry', () async {
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account-1',
        email: 'owner@example.com',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(hours: 1),
      ),
      subscriptions: const <String, RuntimePushPreferences>{
        'runtime-1': RuntimePushPreferences(),
      },
    );
    final repository = _MemoryRepository(session);
    final api = _RemovalApi();
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(repository),
        aleraCloudApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(cloudAccountsControllerProvider.future);

    await expectLater(
      container
          .read(cloudAccountsControllerProvider.notifier)
          .removeFromThisPhone('account-1'),
      throwsA(isA<StateError>()),
    );

    expect(repository.sessions, hasLength(1));
    expect(container.read(cloudAccountsControllerProvider).value, hasLength(1));
    expect(api.pushTokenDeleteCalls, 0);
  });

  test('Revoked Session Can Still Be Removed From The Phone', () async {
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account-1',
        email: 'owner@example.com',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(hours: 1),
      ),
      subscriptions: const <String, RuntimePushPreferences>{
        'runtime-1': RuntimePushPreferences(),
      },
    );
    final repository = _MemoryRepository(session);
    final api = _RemovalApi(
      removalError: const AleraCloudException(
        'The account session has been revoked.',
        statusCode: 401,
        code: 'session_revoked',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(repository),
        aleraCloudApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await container.read(cloudAccountsControllerProvider.future);

    await container
        .read(cloudAccountsControllerProvider.notifier)
        .removeFromThisPhone('account-1');

    expect(repository.sessions, isEmpty);
    expect(container.read(cloudAccountsControllerProvider).value, isEmpty);
    expect(api.pushTokenDeleteCalls, 0);
  });

  test(
    'Session Refresh Is Serialized And Cannot Replace Reenrollment',
    () async {
      final expired = CloudAccountSession(
        account: const CloudAccountProfile(
          id: 'account-1',
          email: 'owner@example.com',
        ),
        accessToken: 'expired-access',
        refreshToken: 'expired-refresh',
        accessTokenExpiresAt: DateTime.now().toUtc(),
      );
      final reenrolled = expired.copyWith(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
        accessTokenExpiresAt: DateTime.now().toUtc().add(
          const Duration(minutes: 15),
        ),
      );
      final repository = _MemoryRepository(expired);
      final api = _RefreshApi(reenrolled);
      final container = ProviderContainer(
        overrides: [
          cloudAccountRepositoryProvider.overrideWithValue(repository),
          aleraCloudApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      await container.read(cloudAccountsControllerProvider.future);
      final controller = container.read(
        cloudAccountsControllerProvider.notifier,
      );

      final firstRefresh = controller.sessionForRequest('account-1');
      await api.refreshStarted.future;
      final secondRefresh = controller.sessionForRequest('account-1');
      await controller.redeemEnrollment('enrollment-code');
      api.refreshRelease.complete();
      await Future.wait(<Future<CloudAccountSession?>>[
        firstRefresh,
        secondRefresh,
      ]);

      expect(api.refreshCalls, 1);
      expect(repository.sessions.single.refreshToken, 'new-refresh');
      expect(
        container
            .read(cloudAccountsControllerProvider)
            .value
            ?.single
            .refreshToken,
        'new-refresh',
      );
    },
  );
}

class _MemoryRepository implements CloudAccountRepository {
  _MemoryRepository(CloudAccountSession session)
    : sessions = <CloudAccountSession>[session];

  final List<CloudAccountSession> sessions;

  @override
  Future<String> getOrCreateInstallationId() async => 'installation-1';

  @override
  Future<List<CloudAccountSession>> loadSessions() async =>
      List<CloudAccountSession>.of(sessions);

  @override
  Future<void> removeSession(String accountId) async {
    sessions.removeWhere((session) => session.account.id == accountId);
  }

  @override
  Future<void> saveSession(CloudAccountSession session) async {
    sessions.removeWhere((item) => item.account.id == session.account.id);
    sessions.add(session);
  }
}

class _RefreshApi implements AleraCloudApi {
  _RefreshApi(this.reenrolled);

  final CloudAccountSession reenrolled;
  final Completer<void> refreshStarted = Completer<void>();
  final Completer<void> refreshRelease = Completer<void>();
  int refreshCalls = 0;

  @override
  Future<CloudAccountSession> refreshSession(
    CloudAccountSession session,
  ) async {
    refreshCalls += 1;
    if (!refreshStarted.isCompleted) {
      refreshStarted.complete();
    }
    await refreshRelease.future;
    return session.copyWith(
      accessToken: 'rotated-access',
      refreshToken: 'rotated-refresh',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(minutes: 15),
      ),
    );
  }

  @override
  Future<CloudEnrollmentResult> redeemEnrollment({
    required String code,
    required String deviceId,
    required String deviceName,
  }) async =>
      CloudEnrollmentResult(session: reenrolled, runtimeId: 'runtime-1');

  @override
  Future<CloudAccountProfile> accountStatus(
    CloudAccountSession session,
  ) async => session.account;

  @override
  Future<void> deletePushToken(CloudAccountSession session) async {}

  @override
  Future<void> deleteSubscription({
    required CloudAccountSession session,
    required String runtimeId,
  }) async {}

  @override
  Future<void> putSubscription({
    required CloudAccountSession session,
    required String runtimeId,
    required RuntimePushPreferences preferences,
  }) async {}

  @override
  Future<void> registerPushToken({
    required CloudAccountSession session,
    required String token,
    required String platform,
  }) async {}

  @override
  Future<void> revokeSession(CloudAccountSession session) async {}
}

class _RemovalApi implements AleraCloudApi {
  _RemovalApi({this.removalError});

  final Object? removalError;
  int pushTokenDeleteCalls = 0;

  @override
  Future<void> deleteSubscription({
    required CloudAccountSession session,
    required String runtimeId,
  }) {
    throw removalError ?? StateError('cloud unavailable');
  }

  @override
  Future<void> deletePushToken(CloudAccountSession session) async {
    pushTokenDeleteCalls += 1;
  }

  @override
  Future<CloudAccountProfile> accountStatus(
    CloudAccountSession session,
  ) async => session.account;

  @override
  Future<void> putSubscription({
    required CloudAccountSession session,
    required String runtimeId,
    required RuntimePushPreferences preferences,
  }) async {}

  @override
  Future<void> registerPushToken({
    required CloudAccountSession session,
    required String token,
    required String platform,
  }) async {}

  @override
  Future<CloudEnrollmentResult> redeemEnrollment({
    required String code,
    required String deviceId,
    required String deviceName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CloudAccountSession> refreshSession(
    CloudAccountSession session,
  ) async => session;

  @override
  Future<void> revokeSession(CloudAccountSession session) async {}
}
