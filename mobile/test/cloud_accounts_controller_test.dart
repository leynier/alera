import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  Future<void> saveSession(CloudAccountSession session) async {}
}

class _RemovalApi implements AleraCloudApi {
  int pushTokenDeleteCalls = 0;

  @override
  Future<void> deleteSubscription({
    required CloudAccountSession session,
    required String runtimeId,
  }) {
    throw StateError('cloud unavailable');
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
