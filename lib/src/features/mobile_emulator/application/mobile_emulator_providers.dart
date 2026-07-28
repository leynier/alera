import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_lease_coordinator.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_emulator_providers.g.dart';

@Riverpod(keepAlive: true)
MobileEmulatorService mobileEmulatorService(Ref ref) {
  final service = MobileEmulatorService(ref.watch(runtimeHostClientProvider));
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
MobileEmulatorLeaseCoordinator mobileEmulatorLeaseCoordinator(Ref ref) {
  final coordinator = MobileEmulatorLeaseCoordinator(
    ref.watch(mobileEmulatorServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
}
