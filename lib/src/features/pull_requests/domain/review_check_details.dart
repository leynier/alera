/// Detail metadata for a single review check, fetched lazily when the user
/// expands the check row. Transient (not persisted), so this stays a plain
/// value type.
class const ReviewCheckDetails({
  final String? description,
  final String? workflow,
  final String? event,
  final DateTime? startedAt,
  final DateTime? completedAt,
  final String? url,
});
