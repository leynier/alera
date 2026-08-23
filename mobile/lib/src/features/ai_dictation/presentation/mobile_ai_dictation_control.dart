import 'dart:async';

import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileAiDictationControl extends ConsumerWidget {
  const MobileAiDictationControl({
    super.key,
    required this.hostId,
    required this.targetKey,
    required this.controller,
    this.workspaceId,
    this.tabId,
    this.enabled = true,
  });

  final String hostId;
  final String targetKey;
  final TextEditingController controller;
  final String? workspaceId;
  final String? tabId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(mobileAiDictationSettingsControllerProvider);
    if (settings.value?.enabled != true) return const SizedBox.shrink();
    final provider = mobileAiDictationControllerProvider(hostId, targetKey);
    final state = ref.watch(provider);
    ref.listen(provider.select((value) => value.warning), (previous, warning) {
      if (warning != null && warning != previous && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(warning)));
      }
    });
    final notifier = ref.read(provider.notifier);
    return IconButton(
      tooltip: switch (state.stage) {
        MobileAiDictationStage.idle => 'Start Dictation',
        MobileAiDictationStage.recording => 'Stop Dictation',
        MobileAiDictationStage.recorded ||
        MobileAiDictationStage.playing => 'Review Recording',
        MobileAiDictationStage.transcribing => 'Transcribing',
        MobileAiDictationStage.improving => 'Improving Transcript',
      },
      onPressed:
          !enabled ||
              state.stage == MobileAiDictationStage.transcribing ||
              state.stage == MobileAiDictationStage.improving ||
              state.hasRecording
          ? null
          : () => unawaited(_toggle(context, notifier, state.stage)),
      icon: Icon(switch (state.stage) {
        MobileAiDictationStage.idle => AleraIcons.mic,
        MobileAiDictationStage.recording => AleraIcons.stop,
        MobileAiDictationStage.recorded ||
        MobileAiDictationStage.playing => AleraIcons.audio,
        MobileAiDictationStage.transcribing ||
        MobileAiDictationStage.improving => AleraIcons.loading,
      }),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    MobileAiDictationController notifier,
    MobileAiDictationStage stage,
  ) async {
    try {
      if (stage == MobileAiDictationStage.recording) {
        await notifier.stop();
      } else {
        await notifier.start(
          workspaceId: workspaceId,
          tabId: tabId,
          onText: _insert,
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _insert(String text) {
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
  }
}
