import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/accounts/infra/local_cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_relay_identity_repository.dart';
import 'package:alera_mobile/src/features/accounts/infra/local_cloud_relay_identity_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cloud_account_providers.g.dart';

@Riverpod(keepAlive: true)
CloudAccountRepository cloudAccountRepository(Ref ref) {
  return LocalCloudAccountRepository();
}

@Riverpod(keepAlive: true)
CloudRelayIdentityRepository cloudRelayIdentityRepository(Ref ref) {
  return LocalCloudRelayIdentityRepository();
}

@Riverpod(keepAlive: true)
AleraCloudConfiguration aleraCloudConfiguration(Ref ref) {
  return AleraCloudConfiguration.fromEnvironment();
}

@Riverpod(keepAlive: true)
AleraCloudApi aleraCloudApi(Ref ref) {
  final client = HttpAleraCloudApi(
    configuration: ref.watch(aleraCloudConfigurationProvider),
  );
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
AleraRelayCloudApi aleraRelayCloudApi(Ref ref) {
  return ref.watch(aleraCloudApiProvider) as AleraRelayCloudApi;
}

@Riverpod(keepAlive: true)
AleraMobileAuthApi aleraMobileAuthApi(Ref ref) {
  return ref.watch(aleraCloudApiProvider) as AleraMobileAuthApi;
}
