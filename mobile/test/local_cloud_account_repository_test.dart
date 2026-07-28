import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/infra/local_cloud_account_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Secure Repository Stores Multiple Sessions And Stable Device Id',
    () async {
      final store = _MemorySecureValueStore();
      final repository = LocalCloudAccountRepository(store: store);

      await repository.saveSession(_session('account-1'));
      await repository.saveSession(_session('account-2'));
      final firstId = await repository.getOrCreateInstallationId();
      final secondId = await repository.getOrCreateInstallationId();

      expect(
        (await repository.loadSessions()).map((item) => item.account.id),
        containsAll(<String>['account-1', 'account-2']),
      );
      expect(firstId, secondId);
      expect(firstId, isNotEmpty);

      await repository.removeSession('account-1');
      expect((await repository.loadSessions()).single.account.id, 'account-2');
    },
  );

  test(
    'Secure Repository Replaces One Account Without Losing Others',
    () async {
      final repository = LocalCloudAccountRepository(
        store: _MemorySecureValueStore(),
      );
      await repository.saveSession(_session('account-1'));
      await repository.saveSession(_session('account-2'));
      await repository.saveSession(
        _session('account-1').copyWith(
          account: const CloudAccountProfile(
            id: 'account-1',
            email: 'new@example.com',
          ),
        ),
      );

      final sessions = await repository.loadSessions();
      expect(sessions.length, 2);
      expect(
        sessions
            .singleWhere((item) => item.account.id == 'account-1')
            .account
            .email,
        'new@example.com',
      );
    },
  );
}

CloudAccountSession _session(String accountId) {
  return CloudAccountSession(
    account: CloudAccountProfile(
      id: accountId,
      email: '$accountId@example.com',
    ),
    accessToken: 'access-$accountId',
    refreshToken: 'refresh-$accountId',
    accessTokenExpiresAt: DateTime.utc(2026, 8),
  );
}

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
