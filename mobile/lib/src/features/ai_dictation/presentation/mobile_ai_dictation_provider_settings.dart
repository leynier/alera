import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_provider_credentials.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _credentialLog = Logger('MobileAiDictationProviderSettings');

class MobileAiDictationProviderSettings extends StatelessWidget {
  const MobileAiDictationProviderSettings({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final MobileAiDictationSettings settings;
  final ValueChanged<MobileAiDictationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final openAi = settings.engine == MobileAiDictationEngine.openAiCompatible;
    final codex = settings.engine == MobileAiDictationEngine.codexSubscription;
    if (!openAi && !codex) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Remote Provider', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space4),
        Text(
          settings.location == MobileAiDictationLocation.thisDevice
              ? 'Configure the API called directly by this mobile app.'
              : 'Configure the provider called by the paired runtime.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AleraTokens.foregroundMuted),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (openAi) ...<Widget>[
                  _CommittedProviderField(
                    label: 'Base URL',
                    value: settings.providerBaseUrl,
                    hintText: 'https://api.openai.com/v1',
                    onChanged: (value) =>
                        onChanged(settings.copyWith(providerBaseUrl: value)),
                  ),
                  const SizedBox(height: AleraTokens.spaceMd),
                  _CommittedProviderField(
                    label: 'Model',
                    value: settings.providerModel,
                    hintText: 'gpt-4o-mini-transcribe',
                    onChanged: (value) =>
                        onChanged(settings.copyWith(providerModel: value)),
                  ),
                  const SizedBox(height: AleraTokens.spaceMd),
                  if (settings.location == MobileAiDictationLocation.thisDevice)
                    _DirectTokenField(baseUrl: settings.providerBaseUrl)
                  else
                    const Text(
                      'The runtime uses the API token configured in desktop AI Dictation settings.',
                    ),
                ],
                if (codex)
                  _CommittedProviderField(
                    label: 'Realtime Model',
                    value: settings.codexRealtimeModel ?? '',
                    hintText: 'Subscription default',
                    allowEmpty: true,
                    onChanged: (value) => onChanged(
                      settings.copyWith(
                        codexRealtimeModel: value,
                        clearCodexRealtimeModel: value.isEmpty,
                      ),
                    ),
                  ),
                const SizedBox(height: AleraTokens.spaceMd),
                AleraDropdownField<int>(
                  value: settings.providerTimeoutSeconds,
                  labelText: 'Request Timeout',
                  entries: const <AleraDropdownFieldEntry<int>>[
                    AleraDropdownFieldEntry<int>(
                      value: 30,
                      label: '30 Seconds',
                    ),
                    AleraDropdownFieldEntry<int>(
                      value: 60,
                      label: '60 Seconds',
                    ),
                    AleraDropdownFieldEntry<int>(
                      value: 120,
                      label: '120 Seconds',
                    ),
                    AleraDropdownFieldEntry<int>(
                      value: 300,
                      label: '300 Seconds',
                    ),
                  ],
                  onChanged: (value) => onChanged(
                    settings.copyWith(providerTimeoutSeconds: value),
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

class _DirectTokenField extends ConsumerStatefulWidget {
  const _DirectTokenField({required this.baseUrl});

  final String baseUrl;

  @override
  ConsumerState<_DirectTokenField> createState() => _DirectTokenFieldState();
}

class _DirectTokenFieldState extends ConsumerState<_DirectTokenField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref
          .read(mobileAiDictationCredentialStoreProvider)
          .saveToken(_controller.text, baseUrl: widget.baseUrl);
      _controller.clear();
      ref.invalidate(mobileAiDictationCredentialStatusProvider(widget.baseUrl));
    } on Object catch (error) {
      _credentialLog.warning('mobile dictation token save failed', error);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _clear() async {
    try {
      await ref.read(mobileAiDictationCredentialStoreProvider).clearToken();
      ref.invalidate(mobileAiDictationCredentialStatusProvider(widget.baseUrl));
    } on Object catch (error) {
      _credentialLog.warning('mobile dictation token removal failed', error);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      mobileAiDictationCredentialStatusProvider(widget.baseUrl),
    );
    final configured = status.value?.configured == true;
    final matches = status.value?.matchesBaseUrl == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraTextField(
          key: const ValueKey<String>('mobile-ai-dictation-api-token'),
          controller: _controller,
          labelText: 'API Token',
          hintText: configured ? 'Replace saved token' : 'Bearer token',
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          onSubmitted: (_) => unawaited(_save()),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        Text(
          status.hasError
              ? 'Token status could not be read: ${status.error}'
              : configured && !matches
              ? 'The saved token belongs to another API origin.'
              : configured
              ? 'A token is stored securely on this mobile device.'
              : 'No token is stored. Tokenless APIs are supported.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: status.hasError || (configured && !matches)
                ? AleraTokens.error
                : AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AleraTokens.spaceSm,
          children: <Widget>[
            if (configured)
              OutlinedButton(
                onPressed: () => unawaited(_clear()),
                child: const Text('Remove Token'),
              ),
            FilledButton(
              onPressed: () => unawaited(_save()),
              child: Text(configured ? 'Replace Token' : 'Save Token'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommittedProviderField extends StatefulWidget {
  const _CommittedProviderField({
    required this.label,
    required this.value,
    required this.hintText,
    required this.onChanged,
    this.allowEmpty = false,
  });

  final String label;
  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool allowEmpty;

  @override
  State<_CommittedProviderField> createState() =>
      _CommittedProviderFieldState();
}

class _CommittedProviderFieldState extends State<_CommittedProviderField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_handleFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!_focus.hasFocus) _save();
  }

  void _save() {
    final value = _controller.text.trim();
    if ((value.isNotEmpty || widget.allowEmpty) && value != widget.value) {
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) => AleraTextField(
    controller: _controller,
    focusNode: _focus,
    labelText: widget.label,
    hintText: widget.hintText,
    onSubmitted: (_) => _save(),
  );
}
