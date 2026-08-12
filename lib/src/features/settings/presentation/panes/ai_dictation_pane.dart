import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiDictationSettingsPane extends ConsumerStatefulWidget {
  const AiDictationSettingsPane({
    super.key,
    required this.settings,
    required this.onChanged,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final AiDictationSettings settings;
  final ValueChanged<AiDictationSettings> onChanged;
  final Map<String, GlobalKey> groupKeys;

  @override
  ConsumerState<AiDictationSettingsPane> createState() =>
      _AiDictationSettingsPaneState();
}

class _AiDictationSettingsPaneState
    extends ConsumerState<AiDictationSettingsPane> {
  bool? _modelInstalled;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  Future<void> _refreshModelStatus() async {
    if (!mounted) return;
    final installed = await ref
        .read(aiDictationModelStoreProvider)
        .isInstalled(widget.settings.localModelId);
    if (mounted) {
      setState(() => _modelInstalled = installed);
    }
  }

  Future<void> _downloadModel() async {
    await ref
        .read(aiDictationModelStoreProvider)
        .download(id: widget.settings.localModelId);
    await _refreshModelStatus();
  }

  Future<void> _removeModel() async {
    await ref
        .read(aiDictationModelStoreProvider)
        .remove(widget.settings.localModelId);
    await _refreshModelStatus();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: widget.groupKeys['local'],
          child: AleraSettingsGroup(
            title: 'Local Whisper',
            description:
                'Transcribe recordings locally with the bundled Whisper runtime. Audio stays on this device.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Enable AI Dictation',
                description: 'Show microphone controls in supported composers.',
                value: settings.enabled,
                onChanged: (value) =>
                    widget.onChanged(settings.copyWith(enabled: value)),
              ),
              ListTile(
                title: const Text('Whisper Model'),
                subtitle: Text(
                  'Select the local model used before fallback providers.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: DropdownButton<String>(
                  value:
                      AiDictationModelStore.models.any(
                        (model) =>
                            model.id ==
                            AiDictationModelStore.modelForId(
                              settings.localModelId,
                            ),
                      )
                      ? AiDictationModelStore.modelForId(settings.localModelId)
                      : AiDictationModelStore.models.first.id,
                  items: <DropdownMenuItem<String>>[
                    for (final model in AiDictationModelStore.models)
                      DropdownMenuItem<String>(
                        value: model.id,
                        child: Text(model.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.onChanged(settings.copyWith(localModelId: value));
                    }
                  },
                ),
              ),
              SettingsTextRow(
                title: 'Language',
                description:
                    'Optional ISO language code. Leave blank to let Whisper detect it.',
                value: settings.language ?? '',
                hintText: 'en',
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(language: value.isEmpty ? null : value),
                ),
              ),
              SettingsButtonRow(
                title: 'Whisper Model',
                description: _modelInstalled == true
                    ? 'The offline model is installed and ready.'
                    : 'Download the selected offline model before using dictation.',
                buttonLabel: _modelInstalled == true
                    ? 'Remove Model'
                    : 'Download Model',
                onPressed: _modelInstalled == true
                    ? _removeModel
                    : _downloadModel,
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: widget.groupKeys['fallback'],
          child: AleraSettingsGroup(
            title: 'Fallback Providers',
            description:
                'Use the connected runtime first, then an OpenAI-compatible provider when local transcription is unavailable.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Host Whisper Fallback',
                description:
                    'Send recordings to the connected runtime for local Whisper transcription.',
                value: settings.hostFallbackEnabled,
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(hostFallbackEnabled: value),
                ),
              ),
              SettingsSwitchRow(
                title: 'OpenAI-Compatible Fallback',
                description:
                    'Use the configured speech-to-text endpoint after local and host fallback fail.',
                value: settings.providerFallbackEnabled,
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(providerFallbackEnabled: value),
                ),
              ),
              SettingsTextRow(
                title: 'Provider URL',
                description: 'Base URL such as https://api.openai.com.',
                value: settings.remoteBaseUrl ?? '',
                hintText: 'https://api.openai.com',
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(
                    remoteBaseUrl: value.trim().isEmpty ? null : value.trim(),
                  ),
                ),
              ),
              SettingsTextRow(
                title: 'Provider Model',
                description:
                    'Model sent in the multipart transcription request.',
                value: settings.remoteModel ?? '',
                hintText: 'gpt-4o-mini-transcribe',
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(
                    remoteModel: value.trim().isEmpty ? null : value.trim(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: widget.groupKeys['privacy'],
          child: AleraSettingsGroup(
            title: 'Privacy',
            description:
                'Remote providers are reserved for a future opt-in flow.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Local Only',
                description:
                    'Keep dictation on the device and disable remote fallback.',
                value:
                    settings.providerPolicy ==
                    AiDictationProviderPolicy.localOnly,
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(
                    providerPolicy: value
                        ? AiDictationProviderPolicy.localOnly
                        : AiDictationProviderPolicy.localPreferred,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
