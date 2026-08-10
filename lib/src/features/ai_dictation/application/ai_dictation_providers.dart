import 'package:alera/src/features/ai_dictation/application/ai_dictation_service.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_target_registry.dart';
import 'package:alera/src/features/ai_dictation/infra/native_ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_dictation_providers.g.dart';

@Riverpod(keepAlive: true)
AiDictationTargetRegistry aiDictationTargetRegistry(Ref ref) {
  return AiDictationTargetRegistry();
}

@Riverpod(keepAlive: true)
AiDictationModelStore aiDictationModelStore(Ref ref) {
  final store = AiDictationModelStore();
  ref.onDispose(store.dispose);
  return store;
}

@Riverpod(keepAlive: true)
AiDictationService aiDictationService(Ref ref) {
  final service = AiDictationService(
    settings: () => ref.read(settingsControllerProvider).aiDictation,
    targets: ref.read(aiDictationTargetRegistryProvider),
    provider: NativeAiDictationProvider(),
    modelStore: ref.read(aiDictationModelStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}
