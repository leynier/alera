import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
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
