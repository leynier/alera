enum MobileAiDictationStage {
  idle,
  recording,
  recorded,
  playing,
  transcribing,
  improving,
}

class MobileAiDictationState {
  const MobileAiDictationState({
    this.stage = MobileAiDictationStage.idle,
    this.elapsed = Duration.zero,
    this.duration = Duration.zero,
    this.playbackPosition = Duration.zero,
    this.amplitude = 0,
    this.audioReviewAvailable = false,
    this.segmentCount = 0,
    this.warning,
  });

  final MobileAiDictationStage stage;
  final Duration elapsed;
  final Duration duration;
  final Duration playbackPosition;
  final double amplitude;
  final bool audioReviewAvailable;
  final int segmentCount;
  final String? warning;

  bool get hasRecording =>
      stage == MobileAiDictationStage.recorded ||
      stage == MobileAiDictationStage.playing;

  MobileAiDictationState copyWith({
    MobileAiDictationStage? stage,
    Duration? elapsed,
    Duration? duration,
    Duration? playbackPosition,
    double? amplitude,
    bool? audioReviewAvailable,
    int? segmentCount,
    String? warning,
    bool clearWarning = false,
  }) => MobileAiDictationState(
    stage: stage ?? this.stage,
    elapsed: elapsed ?? this.elapsed,
    duration: duration ?? this.duration,
    playbackPosition: playbackPosition ?? this.playbackPosition,
    amplitude: amplitude ?? this.amplitude,
    audioReviewAvailable: audioReviewAvailable ?? this.audioReviewAvailable,
    segmentCount: segmentCount ?? this.segmentCount,
    warning: clearWarning ? null : warning ?? this.warning,
  );
}
