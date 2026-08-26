import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_model_transfers.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_provider_credentials.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_credential_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ai_dictation_settings.dart';

void main() {
  testWidgets('AI Dictation settings groups transcription and processing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _settingsApp(
        const MobileAiDictationSettings(enabled: true, language: 'en-US'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable AI Dictation'), findsOneWidget);
    expect(
      find.text(
        'Add microphone controls to composers and New Workspace From Prompt.',
      ),
      findsOneWidget,
    );
    expect(find.text('Transcription'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('Paired Device'), findsOneWidget);
    expect(find.text('Transcription Engine'), findsOneWidget);
    expect(find.text('Language Or Locale'), findsOneWidget);
    expect(find.text('Speech Processing'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Clean Up'), findsOneWidget);
    expect(find.text('Summarize'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('paired-device transcription reveals remote consent and model', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _settingsApp(const MobileAiDictationSettings(enabled: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paired Device'));
    await tester.pumpAndSettle();

    expect(find.text('Allow Remote Audio Processing'), findsOneWidget);
    expect(
      find.text('Paired-Device Whisper Model', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Remote Model', skipOffstage: false), findsOneWidget);
    expect(find.text('Whisper'), findsOneWidget);
  });

  testWidgets('enabling the switch persists through the settings controller', (
    tester,
  ) async {
    final controller = FakeMobileAiDictationSettingsController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileAiDictationSettingsControllerProvider.overrideWith(
            () => controller,
          ),
          mobileAiDictationOnDeviceAvailableProvider.overrideWith(
            (ref, localeId) async => true,
          ),
          mobileAiDictationModelTransfersProvider.overrideWith(
            FakeMobileAiDictationModelTransfers.new,
          ),
        ],
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: const MobileAiDictationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('direct OpenAI settings expose mobile token configuration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _settingsApp(
        const MobileAiDictationSettings(
          enabled: true,
          engine: MobileAiDictationEngine.openAiCompatible,
          remoteAudioConsentVersion: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remote Provider'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('API Token'), findsOneWidget);
    expect(
      find.text('A token is stored securely on this mobile device.'),
      findsNothing,
    );
  });

  testWidgets('paired OpenAI uses runtime token configuration', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _settingsApp(
        const MobileAiDictationSettings(
          enabled: true,
          location: MobileAiDictationLocation.pairedDevice,
          engine: MobileAiDictationEngine.openAiCompatible,
          remoteAudioConsentVersion: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The runtime uses the API token configured in desktop AI Dictation settings.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('mobile-ai-dictation-api-token')),
      findsNothing,
    );
  });

  testWidgets('paired Codex exposes runtime realtime configuration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _settingsApp(
        const MobileAiDictationSettings(
          enabled: true,
          location: MobileAiDictationLocation.pairedDevice,
          engine: MobileAiDictationEngine.codexSubscription,
          remoteAudioConsentVersion: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Realtime Model'), findsOneWidget);
    expect(find.text('Subscription default'), findsOneWidget);
    expect(find.text('API Token'), findsNothing);
  });

  testWidgets('direct OpenAI mobile settings golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _settingsApp(
        const MobileAiDictationSettings(
          enabled: true,
          engine: MobileAiDictationEngine.openAiCompatible,
          remoteAudioConsentVersion: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remote Provider'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MobileAiDictationSettingsScreen),
      matchesGoldenFile('goldens/ai_dictation_openai_direct.png'),
    );
  });
}

Widget _settingsApp(MobileAiDictationSettings settings) {
  return ProviderScope(
    overrides: [
      mobileAiDictationSettingsControllerProvider.overrideWith(
        () => FakeMobileAiDictationSettingsController(settings),
      ),
      mobileAiDictationOnDeviceAvailableProvider.overrideWith(
        (ref, localeId) async => true,
      ),
      mobileAiDictationModelTransfersProvider.overrideWith(
        FakeMobileAiDictationModelTransfers.new,
      ),
      mobileAiDictationCredentialStoreProvider.overrideWithValue(
        MobileAiDictationCredentialStore(store: _MemorySecureStore()),
      ),
    ],
    child: MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      home: const MobileAiDictationSettingsScreen(),
    ),
  );
}

class _MemorySecureStore implements MobileAiDictationSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
