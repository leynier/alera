import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const aiDictationRemoteConsentVersion = 1;

class AiDictationRemoteSettings extends ConsumerStatefulWidget {
  const AiDictationRemoteSettings({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.supported,
    this.groupKey,
  });

  final AiDictationSettings settings;
  final ValueChanged<AiDictationSettings Function(AiDictationSettings)>
  onChanged;
  final bool supported;
  final GlobalKey? groupKey;

  @override
  ConsumerState<AiDictationRemoteSettings> createState() =>
      _AiDictationRemoteSettingsState();
}

class _AiDictationRemoteSettingsState
    extends ConsumerState<AiDictationRemoteSettings> {
  final TextEditingController _tokenController = TextEditingController();
  bool _loadingToken = true;
  bool _savingToken = false;
  bool _tokenConfigured = false;
  bool _tokenMatchesBaseUrl = false;
  String? _tokenError;

  @override
  void initState() {
    super.initState();
    _tokenController.addListener(_handleTokenChanged);
    unawaited(_loadTokenStatus());
  }

  @override
  void dispose() {
    _tokenController.removeListener(_handleTokenChanged);
    _tokenController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AiDictationRemoteSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.remoteBaseUrl != widget.settings.remoteBaseUrl ||
        oldWidget.supported != widget.supported) {
      unawaited(_loadTokenStatus());
    }
  }

  void _handleTokenChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTokenStatus() async {
    try {
      final status = await ref
          .read(aiDictationCredentialStoreProvider)
          .status(widget.settings.remoteBaseUrl);
      if (mounted) {
        setState(() {
          _loadingToken = false;
          _tokenConfigured = status.configured;
          _tokenMatchesBaseUrl = status.matchesBaseUrl;
          _tokenError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loadingToken = false;
          _tokenError = error.toString();
        });
      }
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty || _savingToken) return;
    setState(() {
      _savingToken = true;
      _tokenError = null;
    });
    try {
      await ref
          .read(aiDictationCredentialStoreProvider)
          .saveToken(
            token,
            baseUrl: widget.settings.remoteBaseUrl?.trim() ?? '',
          );
      _tokenController.clear();
      if (mounted) {
        setState(() {
          _savingToken = false;
          _tokenConfigured = true;
          _tokenMatchesBaseUrl = true;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _savingToken = false;
          _tokenError = error.toString();
        });
      }
    }
  }

  Future<void> _clearToken() async {
    if (_savingToken) return;
    setState(() {
      _savingToken = true;
      _tokenError = null;
    });
    try {
      await ref.read(aiDictationCredentialStoreProvider).clearToken();
      if (mounted) {
        setState(() {
          _savingToken = false;
          _tokenConfigured = false;
          _tokenMatchesBaseUrl = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _savingToken = false;
          _tokenError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final engine = settings.transcriptionEngine;
    final usesOpenAi =
        engine == AiDictationTranscriptionEngine.openAiCompatible;
    final usesCodex =
        engine == AiDictationTranscriptionEngine.codexSubscription;
    return KeyedSubtree(
      key: widget.groupKey,
      child: AleraSettingsGroup(
        title: 'Remote Transcription',
        description: 'Send recordings to Codex or an OpenAI-compatible speech API. Transcription endpoints do not use reasoning effort.',
        children: <Widget>[
          if (!widget.supported)
            const AleraSettingRow(
              title: 'Runtime Update Required',
              description: 'Restart Alera to replace the running sidecar before configuring remote transcription.',
              child: SizedBox.shrink(),
            ),
          if (widget.supported) ...<Widget>[
            SettingsSwitchRow(
              title: 'Allow Remote Audio Processing',
              description: 'Recordings may leave this device and are deleted locally after transcription.',
              value:
                  settings.remoteConsentVersion ==
                  aiDictationRemoteConsentVersion,
              onChanged: (value) => widget.onChanged(
                (settings) => settings.copyWith(
                  remoteConsentVersion: value
                      ? aiDictationRemoteConsentVersion
                      : null,
                ),
              ),
            ),
            if (usesCodex)
              SettingsTextRow(
                title: 'Realtime Model',
                description: 'Optional Codex realtime model override. Leave blank to use the subscription default. This Codex API is experimental.',
                value: settings.codexRealtimeModel ?? '',
                hintText: 'Subscription default',
                onChanged: (value) => widget.onChanged(
                  (settings) => settings.copyWith(
                    codexRealtimeModel: value.isEmpty ? null : value,
                  ),
                ),
              ),
            if (usesOpenAi) ...<Widget>[
              SettingsTextRow(
                title: 'Base URL',
                description: 'Base API URL. Alera appends /audio/transcriptions when needed and preserves query parameters.',
                value: settings.remoteBaseUrl ?? '',
                hintText: 'https://api.openai.com/v1',
                onChanged: (value) => widget.onChanged(
                  (settings) => settings.copyWith(
                    remoteBaseUrl: value.isEmpty ? null : value,
                  ),
                ),
              ),
              SettingsTextRow(
                title: 'Model',
                description:
                    'Speech-to-text model accepted by the configured API.',
                value: settings.remoteModel ?? '',
                hintText: 'gpt-4o-mini-transcribe',
                onChanged: (value) => widget.onChanged(
                  (settings) => settings.copyWith(
                    remoteModel: value.isEmpty ? null : value,
                  ),
                ),
              ),
              _tokenRow(context),
            ],
            if (usesOpenAi || usesCodex)
              SettingsIntegerRow(
                title: 'Request Timeout',
                description: 'Maximum time allowed for remote transcription.',
                value: settings.timeoutSeconds,
                min: 5,
                max: 300,
                step: 5,
                suffix: 's',
                onChanged: (value) => widget.onChanged(
                  (settings) => settings.copyWith(timeoutSeconds: value),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tokenRow(BuildContext context) {
    final status = _loadingToken
        ? 'Checking saved token...'
        : _tokenError ??
              (_tokenConfigured && !_tokenMatchesBaseUrl
                  ? 'The saved token belongs to another API origin. Replace it before transcribing.'
                  : _tokenConfigured
                  ? 'A token is stored for this API origin.'
                  : 'No token is stored. Tokenless local APIs are also supported.');
    return AleraSettingRow(
      title: 'API Token',
      description: 'Optional Bearer token. It uses the system credential store, with a private 0600 file fallback on Linux, and is never stored in Settings.',
      controlWidth: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AleraTextField(
            key: const ValueKey<String>('ai-dictation-api-token'),
            controller: _tokenController,
            hintText: _tokenConfigured ? 'Replace saved token' : 'Bearer token',
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            textActionsEnabled: false,
            onSubmitted: (_) => unawaited(_saveToken()),
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _tokenError == null
                  ? AleraTokens.foregroundMuted
                  : AleraTokens.error,
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              if (_tokenConfigured)
                OutlinedButton(
                  onPressed: _savingToken ? null : _clearToken,
                  child: const Text('Remove Token'),
                ),
              FilledButton(
                onPressed: _savingToken || _tokenController.text.trim().isEmpty
                    ? null
                    : _saveToken,
                child: Text(_tokenConfigured ? 'Replace Token' : 'Save Token'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
