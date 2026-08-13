import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MobileAiDictationSettingsScreen extends StatefulWidget {
  const MobileAiDictationSettingsScreen({super.key, this.modelStore});

  final MobileAiDictationModels? modelStore;

  @override
  State<MobileAiDictationSettingsScreen> createState() =>
      _MobileAiDictationSettingsScreenState();
}

class _MobileAiDictationSettingsScreenState
    extends State<MobileAiDictationSettingsScreen> {
  MobileAiDictationSettings _settings = const MobileAiDictationSettings();
  late final MobileAiDictationModels _modelStore;
  bool _modelInstalled = false;
  bool _modelDownloading = false;
  String? _modelDownloadError;
  final _url = TextEditingController();
  final _model = TextEditingController();
  final _logger = Logger('MobileAiDictationSettings');

  @override
  void initState() {
    super.initState();
    _modelStore = widget.modelStore ?? MobileAiDictationModelStore();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _modelStore.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('aiDictation.settings');
    final installed = await _modelStore.isInstalled();
    if (!mounted) return;
    final next = raw == null
        ? const MobileAiDictationSettings()
        : MobileAiDictationSettings.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
    setState(() {
      _settings = next;
      _modelInstalled = installed;
      _url.text = next.providerBaseUrl;
      _model.text = next.providerModel;
    });
  }

  Future<void> _downloadModel() async {
    if (_modelDownloading) return;
    setState(() {
      _modelDownloading = true;
      _modelDownloadError = null;
    });
    try {
      await _modelStore.download();
    } on MobileAiModelDownloadCancelled {
      return;
    } on Object catch (error, stackTrace) {
      _logger.warning('Whisper model download failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _modelDownloading = false;
        _modelDownloadError = error is MobileAiModelDownloadException
            ? MobileAiModelDownloadException.message
            : 'The model could not be downloaded. Retry in a moment.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _modelDownloading = false;
      _modelInstalled = true;
    });
  }

  Future<void> _save(MobileAiDictationSettings next) async {
    setState(() => _settings = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiDictation.settings', jsonEncode(next.toJson()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Dictation')),
    body: ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        SwitchListTile(
          value: _settings.enabled,
          title: const Text('Enable AI Dictation'),
          subtitle: const Text('Add microphone controls to mobile composers.'),
          onChanged: (value) => _save(_settings.copyWith(enabled: value)),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Local Whisper', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          title: const Text('Whisper Base Model'),
          subtitle: Text(
            _modelDownloadError ??
                (_modelInstalled
                    ? 'Installed on this phone.'
                    : 'Download the local model before using offline dictation.'),
            style: _modelDownloadError == null
                ? null
                : Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AleraTokens.error),
          ),
          trailing: _modelDownloading
              ? const SizedBox.square(
                  dimension: AleraTokens.minTapTarget,
                  child: Padding(
                    padding: EdgeInsets.all(AleraTokens.space12),
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  ),
                )
              : FilledButton(
                  onPressed: _modelInstalled ? null : _downloadModel,
                  child: Text(
                    _modelInstalled
                        ? 'Ready'
                        : _modelDownloadError == null
                        ? 'Download'
                        : 'Retry',
                  ),
                ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Fallback Order', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          value: _settings.hostFallbackEnabled,
          title: const Text('Connected Host Whisper'),
          subtitle: const Text(
            'Use the paired runtime when local transcription is unavailable.',
          ),
          onChanged: (value) =>
              _save(_settings.copyWith(hostFallbackEnabled: value)),
        ),
        SwitchListTile(
          value: _settings.providerFallbackEnabled,
          title: const Text('OpenAI-Compatible Provider'),
          subtitle: const Text(
            'Use the configured provider as the final fallback.',
          ),
          onChanged: (value) =>
              _save(_settings.copyWith(providerFallbackEnabled: value)),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Provider', style: Theme.of(context).textTheme.titleMedium),
        TextField(
          controller: _url,
          decoration: const InputDecoration(labelText: 'Provider URL'),
          onChanged: (value) =>
              _save(_settings.copyWith(providerBaseUrl: value)),
        ),
        TextField(
          controller: _model,
          decoration: const InputDecoration(labelText: 'Provider Model'),
          onChanged: (value) => _save(_settings.copyWith(providerModel: value)),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        const Text(
          'The local Whisper model remains on this phone. Audio is sent to the host or provider only when that fallback is enabled.',
        ),
      ],
    ),
  );
}
