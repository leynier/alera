import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';

class MemoryCloudAccountRepository implements CloudAccountRepository {
  MemoryCloudAccountRepository([this.sessions = const <CloudAccountSession>[]]);

  final List<CloudAccountSession> sessions;

  @override
  Future<String> getOrCreateInstallationId() async => 'cloud-installation-1';

  @override
  Future<List<CloudAccountSession>> loadSessions() async => sessions;

  @override
  Future<void> removeSession(String accountId) async {}

  @override
  Future<void> saveSession(CloudAccountSession session) async {}
}
