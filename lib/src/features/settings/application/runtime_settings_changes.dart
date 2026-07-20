import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_settings_changes.g.dart';

@Riverpod(keepAlive: true)
Stream<void> runtimeSettingsChanges(Ref ref) async* {
  final client = ref.watch(runtimeHostClientProvider);
  await for (final event in client.runtimeEvents) {
    if (event.name == 'runtimeSettingsChanged') {
      yield null;
    }
  }
}
