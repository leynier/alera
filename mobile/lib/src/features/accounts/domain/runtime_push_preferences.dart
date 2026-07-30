class RuntimePushPreferences {
  const RuntimePushPreferences({
    this.enabled = true,
    this.attention = true,
    this.done = false,
    this.terminalExit = false,
  });

  final bool enabled;
  final bool attention;
  final bool done;
  final bool terminalExit;

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

  factory RuntimePushPreferences.fromJson(Map<String, Object?> json) {
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
