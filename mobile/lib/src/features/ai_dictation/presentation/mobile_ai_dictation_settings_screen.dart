import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_model_transfers.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_provider_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'mobile_ai_dictation_settings_models.dart';
part 'mobile_ai_dictation_settings_controls.dart';

const _onlineConsentVersion = 1;
const _remoteConsentVersion = 1;
const _remoteWhisperModels = <({String id, String label})>[
  (id: 'whisper-tiny', label: 'Whisper Tiny'),
  (id: 'whisper-base', label: 'Whisper Base'),
  (id: 'whisper-small', label: 'Whisper Small'),
  (id: 'whisper-large-v3-turbo-q5-0', label: 'Whisper Large V3 Turbo (Q5)'),
];

class MobileAiDictationSettingsScreen extends ConsumerWidget {
  const MobileAiDictationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsValue = ref.watch(
      mobileAiDictationSettingsControllerProvider,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('AI Dictation')),
      body: SafeArea(
        child: settingsValue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: AleraTokens.pagePadding,
              child: Text(
                'AI Dictation settings could not be loaded: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (settings) => _SettingsList(settings: settings),
        ),
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
    final engines = settings.location == MobileAiDictationLocation.pairedDevice
        ? const <MobileAiDictationEngine>[
            MobileAiDictationEngine.whisper,
            MobileAiDictationEngine.openAiCompatible,
            MobileAiDictationEngine.codexSubscription,
          ]
        : const <MobileAiDictationEngine>[
            MobileAiDictationEngine.whisper,
            MobileAiDictationEngine.openAiCompatible,
            MobileAiDictationEngine.systemOnDevice,
            MobileAiDictationEngine.systemRecognition,
          ];
    final selectedEngine = engines.contains(settings.engine)
        ? settings.engine
        : MobileAiDictationEngine.whisper;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        _EnableCard(
          enabled: settings.enabled,
          onChanged: (value) =>
              controller.save(settings.copyWith(enabled: value)),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        _SectionTitle(
          title: 'Transcription',
          description: 'Choose where speech is converted to text.',
        ),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Processing Location',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                SegmentedButton<MobileAiDictationLocation>(
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  segments: const <ButtonSegment<MobileAiDictationLocation>>[
                    ButtonSegment<MobileAiDictationLocation>(
                      value: MobileAiDictationLocation.thisDevice,
                      label: Text('This Device'),
                    ),
                    ButtonSegment<MobileAiDictationLocation>(
                      value: MobileAiDictationLocation.pairedDevice,
                      label: Text('Paired Device'),
                    ),
                  ],
                  selected: <MobileAiDictationLocation>{settings.location},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    final value = selection.first;
                    controller.save(
                      settings.copyWith(
                        location: value,
                        engine: _engineForLocation(value, settings.engine),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AleraTokens.spaceLg),
                AleraDropdownField<MobileAiDictationEngine>(
                  key: ValueKey<String>(
                    'dictation-engine-${settings.location.name}-${selectedEngine.name}',
                  ),
                  value: selectedEngine,
                  labelText: 'Transcription Engine',
                  entries: <AleraDropdownFieldEntry<MobileAiDictationEngine>>[
                    for (final engine in engines)
                      AleraDropdownFieldEntry<MobileAiDictationEngine>(
                        value: engine,
                        enabled:
                            engine != MobileAiDictationEngine.systemOnDevice ||
                            onDeviceAvailable,
                        label:
                            engine == MobileAiDictationEngine.systemOnDevice &&
                                !onDeviceAvailable
                            ? '${_engineLabel(engine)} (Unavailable)'
                            : _engineLabel(engine),
                      ),
                  ],
                  onChanged: (value) =>
                      controller.save(settings.copyWith(engine: value)),
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                _HelperText(
                  _engineDescription(settings.location, selectedEngine),
                ),
                const SizedBox(height: AleraTokens.spaceLg),
                _LanguageField(
                  language: settings.language,
                  onChanged: (value) => controller.save(
                    settings.copyWith(
                      language: value,
                      clearLanguage: value == null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (settings.requiresRemoteAudioConsent) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Card(
            child: SwitchListTile(
              value:
                  settings.remoteAudioConsentVersion == _remoteConsentVersion,
              title: const Text('Allow Remote Audio Processing'),
              subtitle: Text(
                settings.location == MobileAiDictationLocation.pairedDevice
                    ? 'Send recordings through the authenticated connection to the paired runtime.'
                    : 'Send recordings directly from this mobile app to the configured speech API.',
              ),
              onChanged: (value) => controller.save(
                settings.copyWith(
                  remoteAudioConsentVersion: value
                      ? _remoteConsentVersion
                      : null,
                  clearRemoteConsent: !value,
                ),
              ),
            ),
          ),
        ],
        if (settings.engine ==
            MobileAiDictationEngine.systemRecognition) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Card(
            child: SwitchListTile(
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
                  clearSystemConsent: !value,
                ),
              ),
            ),
          ),
        ],
        MobileAiDictationProviderSettings(
          settings: settings,
          onChanged: controller.save,
        ),
        if (selectedEngine == MobileAiDictationEngine.whisper) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceXl),
          _SectionTitle(
            title: settings.location == MobileAiDictationLocation.thisDevice
                ? 'On-Device Whisper Models'
                : 'Paired-Device Whisper Model',
            description:
                settings.location == MobileAiDictationLocation.thisDevice
                ? 'Install a multilingual model and select it for local transcription.'
                : 'Install the selected model in AI Dictation settings on the paired computer before using it.',
          ),
          if (settings.location == MobileAiDictationLocation.thisDevice)
            const _LocalModelList()
          else
            Card(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: AleraDropdownField<String>(
                  value: settings.remoteModelId,
                  labelText: 'Remote Model',
                  entries: <AleraDropdownFieldEntry<String>>[
                    for (final model in _remoteWhisperModels)
                      AleraDropdownFieldEntry<String>(
                        value: model.id,
                        label: model.label,
                      ),
                  ],
                  onChanged: (value) =>
                      controller.save(settings.copyWith(remoteModelId: value)),
                ),
              ),
            ),
        ],
        const SizedBox(height: AleraTokens.spaceXl),
        _SectionTitle(
          title: 'Speech Processing',
          description: 'Optionally improve the finished transcript with the agent configured for Speech Messages.',
        ),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Automatic Processing',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                SegmentedButton<MobileAiDictationRewriteMode>(
                  showSelectedIcon: false,
                  expandedInsets: EdgeInsets.zero,
                  segments: const <ButtonSegment<MobileAiDictationRewriteMode>>[
                    ButtonSegment<MobileAiDictationRewriteMode>(
                      value: MobileAiDictationRewriteMode.off,
                      label: Text('Off'),
                    ),
                    ButtonSegment<MobileAiDictationRewriteMode>(
                      value: MobileAiDictationRewriteMode.cleanUp,
                      label: Text('Clean Up'),
                    ),
                    ButtonSegment<MobileAiDictationRewriteMode>(
                      value: MobileAiDictationRewriteMode.summarize,
                      label: Text('Summarize'),
                    ),
                  ],
                  selected: <MobileAiDictationRewriteMode>{
                    settings.rewriteMode,
                  },
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    controller.save(
                      settings.copyWith(rewriteMode: selection.first),
                    );
                  },
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                const _HelperText(
                  'Speech processing sends only the completed transcript to the paired host. Raw text is inserted if processing fails.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _engineLabel(MobileAiDictationEngine engine) => switch (engine) {
  MobileAiDictationEngine.whisper => 'Whisper',
  MobileAiDictationEngine.openAiCompatible => 'OpenAI-Compatible API',
  MobileAiDictationEngine.codexSubscription =>
    'Codex Subscription (Experimental)',
  MobileAiDictationEngine.systemOnDevice => 'System On-Device',
  MobileAiDictationEngine.systemRecognition => 'System Recognition',
};

