import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_remote_settings.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:flutter/material.dart';

class AiDictationSettingsTest extends StatefulWidget {
  const AiDictationSettingsTest({
    super.key,
    required this.settings,
    this.groupKey,
  });

  final AiDictationSettings settings;
  final GlobalKey? groupKey;

  @override
  State<AiDictationSettingsTest> createState() =>
      _AiDictationSettingsTestState();
}

class _AiDictationSettingsTestState extends State<AiDictationSettingsTest> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _canTest(widget.settings);
    return KeyedSubtree(
      key: widget.groupKey,
      child: AleraSettingsGroup(
        title: 'Test AI Dictation',
        description:
            'Record a short sample with the current configuration and review the transcript here.',
        children: <Widget>[
          AleraSettingRow(
            title: 'Test Transcript',
            description: _testDescription(widget.settings, enabled),
            child: AiDictationTarget(
              controller: _controller,
              focusNode: _focusNode,
              initialPrompt: 'AI Dictation settings test',
              builder: (context, targetId) => AleraTextField(
                key: const ValueKey<String>('ai-dictation-test-transcript'),
                controller: _controller,
                focusNode: _focusNode,
                hintText: 'Your test transcription appears here',
                suffix: AiDictationControl(
                  key: const ValueKey<String>('ai-dictation-test-control'),
                  targetId: targetId,
                  enabled: enabled,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _canTest(AiDictationSettings settings) {
  if (!settings.enabled) return false;
  final remote =
      settings.transcriptionEngine ==
          AiDictationTranscriptionEngine.codexSubscription ||
      settings.transcriptionEngine ==
          AiDictationTranscriptionEngine.openAiCompatible;
  return !remote ||
      settings.remoteConsentVersion == aiDictationRemoteConsentVersion;
}

String _testDescription(AiDictationSettings settings, bool enabled) {
  if (!settings.enabled) {
    return 'Enable AI Dictation before testing.';
  }
  if (!enabled) {
    return 'Allow remote audio processing before testing this engine.';
  }
  return 'Select the microphone, speak, then select Stop Dictation.';
}
