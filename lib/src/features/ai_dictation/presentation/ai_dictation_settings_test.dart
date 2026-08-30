import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_remote_settings.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:flutter/material.dart';

class const AiDictationSettingsTest({
  super.key,
  required final AiDictationSettings settings,
  required final bool remoteSupported,
  final GlobalKey? groupKey,
}) extends StatefulWidget {
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
    final enabled = _canTest(widget.settings, widget.remoteSupported);
    return KeyedSubtree(
      key: widget.groupKey,
      child: AleraSettingsGroup(
        title: 'Test AI Dictation',
        description: 'Record a short sample with the current configuration and review the transcript here.',
        children: <Widget>[
          AleraSettingRow(
            title: 'Test Transcript',
            description: _testDescription(
              widget.settings,
              enabled,
              widget.remoteSupported,
            ),
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

bool _canTest(AiDictationSettings settings, bool remoteSupported) {
  if (!settings.enabled) return false;
  final remote =
      settings.transcriptionEngine ==
          AiDictationTranscriptionEngine.codexSubscription ||
      settings.transcriptionEngine ==
          AiDictationTranscriptionEngine.openAiCompatible;
  if (remote && !remoteSupported) return false;
  return !remote ||
      settings.remoteConsentVersion == aiDictationRemoteConsentVersion;
}

String _testDescription(
  AiDictationSettings settings,
  bool enabled,
  bool remoteSupported,
) {
  if (!settings.enabled) {
    return 'Enable AI Dictation before testing.';
  }
  if (!enabled) {
    final remote =
        settings.transcriptionEngine ==
            AiDictationTranscriptionEngine.codexSubscription ||
        settings.transcriptionEngine ==
            AiDictationTranscriptionEngine.openAiCompatible;
    if (remote && !remoteSupported) {
      return 'Restart Alera to update the runtime before testing remote transcription.';
    }
    return 'Allow remote audio processing before testing this engine.';
  }
  return 'Select the microphone, speak, then select Stop Dictation.';
}
