import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/github_star_prompt_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28, 12);
  final oldProject = _project(createdAt: now.subtract(const Duration(days: 3)));
  final youngProject = _project(
    createdAt: now.subtract(
      const Duration(days: 3) - const Duration(seconds: 1),
    ),
  );

  group('shouldOfferGitHubStarPrompt', () {
    test('requires a project at least three days old', () {
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[oldProject],
          starState: .notStarred,
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[youngProject],
          starState: .notStarred,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: const <Project>[],
          starState: .notStarred,
          now: now,
        ),
        isFalse,
      );
    });

    test('uses the oldest project when several exist', () {
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[youngProject, oldProject],
          starState: .notStarred,
          now: now,
        ),
        isTrue,
      );
    });

    test('stays off after mute or when already starred', () {
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: true,
          projects: <Project>[oldProject],
          starState: .notStarred,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[oldProject],
          starState: .starred,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[oldProject],
          starState: .loading,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[oldProject],
          starState: .starring,
          now: now,
        ),
        isFalse,
      );
    });

    test('still offers when gh is unavailable so the URL path can run', () {
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[oldProject],
          starState: .hidden,
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldOfferGitHubStarPrompt(
          starClicked: false,
          projects: <Project>[oldProject],
          starState: .error,
          now: now,
        ),
        isTrue,
      );
    });
  });
}

Project _project({required DateTime createdAt}) {
  return Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/tmp/alera',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