String _engineDescription(
  MobileAiDictationLocation location,
  MobileAiDictationEngine engine,
) => switch ((location, engine)) {
  (MobileAiDictationLocation.thisDevice, MobileAiDictationEngine.whisper) => 'Record, review, and transcribe with a Whisper model stored on this device.',
  (MobileAiDictationLocation.pairedDevice, MobileAiDictationEngine.whisper) => 'Record and review here, then transcribe with Whisper on the paired device.',
  (
    MobileAiDictationLocation.thisDevice,
    MobileAiDictationEngine.openAiCompatible,
  ) =>
    'Send the reviewed recording directly from this mobile app to the configured API.',
  (
    MobileAiDictationLocation.pairedDevice,
    MobileAiDictationEngine.openAiCompatible,
  ) =>
    'Send the reviewed recording to the paired runtime, which calls the configured API.',
  (_, MobileAiDictationEngine.codexSubscription) => 'Transcribe through the authenticated experimental Codex app-server in the paired runtime.',
  (_, MobileAiDictationEngine.systemOnDevice) =>
    'Use the platform recognizer only when it guarantees offline processing.',
  (_, MobileAiDictationEngine.systemRecognition) =>
    'Use the platform speech service, which may process audio online.',
};

MobileAiDictationEngine _engineForLocation(
  MobileAiDictationLocation location,
  MobileAiDictationEngine current,
) {
  if (location == MobileAiDictationLocation.thisDevice &&
      current == MobileAiDictationEngine.codexSubscription) {
    return MobileAiDictationEngine.whisper;
  }
  if (location == MobileAiDictationLocation.pairedDevice &&
      (current == MobileAiDictationEngine.systemOnDevice ||
          current == MobileAiDictationEngine.systemRecognition)) {
    return MobileAiDictationEngine.whisper;
  }
  return current;
}
