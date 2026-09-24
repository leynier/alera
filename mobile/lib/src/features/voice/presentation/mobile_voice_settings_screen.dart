import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/settings/application/host_settings_controller.dart';
import 'package:alera_mobile/src/features/voice/domain/mobile_voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const MobileVoiceSettingsScreen({super.key, required this.host})
    extends ConsumerStatefulWidget {
  final PairedHostProfile host;

  @override
  ConsumerState<MobileVoiceSettingsScreen> createState() =>
      _MobileVoiceSettingsScreenState();
}

class _MobileVoiceSettingsScreenState
    extends ConsumerState<MobileVoiceSettingsScreen> {
  final TextEditingController _geminiController = TextEditingController();
  final TextEditingController _openaiController = TextEditingController();
  final TextEditingController _voiceController = TextEditingController();
  List<AgentProfileSummary> _profiles = const <AgentProfileSummary>[];
  var _geminiConfigured = false;
  var _openaiConfigured = false;
  var _loadingCredentials = true;
  var _voiceFieldSynced = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSideData());
    ref.listenManual(hostSettingsControllerProvider(widget.host.id), (
      previous,
      next,
    ) {
      next.whenData((value) {
        if (!_voiceFieldSynced && mounted) {
          _voiceController.text = value.voice.ttsVoice ?? '';
          _voiceFieldSynced = true;
        }
        if (!mounted) {
          return;
        }
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _openaiController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _loadSideData() async {
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.host.id).future,
      );
      final profiles = await client.listAgentProfiles();
      var geminiConfigured = false;
      var openaiConfigured = false;
      if (client.supportsVoiceHomeAgent) {
        final status = await client.voiceCredentialStatus();
        geminiConfigured = status.geminiConfigured;
        openaiConfigured = status.openaiConfigured;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = profiles;
        _geminiConfigured = geminiConfigured;
        _openaiConfigured = openaiConfigured;
        _loadingCredentials = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCredentials = false;
      });
    }
  }

  Future<void> _saveGemini() async {
    // Blank Save is a no-op; the host treats an empty token as a clear, and
    // only Clear may remove a saved key.
    final token = _geminiController.text.trim();
    if (token.isEmpty) {
      return;
    }
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.host.id).future,
      );
      final status = await client.saveVoiceCredentials(geminiToken: token);
      _geminiController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _geminiConfigured = status.geminiConfigured;
        _openaiConfigured = status.openaiConfigured;
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _saveOpenai() async {
    // Blank Save is a no-op; the host treats an empty token as a clear, and
    // only Clear may remove a saved key.
    final token = _openaiController.text.trim();
    if (token.isEmpty) {
      return;
    }
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.host.id).future,
      );
      final status = await client.saveVoiceCredentials(openaiToken: token);
      _openaiController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _geminiConfigured = status.geminiConfigured;
        _openaiConfigured = status.openaiConfigured;
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _clearProvider(String provider) async {
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.host.id).future,
      );
      final status = await client.clearVoiceCredentials(provider: provider);
      if (!mounted) {
        return;
      }
      setState(() {
        _geminiConfigured = status.geminiConfigured;
        _openaiConfigured = status.openaiConfigured;
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(hostSettingsControllerProvider(widget.host.id));
    ref.listen(hostSettingsControllerProvider(widget.host.id), (
      previous,
      next,
    ) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Settings')),
      body: SafeArea(
        child: settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: AleraTokens.pagePadding,
              child: Text(error.toString(), textAlign: .center),
            ),
          ),
          data: (value) {
            return _SettingsBody(
              hostId: widget.host.id,
              voice: value.voice,
              profiles: _profiles,
              geminiController: _geminiController,
              openaiController: _openaiController,
              voiceController: _voiceController,
              geminiConfigured: _geminiConfigured,
              openaiConfigured: _openaiConfigured,
              loadingCredentials: _loadingCredentials,
              onSaveGemini: _saveGemini,
              onSaveOpenai: _saveOpenai,
              onClear: _clearProvider,
            );
          },
        ),
      ),
    );
  }
}

