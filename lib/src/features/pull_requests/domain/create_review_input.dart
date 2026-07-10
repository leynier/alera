import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';

/// User-supplied parameters for creating a new hosted review from a workspace.
/// Transient (not persisted), so this stays a plain value type.
class CreateReviewInput {
  const CreateReviewInput({
    required this.provider,
    required this.title,
    required this.baseBranch,
    required this.headBranch,
    this.body,
    this.draft = false,
  });

  final GitHostingProvider provider;
  final String title;
  final String baseBranch;
  final String headBranch;
  final String? body;
  final bool draft;
}
