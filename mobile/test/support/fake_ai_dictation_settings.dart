import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_model_transfers.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeMobileAiDictationSettingsController
    extends MobileAiDictationSettingsController {
  FakeMobileAiDictationSettingsController([
    this.initial = const MobileAiDictationSettings(),
  ]);

  final MobileAiDictationSettings initial;

  @override
  Future<MobileAiDictationSettings> build() async => initial;

  @override
  Future<void> save(MobileAiDictationSettings settings) async {
    state = AsyncData<MobileAiDictationSettings>(settings);
  }
}

class FakeMobileAiDictationModelTransfers
    extends MobileAiDictationModelTransfers {
  @override
  MobileAiModelTransfersState build() {
    return MobileAiModelTransfersState(<String, MobileAiModelTransfer>{
      for (final model in MobileAiDictationModelStore.models)
        model.id: MobileAiModelTransfer(
          installed: model.id == 'whisper-base',
          receivedBytes: model.id == 'whisper-base' ? model.sizeBytes : 0,
          totalBytes: model.sizeBytes,
        ),
    });
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> download(String id) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> remove(String id, {required String selectedModelId}) async {}
}
