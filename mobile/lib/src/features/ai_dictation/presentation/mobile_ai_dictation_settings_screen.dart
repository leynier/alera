import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MobileAiDictationSettingsScreen extends StatefulWidget {
  const MobileAiDictationSettingsScreen({super.key});
  @override
  State<MobileAiDictationSettingsScreen> createState() =>
      _MobileAiDictationSettingsScreenState();
}

class _MobileAiDictationSettingsScreenState
    extends State<MobileAiDictationSettingsScreen> {
  MobileAiDictationSettings _settings = const MobileAiDictationSettings();
  final _modelStore = MobileAiDictationModelStore();
  bool _modelInstalled = false;
  final _url = TextEditingController();
  final _model = TextEditingController();

  @override
  void initState() {
    super.initState();
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
    await _modelStore.download();
    if (mounted) setState(() => _modelInstalled = true);
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
            _modelInstalled
                ? 'Installed on this phone.'
                : 'Download the local model before using offline dictation.',
          ),
          trailing: FilledButton(
            onPressed: _modelInstalled ? null : _downloadModel,
            child: Text(_modelInstalled ? 'Ready' : 'Download'),
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
