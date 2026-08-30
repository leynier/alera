enum MobileAiDictationStage {
  idle,
  recording,
  recorded,
  playing,
  transcribing,
  improving,
}

class const MobileAiDictationState({
  final MobileAiDictationStage stage = MobileAiDictationStage.idle,
  final Duration elapsed = Duration.zero,
  final Duration duration = Duration.zero,
  final Duration playbackPosition = Duration.zero,
  final double amplitude = 0,
  final bool audioReviewAvailable = false,
  final int segmentCount = 0,
  final String? warning,
}) {
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
