import 'package:alera/src/features/ai_dictation/application/ai_dictation_service.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_target_registry.dart';
import 'package:alera/src/features/ai_dictation/infra/native_ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_credential_store.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_speech_processor.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
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
AiDictationCredentialStore aiDictationCredentialStore(Ref ref) {
  return RuntimeAiDictationCredentialStore(ref.read(runtimeHostClientProvider));
}

@riverpod
Future<bool> remoteAiDictationSupported(Ref ref) async {
  final client = ref.read(runtimeHostClientProvider);
  return client.supportsRuntimeCapability(
    aleraRuntimeHostRemoteAiDictationCapability,
  );
}

@Riverpod(keepAlive: true)
AiDictationService aiDictationService(Ref ref) {
  final service = AiDictationService(
    settings: () => ref.read(settingsControllerProvider).aiDictation,
    targets: ref.read(aiDictationTargetRegistryProvider),
    provider: NativeAiDictationProvider(),
    remoteProvider: RuntimeAiDictationProvider(
      ref.read(runtimeHostClientProvider),
    ),
    modelStore: ref.read(aiDictationModelStoreProvider),
    speechProcessor: RuntimeAiDictationSpeechProcessor(
      ref.read(runtimeHostClientProvider),
    ),
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
}
