import 'dart:convert';

import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'mobile_ai_dictation_settings_controller.g.dart';

const _settingsKey = 'aiDictation.settings';

@Riverpod(keepAlive: true)
class MobileAiDictationSettingsController
    extends _$MobileAiDictationSettingsController {
  @override
  Future<MobileAiDictationSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return const MobileAiDictationSettings();
    try {
      return MobileAiDictationSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return const MobileAiDictationSettings();
    }
  }

  Future<void> save(MobileAiDictationSettings settings) async {
    state = AsyncData<MobileAiDictationSettings>(settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}
