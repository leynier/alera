/// Snapshot of the mobile voice session shown by the Voice screen.
class const MobileVoiceSessionState({
  this.supported = false,
  this.active = false,
  this.busy = false,
  this.phase = 'idle',
  this.realtime = false,
  this.queuedSpeakCount = 0,
  this.queuedTurnCount = 0,
  this.lastSpoken,
  this.lastError,
}) {
  final bool supported;
  final bool active;
  final bool busy;
  final String phase;
  final bool realtime;
  final int queuedSpeakCount;
  final int queuedTurnCount;
  final String? lastSpoken;
  final String? lastError;

  MobileVoiceSessionState copyWith({
    bool? supported,
    bool? active,
    bool? busy,
    String? phase,
    bool? realtime,
    int? queuedSpeakCount,
    int? queuedTurnCount,
    String? lastSpoken,
    String? lastError,
  }) {
    return MobileVoiceSessionState(
      supported: supported ?? this.supported,
      active: active ?? this.active,
      busy: busy ?? this.busy,
      phase: phase ?? this.phase,
      realtime: realtime ?? this.realtime,
      queuedSpeakCount: queuedSpeakCount ?? this.queuedSpeakCount,
      queuedTurnCount: queuedTurnCount ?? this.queuedTurnCount,
      lastSpoken: lastSpoken ?? this.lastSpoken,
      lastError: lastError ?? this.lastError,
    );
  }
}
