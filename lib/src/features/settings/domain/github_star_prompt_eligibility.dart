import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/github_star_controller.dart';

/// Minimum time since the oldest project was created before the support prompt
/// may appear. Keeps the ask off first-run setup.
const Duration kGitHubStarPromptMinProjectAge = Duration(days: 3);

/// Whether the one-time GitHub star support prompt should be offered.
///
/// Callers still own once-per-process guards and loading waits. This only
/// answers the durable product rules: not muted, real usage age, and not
/// already starred.
bool shouldOfferGitHubStarPrompt({
  required bool starClicked,
  required List<Project> projects,
  required GitHubStarState starState,
  required DateTime now,
  Duration minProjectAge = kGitHubStarPromptMinProjectAge,
}) {
  if (starClicked || projects.isEmpty) {
    return false;
  }
  if (starState == GitHubStarState.loading ||
      starState == GitHubStarState.starring ||
      starState == GitHubStarState.starred) {
    return false;
  }
  DateTime? oldest;
  for (final project in projects) {
    final createdAt = project.createdAt;
    if (oldest == null || createdAt.isBefore(oldest)) {
      oldest = createdAt;
    }
  }
  if (oldest == null) {
    return false;
  }
  return !now.isBefore(oldest.add(minProjectAge));
}
