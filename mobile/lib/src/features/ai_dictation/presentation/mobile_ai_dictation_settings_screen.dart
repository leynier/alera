import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _onlineConsentVersion = 1;

class MobileAiDictationSettingsScreen extends ConsumerWidget {
  const MobileAiDictationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsValue = ref.watch(
      mobileAiDictationSettingsControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('AI Dictation')),
      body: settingsValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('AI Dictation settings could not be loaded: $error'),
        ),
        data: (settings) => _SettingsList(settings: settings),
      ),
    );
  }
}

class _SettingsList extends ConsumerWidget {
  const _SettingsList({required this.settings});

  final MobileAiDictationSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      mobileAiDictationSettingsControllerProvider.notifier,
    );
    final onDeviceAvailable =
        ref
            .watch(
              mobileAiDictationOnDeviceAvailableProvider(settings.language),
            )
            .value ??
        false;
    final engines = <MobileAiDictationEngine>[
      if (onDeviceAvailable) MobileAiDictationEngine.systemOnDevice,
      MobileAiDictationEngine.systemRecognition,
    ];
    final selectedEngine = engines.contains(settings.engine)
        ? settings.engine
        : null;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        SwitchListTile(
          value: settings.enabled,
          title: const Text('Enable AI Dictation'),
          subtitle: const Text('Add microphone controls to mobile composers.'),
          onChanged: (value) =>
              controller.save(settings.copyWith(enabled: value)),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Transcription', style: Theme.of(context).textTheme.titleMedium),
        DropdownButtonFormField<MobileAiDictationEngine>(
          key: ValueKey<String>(
            'dictation-engine-$onDeviceAvailable-${settings.engine.name}',
          ),
          initialValue: selectedEngine,
          decoration: const InputDecoration(labelText: 'Transcription Engine'),
          hint: const Text('Choose Recognition Mode'),
          items: <DropdownMenuItem<MobileAiDictationEngine>>[
            for (final engine in engines)
              DropdownMenuItem<MobileAiDictationEngine>(
                value: engine,
                child: Text(
                  engine == MobileAiDictationEngine.systemOnDevice
                      ? 'System On-Device'
                      : 'System Recognition',
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              controller.save(settings.copyWith(engine: value));
            }
          },
        ),
        if (selectedEngine == null)
          const Text(
            'On-device recognition is unavailable for this device or locale. Choose System Recognition to opt in to the disclosed online service.',
          ),
        TextFormField(
          initialValue: settings.language,
          decoration: const InputDecoration(
            labelText: 'Language Or Locale',
            hintText: 'en-US',
            helperText: 'Leave blank to use the device locale.',
          ),
          onFieldSubmitted: (value) => controller.save(
            settings.copyWith(
              language: value.trim().isEmpty ? null : value.trim(),
              clearLanguage: value.trim().isEmpty,
            ),
          ),
        ),
        if (settings.engine == MobileAiDictationEngine.systemRecognition)
          SwitchListTile(
            value:
                settings.systemRecognitionConsentVersion ==
                _onlineConsentVersion,
            title: const Text('Allow Online Speech Recognition'),
            subtitle: const Text(
              'The platform speech service may send microphone audio to Apple, Google, or the configured recognition provider.',
            ),
            onChanged: (value) => controller.save(
              settings.copyWith(
                systemRecognitionConsentVersion: value
                    ? _onlineConsentVersion
                    : null,
                clearConsent: !value,
              ),
            ),
          ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text(
          'Speech Processing',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        DropdownButtonFormField<MobileAiDictationRewriteMode>(
          initialValue: settings.rewriteMode,
          decoration: const InputDecoration(labelText: 'Automatic Processing'),
          items: const <DropdownMenuItem<MobileAiDictationRewriteMode>>[
            DropdownMenuItem(
              value: MobileAiDictationRewriteMode.off,
              child: Text('Off'),
            ),
            DropdownMenuItem(
              value: MobileAiDictationRewriteMode.cleanUp,
              child: Text('Clean Up'),
            ),
            DropdownMenuItem(
              value: MobileAiDictationRewriteMode.summarize,
              child: Text('Summarize'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              controller.save(settings.copyWith(rewriteMode: value));
            }
          },
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        const Text(
          'Speech processing sends only the completed transcript to the paired host. The host uses the agent and model configured for Speech Messages. Raw text is inserted if processing fails.',
        ),
      ],
    );
  }
}
