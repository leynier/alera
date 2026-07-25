import 'package:alera/src/features/mobile_devices/domain/mobile_access_status.dart';
import 'package:alera/src/features/mobile_devices/infra/runtime_mobile_access_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_access_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeMobileAccessRepository mobileAccessRepository(Ref ref) {
  return RuntimeMobileAccessRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
Stream<MobileAccessStatus> mobileAccessStatus(Ref ref) {
  return ref.watch(mobileAccessRepositoryProvider).watchStatus();
}
