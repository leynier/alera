import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';

/// User-supplied parameters for creating a new hosted review from a workspace.
/// Transient (not persisted), so this stays a plain value type.
class const CreateReviewInput({
  required final GitHostingProvider provider,
  required final String title,
  required final String baseBranch,
  required final String headBranch,
  final String? body,
  final bool draft = false,
});
