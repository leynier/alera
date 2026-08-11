class MobileCodexPreferences {
  const MobileCodexPreferences({
    this.model,
    this.reasoningEffort = 'medium',
    this.speedMode = 'normal',
    this.permissionMode = 'untrusted',
    this.planMode = false,
  });

  final String? model;
  final String reasoningEffort;
  final String speedMode;
  final String permissionMode;
  final bool planMode;

  factory MobileCodexPreferences.fromJson(Map<String, Object?> json) =>
      MobileCodexPreferences(
        model: json['model'] is String ? json['model']! as String : null,
        reasoningEffort: json['reasoningEffort'] is String
            ? json['reasoningEffort']! as String
            : 'medium',
        speedMode: json['speedMode'] == 'fast' ? 'fast' : 'normal',
        permissionMode: switch (json['permissionMode']) {
          'auto-review' => 'auto-review',
          'on-request' => 'on-request',
          'never' => 'never',
          _ => 'untrusted',
        },
        planMode: json['planMode'] == true,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'reasoningEffort': reasoningEffort,
    'speedMode': speedMode,
    'permissionMode': permissionMode,
    'planMode': planMode,
  };
}
