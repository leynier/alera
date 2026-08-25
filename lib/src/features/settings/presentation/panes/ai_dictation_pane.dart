import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_model_transfers.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_remote_settings.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_settings_test.dart';
import 'package:alera/src/features/ai_dictation/infra/system_ai_dictation_recognizer.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _systemRecognitionConsentVersion = 1;

class AiDictationSettingsPane extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(aiDictationModelTransfersProvider);
    final transferController = ref.read(
      aiDictationModelTransfersProvider.notifier,
    );
    final onDeviceAvailable =
        ref
            .watch(aiDictationOnDeviceAvailableProvider(settings.language))
            .value ??
        false;
    final engines = _availableEngines(onDeviceAvailable);
    final selectedEngine = engines.contains(settings.transcriptionEngine)
        ? settings.transcriptionEngine
        : AiDictationTranscriptionEngine.localWhisper;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: groupKeys['transcription'],
            child: AleraSettingsGroup(
              title: 'Transcription',
              description:
                  'Choose where speech is converted to text on this device.',
              children: <Widget>[
                SettingsSwitchRow(
                  title: 'Enable AI Dictation',
                  description:
                      'Show microphone controls in supported composers.',
                  value: settings.enabled,
                  onChanged: (value) =>
                      onChanged(settings.copyWith(enabled: value)),
                ),
                AleraSettingRow(
                  title: 'Transcription Engine',
                  description: _engineDescription(selectedEngine),
                  child: AleraDropdownField<AiDictationTranscriptionEngine>(
                    value: selectedEngine,
                    entries:
                        <
                          AleraDropdownFieldEntry<
                            AiDictationTranscriptionEngine
                          >
                        >[
                          for (final engine in engines)
                            AleraDropdownFieldEntry<
                              AiDictationTranscriptionEngine
                            >(value: engine, label: _engineLabel(engine)),
                        ],
                    onChanged: (value) => onChanged(
                      settings.copyWith(transcriptionEngine: value),
                    ),
                  ),
                ),
                SettingsTextRow(
                  title: 'Language',
                  description:
                      'Optional locale or language code. Leave blank for automatic detection.',
                  value: settings.language ?? '',
                  hintText: 'en-US',
                  onChanged: (value) => onChanged(
                    settings.copyWith(language: value.isEmpty ? null : value),
                  ),
                ),
                if (selectedEngine ==
                    AiDictationTranscriptionEngine.systemRecognition)
                  SettingsSwitchRow(
                    title: 'Allow Online Speech Recognition',
                    description: Platform.isWindows
                        ? 'Windows may send microphone audio to Microsoft to create the transcription.'
                        : 'The system recognizer may send microphone audio to its online speech service.',
                    value:
                        settings.systemRecognitionConsentVersion ==
                        _systemRecognitionConsentVersion,
                    onChanged: (value) => onChanged(
                      settings.copyWith(
                        systemRecognitionConsentVersion: value
                            ? _systemRecognitionConsentVersion
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space16),
          AiDictationRemoteSettings(
            settings: settings,
            onChanged: onChanged,
            groupKey: groupKeys['remote'],
          ),
          const SizedBox(height: AleraTokens.space16),
          KeyedSubtree(
            key: groupKeys['models'],
            child: AleraSettingsGroup(
              title: 'Local Whisper Models',
              description:
                  'Install multiple multilingual models and select one for local transcription.',
              children: <Widget>[
                for (final model in AiDictationModelStore.models)
                  _WhisperModelRow(
                    model: model,
                    transfer: transfers.forModel(model.id),
                    selected:
                        AiDictationModelStore.modelForId(
                          settings.localModelId,
                        ) ==
                        model.id,
                    anotherDownloadActive:
                        transfers.activeModelId != null &&
                        transfers.activeModelId != model.id,
                    onDownload: () => transferController.download(model.id),
                    onCancel: () => transferController.cancel(model.id),
                    onSelect: () =>
                        onChanged(settings.copyWith(localModelId: model.id)),
                    onRemove: () => transferController.remove(
                      model.id,
                      selectedModelId: settings.localModelId,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space16),
          KeyedSubtree(
            key: groupKeys['processing'],
            child: AleraSettingsGroup(
              title: 'Speech Processing',
              description:
                  'Optionally improve the transcript with the agent subscription configured for Speech Messages in AI Text settings.',
              children: <Widget>[
                AleraSettingRow(
                  title: 'Automatic Processing',
                  description:
                      'Raw text is always used if the selected agent is unavailable or fails.',
                  child: AleraDropdownField<AiDictationRewriteMode>(
                    value: settings.rewriteMode,
                    entries:
                        const <AleraDropdownFieldEntry<AiDictationRewriteMode>>[
                          AleraDropdownFieldEntry<AiDictationRewriteMode>(
                            value: AiDictationRewriteMode.off,
                            label: 'Off',
                          ),
                          AleraDropdownFieldEntry<AiDictationRewriteMode>(
                            value: AiDictationRewriteMode.cleanUp,
                            label: 'Clean Up',
                          ),
                          AleraDropdownFieldEntry<AiDictationRewriteMode>(
                            value: AiDictationRewriteMode.summarize,
                            label: 'Summarize',
                          ),
                        ],
                    onChanged: (value) =>
                        onChanged(settings.copyWith(rewriteMode: value)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space16),
          AiDictationSettingsTest(
            settings: settings,
            groupKey: groupKeys['test'],
          ),
        ],
      ),
    );
  }
}

class _WhisperModelRow extends StatelessWidget {
  const _WhisperModelRow({
    required this.model,
    required this.transfer,
    required this.selected,
    required this.anotherDownloadActive,
    required this.onDownload,
    required this.onCancel,
    required this.onSelect,
    required this.onRemove,
  });

  final AiDictationModel model;
  final AiDictationModelTransfer transfer;
  final bool selected;
  final bool anotherDownloadActive;
  final Future<void> Function() onDownload;
  final Future<void> Function() onCancel;
  final VoidCallback onSelect;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final busy =
        transfer.status == AiDictationModelTransferStatus.downloading ||
        transfer.status == AiDictationModelTransferStatus.verifying;
    final statusText = switch (transfer.status) {
      AiDictationModelTransferStatus.queued =>
        'Queued. This download starts when the active transfer finishes.',
      AiDictationModelTransferStatus.downloading =>
        '${_formatBytes(transfer.receivedBytes)} of ${_formatBytes(transfer.totalBytes)}',
      AiDictationModelTransferStatus.verifying =>
        'Verifying downloaded model...',
      AiDictationModelTransferStatus.resumable =>
        'Download interrupted at ${_formatBytes(transfer.receivedBytes)}. Resume when ready.',
      AiDictationModelTransferStatus.failed =>
        transfer.message ?? 'The model download failed.',
      AiDictationModelTransferStatus.idle when transfer.installed =>
        selected ? 'Installed and selected.' : 'Installed on this device.',
      AiDictationModelTransferStatus.idle =>
        '${model.description} Download size ${_formatBytes(model.sizeBytes)}.',
    };
    return AleraSettingRow(
      title: model.label,
      description: statusText,
      controlWidth: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (busy) ...<Widget>[
            LinearProgressIndicator(
              value: transfer.status == AiDictationModelTransferStatus.verifying
                  ? null
                  : transfer.progress,
            ),
            const SizedBox(height: AleraTokens.space8),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              if (busy ||
                  transfer.status == AiDictationModelTransferStatus.queued)
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel Download'),
                )
              else if (!transfer.installed)
                FilledButton(
                  onPressed: onDownload,
                  child: Text(
                    anotherDownloadActive
                        ? 'Queue Download'
                        : transfer.status ==
                              AiDictationModelTransferStatus.resumable
                        ? 'Resume'
                        : 'Download',
                  ),
                )
              else ...<Widget>[
                OutlinedButton(
                  onPressed: selected ? null : onRemove,
                  child: const Text('Remove Model'),
                ),
                FilledButton(
                  onPressed: selected ? null : onSelect,
                  child: Text(selected ? 'Selected' : 'Use Model'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

List<AiDictationTranscriptionEngine> _availableEngines(bool onDeviceAvailable) {
  if (Platform.isMacOS && onDeviceAvailable) {
    return const <AiDictationTranscriptionEngine>[
      AiDictationTranscriptionEngine.localWhisper,
      AiDictationTranscriptionEngine.codexSubscription,
      AiDictationTranscriptionEngine.openAiCompatible,
      AiDictationTranscriptionEngine.systemOnDevice,
    ];
  }
  if (Platform.isWindows) {
    return const <AiDictationTranscriptionEngine>[
      AiDictationTranscriptionEngine.localWhisper,
      AiDictationTranscriptionEngine.codexSubscription,
      AiDictationTranscriptionEngine.openAiCompatible,
      AiDictationTranscriptionEngine.systemRecognition,
    ];
  }
  return const <AiDictationTranscriptionEngine>[
    AiDictationTranscriptionEngine.localWhisper,
    AiDictationTranscriptionEngine.codexSubscription,
    AiDictationTranscriptionEngine.openAiCompatible,
  ];
}

String _engineLabel(AiDictationTranscriptionEngine engine) => switch (engine) {
  AiDictationTranscriptionEngine.localWhisper => 'Local Whisper',
  AiDictationTranscriptionEngine.codexSubscription =>
    'Codex Subscription (Experimental)',
  AiDictationTranscriptionEngine.openAiCompatible => 'OpenAI-Compatible API',
  AiDictationTranscriptionEngine.systemOnDevice => 'System On-Device',
  AiDictationTranscriptionEngine.systemRecognition => 'System Recognition',
};

String _engineDescription(
  AiDictationTranscriptionEngine engine,
) => switch (engine) {
  AiDictationTranscriptionEngine.localWhisper =>
    'Record locally and transcribe with the selected Whisper model.',
  AiDictationTranscriptionEngine.codexSubscription =>
    'Use the experimental Codex app-server realtime API with your Codex subscription.',
  AiDictationTranscriptionEngine.openAiCompatible =>
    'Send recordings to an OpenAI-compatible audio transcription endpoint.',
  AiDictationTranscriptionEngine.systemOnDevice =>
    'Use the platform recognizer only when it guarantees offline processing.',
  AiDictationTranscriptionEngine.systemRecognition =>
    'Use the platform speech service, which may process audio online.',
};

String _formatBytes(int bytes) {
  const mib = 1024 * 1024;
  if (bytes < mib) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / mib).toStringAsFixed(1)} MiB';
}
