import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

Future<MobileRuntimeClient> watchHostConnection(Ref ref, String hostId) {
  final provider = hostConnectionControllerProvider(hostId);
  ref.listen(provider, (previous, next) {
    if (previous != null && (previous.hasValue || previous.hasError)) {
      ref.invalidateSelf();
    }
  });
  final state = ref.read(provider);
  final client = state.value;
  if (client != null &&
      !state.isLoading &&
      !state.hasError &&
      client.isConnectionUsable) {
    return Future<MobileRuntimeClient>.value(client);
  }
  if (state.isLoading && !state.hasValue && !state.hasError) {
    return ref.read(provider.future);
  }
  if (state.hasError && !state.isLoading) {
    return Future<MobileRuntimeClient>.error(
      state.error!,
      state.stackTrace ?? StackTrace.current,
    );
  }
  return ref.read(provider.notifier).requireUsableClient();
}
