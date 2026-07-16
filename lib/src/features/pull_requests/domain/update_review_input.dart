/// User-supplied edits for an existing hosted review. A null field means
/// "leave unchanged". Transient (not persisted), so this stays a plain value
/// type.
class UpdateReviewInput {
  const UpdateReviewInput({this.title, this.baseBranch});

  final String? title;
  final String? baseBranch;

  bool get isEmpty => title == null && baseBranch == null;
}
