import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';

class MemoryCloudAccountRepository([
  final List<CloudAccountSession> sessions = const <CloudAccountSession>[],
]) implements CloudAccountRepository {
  @override
  Future<String> getOrCreateInstallationId() async => 'cloud-installation-1';

  @override
  Future<List<CloudAccountSession>> loadSessions() async => sessions;

  @override
  Future<void> removeSession(String accountId) async {}

  @override
  Future<void> saveSession(CloudAccountSession session) async {}
}
