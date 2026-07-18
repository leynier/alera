import 'package:alera_mobile/src/features/hosts/application/host_repository.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';

class MemoryHostRepository implements HostRepository {
  final Map<String, PairedHostProfile> _hosts = <String, PairedHostProfile>{};
  final Map<String, String> _secrets = <String, String>{};

  @override
  Future<List<PairedHostProfile>> loadHosts() async {
    return _hosts.values.toList(growable: false);
  }

  @override
  Future<void> savePairedHost(
    PairedHostProfile host,
    String deviceToken,
  ) async {
    _hosts[host.id] = host;
    _secrets[host.id] = deviceToken;
  }

  @override
  Future<void> removeHost(String hostId) async {
    _hosts.remove(hostId);
    _secrets.remove(hostId);
  }

  @override
  Future<String?> readDeviceToken(String hostId) async {
    return _secrets[hostId];
  }
}
