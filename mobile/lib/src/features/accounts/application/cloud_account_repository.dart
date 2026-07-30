import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';

abstract interface class CloudAccountRepository {
  Future<List<CloudAccountSession>> loadSessions();
  Future<void> saveSession(CloudAccountSession session);
  Future<void> removeSession(String accountId);
  Future<String> getOrCreateInstallationId();
}