class const _SettingsBody({
  required this.hostId,
  required this.voice,
  required this.profiles,
  required this.geminiController,
  required this.openaiController,
  required this.voiceController,
  required this.geminiConfigured,
  required this.openaiConfigured,
  required this.loadingCredentials,
  required this.onSaveGemini,
  required this.onSaveOpenai,
  required this.onClear,
}) extends ConsumerWidget {
  final String hostId;
  final MobileVoiceSettings voice;
  final List<AgentProfileSummary> profiles;
  final TextEditingController geminiController;
  final TextEditingController openaiController;
  final TextEditingController voiceController;
  final bool geminiConfigured;
  final bool openaiConfigured;
  final bool loadingCredentials;
  final Future<void> Function() onSaveGemini;
  final Future<void> Function() onSaveOpenai;
  final Future<void> Function(String provider) onClear;

  Future<void> _patch(
    WidgetRef ref,
    MobileVoiceSettings Function(MobileVoiceSettings) update,
  ) {
    return ref
        .read(hostSettingsControllerProvider(hostId).notifier)
        .updateVoice(update(voice));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Text(
          'Speech is I/O on this runtime. Keys stay in the host keyring.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Pipeline', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                AleraDropdownField<MobileVoicePipeline>(
                  labelText: 'Voice pipeline',
                  value: voice.pipeline,
                  entries: <AleraDropdownFieldEntry<MobileVoicePipeline>>[
                    for (final item in MobileVoicePipeline.values)
                      AleraDropdownFieldEntry<MobileVoicePipeline>(
                        value: item,
                        label: item.label,
                      ),
                  ],
                  onChanged: (value) => _patch(
                    ref,
                    (current) => current.copyWith(pipeline: value),
                  ),
                ),
                if (voice.pipeline == MobileVoicePipeline.chained) ...<Widget>[
                  const SizedBox(height: AleraTokens.spaceMd),
                  AleraDropdownField<MobileVoiceSttProvider>(
                    labelText: 'Speech to text',
                    value:
                        MobileVoiceSttProvider.mobileChoices.contains(
                          voice.sttProvider,
                        )
                        ? voice.sttProvider
                        : MobileVoiceSttProvider.localWhisper,
                    entries: <AleraDropdownFieldEntry<MobileVoiceSttProvider>>[
                      for (final item in MobileVoiceSttProvider.mobileChoices)
                        AleraDropdownFieldEntry<MobileVoiceSttProvider>(
                          value: item,
                          label: item.label,
                        ),
                    ],
                    onChanged: (value) => _patch(
                      ref,
                      (current) => current.copyWith(sttProvider: value),
                    ),
                  ),
                  const SizedBox(height: AleraTokens.spaceMd),
                  AleraDropdownField<MobileVoiceTtsProvider>(
                    labelText: 'Text to speech',
                    value: voice.ttsProvider,
                    entries: <AleraDropdownFieldEntry<MobileVoiceTtsProvider>>[
                      for (final item in MobileVoiceTtsProvider.values)
                        AleraDropdownFieldEntry<MobileVoiceTtsProvider>(
                          value: item,
                          label: item.label,
                        ),
                    ],
                    onChanged: (value) => _patch(
                      ref,
                      (current) => current.copyWith(ttsProvider: value),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: AleraTokens.spaceMd),
                  AleraDropdownField<MobileVoiceRealtimeProvider>(
                    labelText: 'Realtime model',
                    value: voice.realtimeProvider,
                    entries:
                        <AleraDropdownFieldEntry<MobileVoiceRealtimeProvider>>[
                          for (final item in MobileVoiceRealtimeProvider.values)
                            AleraDropdownFieldEntry<
                              MobileVoiceRealtimeProvider
                            >(value: item, label: item.label),
                        ],
                    onChanged: (value) => _patch(
                      ref,
                      (current) => current.copyWith(realtimeProvider: value),
                    ),
                  ),
                ],
                const SizedBox(height: AleraTokens.spaceMd),
                AleraTextField(
                  controller: voiceController,
                  labelText: 'TTS voice',
                  hintText: 'Kore',
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    _patch(
                      ref,
                      (current) => current.copyWith(
                        ttsVoice: trimmed,
                        clearTtsVoice: trimmed.isEmpty,
                      ),
                    );
                  },
                  onEditingComplete: () {
                    final trimmed = voiceController.text.trim();
                    _patch(
                      ref,
                      (current) => current.copyWith(
                        ttsVoice: trimmed,
                        clearTtsVoice: trimmed.isEmpty,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('API keys', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Text(
                  loadingCredentials
                      ? 'Checking saved credentials…'
                      : geminiConfigured
                      ? 'A Gemini key is saved in the runtime keyring.'
                      : 'Required for Gemini TTS and Gemini Live.',
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                AleraTextField(
                  controller: geminiController,
                  hintText: 'AIza…',
                  obscureText: true,
                ),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: onSaveGemini,
                      child: const Text('Save'),
                    ),
                    TextButton(
                      onPressed: () => onClear('gemini'),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.spaceMd),
                Text(
                  loadingCredentials
                      ? 'Checking saved credentials…'
                      : openaiConfigured
                      ? 'An OpenAI key is saved in the runtime keyring.'
                      : 'Required for OpenAI TTS and GPT Realtime.',
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                AleraTextField(
                  controller: openaiController,
                  hintText: 'sk-…',
                  obscureText: true,
                ),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: onSaveOpenai,
                      child: const Text('Save'),
                    ),
                    TextButton(
                      onPressed: () => onClear('openai'),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Home agent', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                AleraDropdownField<String?>(
                  labelText: 'Home profile',
                  hintText: 'Runtime default',
                  value: voice.homeAgentProfileId,
                  entries: <AleraDropdownFieldEntry<String?>>[
                    const AleraDropdownFieldEntry<String?>(
                      value: null,
                      label: 'Runtime default',
                    ),
                    for (final profile in profiles)
                      AleraDropdownFieldEntry<String?>(
                        value: profile.id,
                        label: profile.name,
                      ),
                  ],
                  onChanged: (value) => _patch(
                    ref,
                    (current) => current.copyWith(
                      homeAgentProfileId: value,
                      clearHomeAgentProfileId: value == null,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: .zero,
                  value: voice.ackWhileThinking,
                  onChanged: (value) => _patch(
                    ref,
                    (current) => current.copyWith(ackWhileThinking: value),
                  ),
                  title: const Text('Ack while thinking'),
                  subtitle: const Text(
                    'Speak a short confirmation while the home agent works.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
