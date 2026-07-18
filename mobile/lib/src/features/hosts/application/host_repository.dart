import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';

abstract interface class HostRepository {
  Future<List<PairedHostProfile>> loadHosts();
  Future<void> savePairedHost(PairedHostProfile host, String deviceToken);
  Future<void> removeHost(String hostId);
  Future<String?> readDeviceToken(String hostId);
}
