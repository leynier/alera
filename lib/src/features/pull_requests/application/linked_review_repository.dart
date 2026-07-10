import 'package:alera/src/features/pull_requests/domain/linked_review.dart';

/// Persistence boundary for the single review linked to a workspace. Backed by
/// the runtime host (Drift); tests use an in-memory fake.
abstract interface class LinkedReviewRepository {
  /// The review linked to [workspaceId], or null when none is linked.
  Future<LinkedReview?> find(String workspaceId);

  /// Emits the linked review for [workspaceId] now and again whenever the
  /// persisted link changes.
  Stream<LinkedReview?> watch(String workspaceId);

  /// Persists (link or replace) the review association.
  Future<void> save(LinkedReview review);

  /// Removes the review linked to [workspaceId] (unlink).
  Future<void> remove(String workspaceId);
}
