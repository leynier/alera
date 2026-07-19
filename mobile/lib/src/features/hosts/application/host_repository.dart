import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';

abstract interface class HostRepository {
  Future<List<PairedHostProfile>> loadHosts();
  Future<void> savePairedHost(PairedHostProfile host, String deviceToken);
  Future<void> removeHost(String hostId);
  Future<String?> readDeviceToken(String hostId);

  /// Stores a local display alias for a paired host. A null [alias] clears
  /// the override so the advertised host name shows again. The device token
  /// is untouched.
  Future<void> updateHostAlias(String hostId, String? alias);
}
