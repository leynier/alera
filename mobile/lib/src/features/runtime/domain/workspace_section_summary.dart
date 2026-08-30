class WorkspaceSectionSummary {
  const WorkspaceSectionSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  factory WorkspaceSectionSummary.fromJson(Map<String, Object?> json) =>
      WorkspaceSectionSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      );
}
