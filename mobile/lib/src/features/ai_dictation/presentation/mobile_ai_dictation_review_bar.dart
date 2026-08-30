import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileAiDictationReviewBar extends ConsumerWidget {
  const MobileAiDictationReviewBar({
    super.key,
    required this.hostId,
    required this.targetKey,
  });

  final String hostId;
  final String targetKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mobileAiDictationControllerProvider(hostId, targetKey);
    final state = ref.watch(provider);
    if (state.stage == MobileAiDictationStage.idle) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(provider.notifier);
    return _RecordingBar(
      state: state,
      onStop: notifier.stop,
      onPlayPause: notifier.playPause,
      onSeek: notifier.seek,
      onTranscribe: notifier.transcribe,
      onRemove: notifier.removeRecording,
      onCancel: notifier.cancel,
    );
  }
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.state,
    required this.onStop,
    required this.onPlayPause,
    required this.onSeek,
    required this.onTranscribe,
    required this.onRemove,
    required this.onCancel,
  });

  final MobileAiDictationState state;
  final Future<void> Function() onStop;
  final Future<void> Function() onPlayPause;
  final Future<void> Function(Duration position) onSeek;
  final Future<void> Function() onTranscribe;
  final Future<void> Function() onRemove;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final processing =
        state.stage == MobileAiDictationStage.transcribing ||
        state.stage == MobileAiDictationStage.improving;
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                state.stage == MobileAiDictationStage.recording
                    ? Icons.fiber_manual_record
                    : processing
                    ? Icons.auto_awesome
                    : Icons.graphic_eq,
                color: state.stage == MobileAiDictationStage.recording
                    ? AleraTokens.error
                    : AleraTokens.foregroundMuted,
                size: AleraTokens.space16,
              ),
              const SizedBox(width: AleraTokens.space8),
              Text(
                processing
                    ? state.stage == MobileAiDictationStage.improving
                          ? 'Improving Transcript...'
                          : 'Transcribing Recording...'
                    : _formatDuration(
                        state.hasRecording
                            ? state.playbackPosition
                            : state.elapsed,
                      ),
                style: AleraTokens.monoStyle,
              ),
              if (state.segmentCount > 1) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                Text(
                  '${state.segmentCount} segments',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
              ],
              const SizedBox(width: AleraTokens.space8),
              Expanded(child: _progress()),
              const SizedBox(width: AleraTokens.space4),
              if (state.stage == MobileAiDictationStage.recording)
                IconButton(
                  tooltip: 'Stop Recording',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(onStop()),
                  icon: const Icon(Icons.stop),
                )
              else if (state.hasRecording) ...<Widget>[
                IconButton(
                  tooltip: state.stage == MobileAiDictationStage.playing
                      ? 'Pause Recording'
                      : 'Play Recording',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(onPlayPause()),
                  icon: Icon(
                    state.stage == MobileAiDictationStage.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove Recording',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(onRemove()),
                  icon: const Icon(Icons.delete_outline),
                ),
                FilledButton.icon(
                  onPressed: () => unawaited(onTranscribe()),
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: AleraTokens.space16,
                  ),
                  label: const Text('Transcribe'),
                ),
              ] else if (processing)
                TextButton(
                  onPressed: () => unawaited(onCancel()),
                  child: const Text('Cancel'),
                ),
            ],
          ),
          if (state.warning case final warning?)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                warning,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.warning),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progress() {
    if (state.stage == MobileAiDictationStage.recording) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        child: LinearProgressIndicator(
          value: state.amplitude,
          minHeight: AleraTokens.space8,
          backgroundColor: AleraTokens.border,
        ),
      );
    }
    if (state.hasRecording) {
      final maximum = state.duration.inMilliseconds
          .toDouble()
          .clamp(1.0, double.infinity)
          .toDouble();
      return Slider(
        value: state.playbackPosition.inMilliseconds.toDouble().clamp(
          0,
          maximum,
        ),
        max: maximum,
        onChanged: (value) =>
            unawaited(onSeek(Duration(milliseconds: value.round()))),
      );
    }
    return const LinearProgressIndicator();
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
