import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiDictationControl extends ConsumerWidget {
  const AiDictationControl({super.key, required this.targetId});

  final String targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(aiDictationServiceProvider);
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final active = service.activeTargetId == targetId;
        final busy = service.isTranscribing && active;
        return AleraIconButton(
          tooltip: busy
              ? 'Transcribing'
              : active && service.isRecording
              ? 'Stop Dictation'
              : 'Start Dictation',
          icon: busy
              ? AleraIcons.loading
              : active && service.isRecording
              ? AleraIcons.stop
              : AleraIcons.mic,
          iconColor: active
              ? AleraTokens.onAccent
              : AleraTokens.foregroundMuted,
          backgroundColor: active ? AleraTokens.accent : null,
          borderColor: active ? AleraTokens.accent : AleraTokens.border,
          onPressed: busy ? null : () => unawaited(_toggle(service, active)),
        );
      },
    );
  }

  Future<void> _toggle(AiDictationService service, bool active) async {
    try {
      if (active && service.isRecording) {
        await service.stop();
      } else {
        await service.start(targetId);
      }
    } on Object catch (error) {
      AleraToast.publish(message: error.toString(), tone: AleraToastTone.error);
    }
  }
}
