class const ReviewActionAccess({
  this.canMerge,
  this.canMarkReady,
  this.mergeBlockReason,
}) {
  final bool? canMerge;
  final bool? canMarkReady;
  final String? mergeBlockReason;
}
