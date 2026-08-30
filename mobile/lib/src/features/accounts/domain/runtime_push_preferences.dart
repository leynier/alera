class const RuntimePushPreferences({
  final bool enabled = true,
  final bool attention = true,
  final bool done = false,
  final bool terminalExit = false,
}) {
  bool get hasEnabledCategory => enabled && (attention || done || terminalExit);

  RuntimePushPreferences copyWith({
    bool? enabled,
    bool? attention,
    bool? done,
    bool? terminalExit,
  }) {
    return RuntimePushPreferences(
      enabled: enabled ?? this.enabled,
      attention: attention ?? this.attention,
      done: done ?? this.done,
      terminalExit: terminalExit ?? this.terminalExit,
    );
  }

  factory fromJson(Map<String, Object?> json) {
    return RuntimePushPreferences(
      enabled: json['enabled'] != false,
      attention: json['attention'] != false,
      done: json['done'] == true,
      terminalExit: json['terminalExit'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'attention': attention,
      'done': done,
      'terminalExit': terminalExit,
    };
  }
}
