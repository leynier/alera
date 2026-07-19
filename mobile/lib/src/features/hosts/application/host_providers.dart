import 'package:alera_mobile/src/features/hosts/application/host_repository.dart';
import 'package:alera_mobile/src/features/hosts/infra/local_host_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_providers.g.dart';

@Riverpod(keepAlive: true)
HostRepository hostRepository(Ref ref) {
  return LocalHostRepository();
}
