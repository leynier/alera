import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_model_transfers.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        ? const <MobileAiDictationEngine>[MobileAiDictationEngine.whisper]
        : MobileAiDictationEngine.values;
    final selectedEngine = engines.contains(settings.engine)
        ? settings.engine
        : MobileAiDictationEngine.whisper;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Card(
          child: SwitchListTile(
            value: settings.enabled,
            title: const Text('Enable AI Dictation'),
            subtitle: const Text(
              'Add microphone controls to mobile composers.',
            ),
            onChanged: (value) =>
                controller.save(settings.copyWith(enabled: value)),
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        _SectionHeader(title: 'Transcription'),
        DropdownButtonFormField<MobileAiDictationLocation>(
          initialValue: settings.location,
          decoration: const InputDecoration(labelText: 'Processing Location'),
          items: const <DropdownMenuItem<MobileAiDictationLocation>>[
            DropdownMenuItem(
              value: MobileAiDictationLocation.thisDevice,
              child: Text('This Device'),
            ),
            DropdownMenuItem(
              value: MobileAiDictationLocation.pairedDevice,
              child: Text('Paired Device'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            controller.save(
              settings.copyWith(
                location: value,
                engine: value == MobileAiDictationLocation.pairedDevice
                    ? MobileAiDictationEngine.whisper
                    : settings.engine,
              ),
            );
          },
        ),
        DropdownButtonFormField<MobileAiDictationEngine>(
          key: ValueKey<String>(
            'dictation-engine-${settings.location.name}-${selectedEngine.name}',
          ),
          initialValue: selectedEngine,
          decoration: const InputDecoration(labelText: 'Transcription Engine'),
          items: <DropdownMenuItem<MobileAiDictationEngine>>[
            for (final engine in engines)
              DropdownMenuItem<MobileAiDictationEngine>(
                value: engine,
                enabled:
                    engine != MobileAiDictationEngine.systemOnDevice ||
                    onDeviceAvailable,
                child: Text(
                  engine == MobileAiDictationEngine.systemOnDevice &&
                          !onDeviceAvailable
                      ? '${_engineLabel(engine)} (Unavailable)'
                      : _engineLabel(engine),
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              controller.save(settings.copyWith(engine: value));
            }
          },
        ),
        Text(_engineDescription(settings.location, selectedEngine)),
        if (settings.location == MobileAiDictationLocation.pairedDevice)
          SwitchListTile(
            value: settings.remoteAudioConsentVersion == _remoteConsentVersion,
            title: const Text('Allow Paired-Device Audio Processing'),
            subtitle: const Text(
              'Send recordings through the authenticated connection to the paired runtime. Recordings are deleted after processing.',
            ),
            onChanged: (value) => controller.save(
              settings.copyWith(
                remoteAudioConsentVersion: value ? _remoteConsentVersion : null,
                clearRemoteConsent: !value,
              ),
            ),
          ),
        const SizedBox(height: AleraTokens.spaceLg),
        TextFormField(
          initialValue: settings.language,
          decoration: const InputDecoration(
            labelText: 'Language Or Locale',
            hintText: 'en-US',
            helperText: 'Leave blank to detect the language automatically.',
          ),
          onFieldSubmitted: (value) => controller.save(
            settings.copyWith(
              language: value.trim().isEmpty ? null : value.trim(),
              clearLanguage: value.trim().isEmpty,
            ),
          ),
        ),
        if (settings.engine == MobileAiDictationEngine.systemRecognition)
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
        if (selectedEngine == MobileAiDictationEngine.whisper) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceXl),
          Text(
            settings.location == MobileAiDictationLocation.thisDevice
                ? 'On-Device Whisper Models'
                : 'Paired-Device Whisper Model',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (settings.location == MobileAiDictationLocation.thisDevice)
            const _LocalModelList()
          else
            DropdownButtonFormField<String>(
              initialValue: settings.remoteModelId,
              decoration: const InputDecoration(labelText: 'Remote Model'),
              items: <DropdownMenuItem<String>>[
                for (final model in _remoteWhisperModels)
                  DropdownMenuItem(value: model.id, child: Text(model.label)),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.save(settings.copyWith(remoteModelId: value));
                }
              },
            ),
          if (settings.location == MobileAiDictationLocation.pairedDevice)
            const Text(
              'Install the selected model in AI Dictation settings on the paired computer before using it.',
            ),
        ],
        const SizedBox(height: AleraTokens.spaceXl),
        const SizedBox(height: AleraTokens.spaceXl),
        _SectionHeader(title: 'Speech Processing'),
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
        const _HelperText(
          'Speech processing sends only the completed transcript to the '
          'paired host. The host uses the agent and model configured for '
          'Speech Messages. Raw text is inserted if processing fails.',
        ),
      ],
    );
  }
}

