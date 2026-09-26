import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/voice/application/voice_session_controller.dart';
import 'package:alera/src/features/voice/domain/voice_session_status.dart';
import 'package:alera/src/features/voice/presentation/voice_home_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const VoiceStatusBarControl({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(voiceHomeAgentSupportedProvider).value ?? false;
    if (!supported) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(voiceSessionControllerProvider);
    final label = switch (status.phase) {
      VoiceSessionPhase.listening => 'Listening',
      VoiceSessionPhase.thinking => 'Thinking',
      VoiceSessionPhase.speaking => 'Speaking',
      VoiceSessionPhase.idle => 'Voice',
    };
    return Tooltip(
      message: 'Alera voice home agent',
      child: TextButton.icon(
        onPressed: () {
          unawaited(_open(context, ref));
        },
        icon: Icon(
          AleraIcons.mic,
          size: AleraTokens.iconMd,
          color: status.phase == VoiceSessionPhase.idle
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : AleraTokens.accent,
        ),
        label: Text(label),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(voiceSessionControllerProvider.notifier).refresh();
      if (!context.mounted) {
        return;
      }
      await showVoiceHomePanel(context);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AleraToast.show(context, message: error.toString(), tone: .error);
    }
  }
}
