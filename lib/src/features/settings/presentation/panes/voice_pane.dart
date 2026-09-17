import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/features/voice/application/voice_session_controller.dart';
import 'package:alera/src/features/voice/domain/voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const VoiceSettingsPane({
  super.key,
  required this.settings,
  required this.groupKeys,
  required this.onChanged,
}) extends ConsumerStatefulWidget {
  final VoiceSettings settings;
  final Map<String, GlobalKey> groupKeys;
  final Future<void> Function(VoiceSettings Function(VoiceSettings)) onChanged;

  @override
  ConsumerState<VoiceSettingsPane> createState() => _VoiceSettingsPaneState();
}

class _VoiceSettingsPaneState extends ConsumerState<VoiceSettingsPane> {
  final TextEditingController _geminiController = TextEditingController();
  final TextEditingController _openaiController = TextEditingController();
  var _geminiConfigured = false;
  var _openaiConfigured = false;
  var _loadingCredentials = true;
  var _voiceSupported = false;
  String? _credentialError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCredentials());
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _openaiController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    try {
      final client = ref.read(runtimeVoiceClientProvider);
      if (!await client.isSupported()) {
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceSupported = false;
          _loadingCredentials = false;
          _credentialError = null;
        });
        return;
      }
      final status = await client.credentialStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceSupported = true;
        _geminiConfigured = status.geminiConfigured;
        _openaiConfigured = status.openaiConfigured;
        _loadingCredentials = false;
        _credentialError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCredentials = false;
        _credentialError = error.toString();
      });
    }
  }

  Future<void> _saveCredential({
    String? geminiToken,
    String? openaiToken,
  }) async {
    try {
      await ref
          .read(runtimeVoiceClientProvider)
          .saveCredentials(geminiToken: geminiToken, openaiToken: openaiToken);
      if (geminiToken != null) {
        _geminiController.clear();
      }
      if (openaiToken != null) {
        _openaiController.clear();
      }
      await _loadCredentials();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _credentialError = error.toString();
      });
    }
  }

  Future<void> _clearCredential(String provider) async {
    try {
      await ref
          .read(runtimeVoiceClientProvider)
          .clearCredentials(provider: provider);
      await _loadCredentials();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _credentialError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final profiles =
        ref.watch(agentProfilesProvider).value ?? const <AgentProfile>[];
    if (!_voiceSupported && !_loadingCredentials) {
      return Text(
        'Update this runtime to use the voice home agent.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          KeyedSubtree(
            key: widget.groupKeys['pipeline'],
            child: AleraSettingsGroup(
              title: 'Pipeline',
              description: 'Chained STT and TTS is cheaper. Realtime is one speech-to-speech model that still must not think or call tools.',
              children: <Widget>[
                AleraSettingRow(
                  title: 'Voice pipeline',
                  description: 'Chained uses independent STT and TTS. Realtime combines them.',
                  child: AleraDropdownField<VoicePipeline>(
                    value: settings.pipeline,
                    entries: const <AleraDropdownFieldEntry<VoicePipeline>>[
                      AleraDropdownFieldEntry(
                        value: VoicePipeline.chained,
                        label: 'Chained STT + TTS',
                      ),
                      AleraDropdownFieldEntry(
                        value: VoicePipeline.realtime,
                        label: 'Realtime speech-to-speech',
                      ),
                    ],
                    onChanged: (value) {
                      widget.onChanged(
                        (current) => current.copyWith(pipeline: value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space24),
          KeyedSubtree(
            key: widget.groupKeys['speech'],
            child: AleraSettingsGroup(
              title: 'Speech providers',
              description: 'Pick STT and TTS independently, or one realtime model. GPT Live / Realtime 2 stay premium.',
              children: <Widget>[
                if (settings.pipeline == VoicePipeline.chained) ...<Widget>[
                  AleraSettingRow(
                    title: 'Speech-to-text',
                    description: 'Local Whisper is the cheap default. Remote engines reuse AI Dictation credentials where possible.',
                    child: AleraDropdownField<VoiceSttProvider>(
                      value: settings.sttProvider,
                      entries:
                          const <AleraDropdownFieldEntry<VoiceSttProvider>>[
                            AleraDropdownFieldEntry(
                              value: VoiceSttProvider.localWhisper,
                              label: 'Local Whisper',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceSttProvider.geminiTranscribeLive,
                              label: 'Gemini transcribe',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceSttProvider.openAiCompatible,
                              label: 'OpenAI-compatible',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceSttProvider.codexRealtime,
                              label: 'Codex realtime',
                            ),
                          ],
                      onChanged: (value) {
                        widget.onChanged(
                          (current) => current.copyWith(sttProvider: value),
                        );
                      },
                    ),
                  ),
                  AleraSettingRow(
                    title: 'Text-to-speech',
                    description: 'Gemini Flash TTS is the cheap default.',
                    child: AleraDropdownField<VoiceTtsProvider>(
                      value: settings.ttsProvider,
                      entries:
                          const <AleraDropdownFieldEntry<VoiceTtsProvider>>[
                            AleraDropdownFieldEntry(
                              value: VoiceTtsProvider.geminiFlashTts,
                              label: 'Gemini Flash TTS',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceTtsProvider.openAiTts,
                              label: 'OpenAI TTS',
                            ),
                          ],
                      onChanged: (value) {
                        widget.onChanged(
                          (current) => current.copyWith(ttsProvider: value),
                        );
                      },
                    ),
                  ),
                ] else
                  AleraSettingRow(
                    title: 'Realtime model',
                    description: 'Speech-to-speech only. It transcribes and speaks host-supplied text; it must not reason or call tools.',
                    child: AleraDropdownField<VoiceRealtimeProvider>(
                      value: settings.realtimeProvider,
                      entries:
                          const <
                            AleraDropdownFieldEntry<VoiceRealtimeProvider>
                          >[
                            AleraDropdownFieldEntry(
                              value: VoiceRealtimeProvider.geminiFlashLive,
                              label: 'Gemini Flash Live',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceRealtimeProvider.gptRealtimeMini,
                              label: 'GPT Realtime Mini',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceRealtimeProvider.gptRealtime,
                              label: 'GPT Realtime',
                            ),
                            AleraDropdownFieldEntry(
                              value: VoiceRealtimeProvider.gptLive1,
                              label: 'GPT Live 1',
                            ),
                          ],
                      onChanged: (value) {
                        widget.onChanged(
                          (current) =>
                              current.copyWith(realtimeProvider: value),
                        );
                      },
                    ),
                  ),
                SettingsTextRow(
                  title: 'Voice name',
                  description: 'Optional provider voice name, for example Kore or alloy.',
                  value: settings.ttsVoice ?? '',
                  hintText: 'Kore',
                  onChanged: (value) {
                    widget.onChanged(
                      (current) => current.copyWith(
                        ttsVoice: value.trim().isEmpty ? null : value.trim(),
                      ),
                    );
                  },
                ),
                if (!_voiceSupported)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space12),
                    child: Text(
                      'Update this runtime to save voice API keys here.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else if (_credentialError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
                    child: SelectableText(
                      _credentialError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                AleraSettingRow(
                  title: 'Gemini API key',
                  description: _loadingCredentials
                      ? 'Checking saved credentials…'
                      : _geminiConfigured
                      ? 'A Gemini key is saved in the runtime keyring.'
                      : 'Required for Gemini TTS and Gemini Live.',
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: AleraTextField(
                          controller: _geminiController,
                          hintText: 'AIza…',
                          obscureText: true,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      TextButton(
                        onPressed: !_voiceSupported
                            ? null
                            : () async {
                                await _saveCredential(
                                  geminiToken: _geminiController.text,
                                );
                              },
                        child: const Text('Save'),
                      ),
                      TextButton(
                        onPressed: !_voiceSupported
                            ? null
                            : () async {
                                await _clearCredential('gemini');
                              },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                AleraSettingRow(
                  title: 'OpenAI API key',
                  description: _loadingCredentials
                      ? 'Checking saved credentials…'
                      : _openaiConfigured
                      ? 'An OpenAI key is saved in the runtime keyring.'
                      : 'Required for OpenAI TTS and GPT Realtime.',
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: AleraTextField(
                          controller: _openaiController,
                          hintText: 'sk-…',
                          obscureText: true,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      TextButton(
                        onPressed: !_voiceSupported
                            ? null
                            : () async {
                                await _saveCredential(
                                  openaiToken: _openaiController.text,
                                );
                              },
                        child: const Text('Save'),
                      ),
                      TextButton(
                        onPressed: !_voiceSupported
                            ? null
                            : () async {
                                await _clearCredential('openai');
                              },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space24),
          KeyedSubtree(
            key: widget.groupKeys['home'],
            child: AleraSettingsGroup(
              title: 'Home agent',
              description: 'The persistent CLI that thinks and delegates. Speech never calls tools.',
              children: <Widget>[
                AleraSettingRow(
                  title: 'Home profile',
                  description: 'Defaults to the runtime default agent profile.',
                  child: AleraDropdownField<String?>(
                    value: settings.homeAgentProfileId,
                    hintText: 'Runtime default',
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
                    onChanged: (value) {
                      widget.onChanged(
                        (current) =>
                            current.copyWith(homeAgentProfileId: value),
                      );
                    },
                  ),
                ),
                SettingsSwitchRow(
                  title: 'Ack while thinking',
                  description:
                      'Speak a short confirmation while the home agent works.',
                  value: settings.ackWhileThinking,
                  onChanged: (value) {
                    widget.onChanged(
                      (current) => current.copyWith(ackWhileThinking: value),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
