// Steer rule model representing a single steering instruction/tag.
class SteerRule {
  const SteerRule({
    required this.id,
    required this.label,
    this.active = true,
    required this.createdAt,
    this.order = 0,
  });

  final String id;
  final String label;
  final bool active;
  final DateTime createdAt;
  final int order;

  SteerRule copyWith({
    String? id,
    String? label,
    bool? active,
    DateTime? createdAt,
    int? order,
  }) {
    return SteerRule(
      id: id ?? this.id,
      label: label ?? this.label,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'active': active,
      'createdAt': createdAt.toIso8601String(),
      'order': order,
    };
  }

  factory SteerRule.fromJson(Map<String, dynamic> json) {
    return SteerRule(
      id: json['id'] as String,
      label: json['label'] as String,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      order: json['order'] as int? ?? 0,
    );
  }
}