class _LocalModelList extends ConsumerWidget {
  const _LocalModelList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref
        .watch(mobileAiDictationSettingsControllerProvider)
        .value;
    final transfers = ref.watch(mobileAiDictationModelTransfersProvider);
    final transferController = ref.read(
      mobileAiDictationModelTransfersProvider.notifier,
    );
    if (settings == null) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        for (final model in MobileAiDictationModelStore.models)
          _ModelTile(
            model: model,
            transfer: transfers.forModel(model.id),
            selected: settings.localModelId == model.id,
            busy: transfers.activeModelId != null,
            onDownload: () => transferController.download(model.id),
            onCancel: () => transferController.cancel(model.id),
            onSelect: () => ref
                .read(mobileAiDictationSettingsControllerProvider.notifier)
                .save(settings.copyWith(localModelId: model.id)),
            onRemove: () => transferController.remove(
              model.id,
              selectedModelId: settings.localModelId,
            ),
          ),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.transfer,
    required this.selected,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onSelect,
    required this.onRemove,
  });

  final MobileAiDictationModel model;
  final MobileAiModelTransfer transfer;
  final bool selected;
  final bool busy;
  final Future<void> Function() onDownload;
  final Future<void> Function() onCancel;
  final Future<void> Function() onSelect;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final downloading =
        transfer.status == MobileAiModelTransferStatus.downloading ||
        transfer.status == MobileAiModelTransferStatus.verifying;
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(model.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AleraTokens.space4),
            Text(_modelStatus(model, transfer, selected)),
            if (downloading) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              LinearProgressIndicator(
                value: transfer.status == MobileAiModelTransferStatus.verifying
                    ? null
                    : transfer.progress,
              ),
            ],
            const SizedBox(height: AleraTokens.space8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AleraTokens.space8,
              children: <Widget>[
                if (downloading)
                  OutlinedButton(
                    onPressed: () => unawaited(onCancel()),
                    child: const Text('Cancel Download'),
                  )
                else if (!transfer.installed)
                  FilledButton(
                    onPressed: busy ? null : () => unawaited(onDownload()),
                    child: Text(
                      transfer.status == MobileAiModelTransferStatus.resumable
                          ? 'Resume'
                          : 'Download',
                    ),
                  )
                else ...<Widget>[
                  OutlinedButton(
                    onPressed: selected ? null : () => unawaited(onRemove()),
                    child: const Text('Remove Model'),
                  ),
                  FilledButton(
                    onPressed: selected ? null : () => unawaited(onSelect()),
                    child: Text(selected ? 'Selected' : 'Use Model'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

String _engineLabel(MobileAiDictationEngine engine) => switch (engine) {
  MobileAiDictationEngine.whisper => 'Whisper',
  MobileAiDictationEngine.systemOnDevice => 'System On-Device',
  MobileAiDictationEngine.systemRecognition => 'System Recognition',
};

String _engineDescription(
  MobileAiDictationLocation location,
  MobileAiDictationEngine engine,
) => switch ((location, engine)) {
  (MobileAiDictationLocation.thisDevice, MobileAiDictationEngine.whisper) =>
    'Record, review, and transcribe with a Whisper model stored on this device.',
  (MobileAiDictationLocation.pairedDevice, MobileAiDictationEngine.whisper) =>
    'Record and review here, then transcribe with Whisper on the paired device.',
  (_, MobileAiDictationEngine.systemOnDevice) =>
    'Use the platform recognizer only when it guarantees offline processing.',
  (_, MobileAiDictationEngine.systemRecognition) =>
    'Use the platform speech service, which may process audio online.',
};

String _modelStatus(
  MobileAiDictationModel model,
  MobileAiModelTransfer transfer,
  bool selected,
) => switch (transfer.status) {
  MobileAiModelTransferStatus.downloading =>
    '${_formatBytes(transfer.receivedBytes)} of ${_formatBytes(transfer.totalBytes)}',
  MobileAiModelTransferStatus.verifying => 'Verifying downloaded model...',
  MobileAiModelTransferStatus.resumable =>
    'Download interrupted at ${_formatBytes(transfer.receivedBytes)}.',
  MobileAiModelTransferStatus.failed =>
    transfer.message ?? 'The model download failed.',
  MobileAiModelTransferStatus.idle when transfer.installed =>
    selected ? 'Installed and selected.' : 'Installed on this device.',
  MobileAiModelTransferStatus.idle =>
    '${model.description} Download size ${_formatBytes(model.sizeBytes)}.',
};

String _formatBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

class _HelperText extends StatelessWidget {
  const _HelperText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}
