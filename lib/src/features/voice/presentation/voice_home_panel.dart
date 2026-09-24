import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/voice/application/voice_session_controller.dart';
import 'package:alera/src/features/voice/domain/voice_session_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showVoiceHomePanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const VoiceHomePanel(),
  );
}

class const VoiceHomePanel({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<VoiceHomePanel> createState() => _VoiceHomePanelState();
}

class _VoiceHomePanelState extends ConsumerState<VoiceHomePanel> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      final error = ref.read(voiceSessionControllerProvider).lastError;
      if (error != null && error.isNotEmpty) {
        AleraToast.show(context, message: error, tone: .error);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: error.toString(), tone: .error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(voiceSessionControllerProvider);
    final phase = switch (status.phase) {
      VoiceSessionPhase.listening => 'Listening',
      VoiceSessionPhase.thinking => 'Thinking',
      VoiceSessionPhase.speaking => 'Speaking',
      VoiceSessionPhase.idle => 'Idle',
    };
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text('Voice', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space8),
            Text(
              'Speech is I/O. The home CLI thinks and delegates.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AleraTokens.space12),
            Text('Home agent: $phase'),
            if (status.queuedTurnCount > 0 ||
                status.queuedSpeakCount > 0) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Queued: ${status.queuedTurnCount} turns, ${status.queuedSpeakCount} spoken replies.',
              ),
            ],
            if (status.lastSpoken != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space12),
              Text(status.lastSpoken!),
            ],
            if (status.lastError != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space12),
              SelectableText(
                status.lastError!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AleraTokens.space16),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: _busy || status.phase != VoiceSessionPhase.idle
                      ? null
                      : () {
                          unawaited(
                            _run(
                              ref
                                  .read(voiceSessionControllerProvider.notifier)
                                  .start,
                            ),
                          );
                        },
                  child: const Text('Start'),
                ),
                const SizedBox(width: AleraTokens.space8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          unawaited(
                            _run(
                              ref
                                  .read(voiceSessionControllerProvider.notifier)
                                  .stop,
                            ),
                          );
                        },
                  child: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
