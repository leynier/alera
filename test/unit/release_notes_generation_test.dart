import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/generate_release_notes.dart' as release_notes;

void main() {
  group('history parsing', () {
    test('splits sha and subject and detects pull request merges', () {
      final entries = release_notes.parseHistory(
        'aaa1 Merge pull request #138 from leynier/chore/launcher-icons\n'
        'bbb2 fix: patch something directly on main\n'
        '\n',
      );
      expect(entries, hasLength(2));
      expect(entries[0].sha, 'aaa1');
      expect(entries[0].pullRequestNumber, 138);
      expect(entries[1].subject, 'fix: patch something directly on main');
      expect(entries[1].pullRequestNumber, isNull);
    });

    test('identifies release bookkeeping commits for both products', () {
      expect(
        release_notes.isReleaseBookkeepingSubject('release: v0.18.0'),
        isTrue,
      );
      expect(
        release_notes.isReleaseBookkeepingSubject('release: mobile-v0.0.1'),
        isTrue,
      );
      expect(
        release_notes.isReleaseBookkeepingSubject(
          'release: v1.2.3 v0.4.0-mobile',
        ),
        isTrue,
      );
      expect(
        release_notes.isReleaseBookkeepingSubject('fix: release notes tool'),
        isFalse,
      );
    });
  });

  group('scope predicates', () {
    test('mobile scope only matches entries touching mobile paths', () {
      expect(
        release_notes.pathsMatchScope('mobile', ['mobile/pubspec.yaml']),
        isTrue,
      );
      expect(
        release_notes.pathsMatchScope('mobile', [
          'lib/main.dart',
          'mobile/lib/main.dart',
        ]),
        isTrue,
      );
      expect(
        release_notes.pathsMatchScope('mobile', [
          'lib/main.dart',
          'landing/index.html',
        ]),
        isFalse,
      );
    });

    test('desktop scope ignores mobile-only and landing-only entries', () {
      expect(
        release_notes.pathsMatchScope('desktop', ['lib/main.dart']),
        isTrue,
      );
      expect(
        release_notes.pathsMatchScope('desktop', [
          'mobile/lib/main.dart',
          'rust/src/api/git.rs',
        ]),
        isTrue,
      );
      expect(
        release_notes.pathsMatchScope('desktop', [
          'mobile/lib/main.dart',
          'landing/index.html',
        ]),
        isFalse,
      );
    });
  });

  group('notes composition', () {
    test('mixes pull request and commit bullets with a compare link', () {
      final notes = release_notes.composeReleaseNotes(
        repo: 'leynier/alera',
        tag: 'mobile-v0.0.2',
        previousTag: 'mobile-v0.0.1',
        bullets: [
          '* feat: add mobile app by @leynier in '
              'https://github.com/leynier/alera/pull/130',
          '* fix: hotfix on main by @leynier in '
              'https://github.com/leynier/alera/commit/abc123',
        ],
      );
      expect(notes, contains("## What's Changed"));
      expect(notes, contains('pull/130'));
      expect(notes, contains('commit/abc123'));
      expect(
        notes,
        contains(
          '**Full Changelog**: https://github.com/leynier/alera/compare/'
          'mobile-v0.0.1...mobile-v0.0.2',
        ),
      );
    });

    test('falls back to a commits link when there is no previous tag', () {
      final notes = release_notes.composeReleaseNotes(
        repo: 'leynier/alera',
        tag: 'mobile-v0.0.1',
        bullets: ['* feat: add mobile app'],
      );
      expect(
        notes,
        contains(
          '**Full Changelog**: '
          'https://github.com/leynier/alera/commits/mobile-v0.0.1',
        ),
      );
    });

    test('keeps the changelog link when no entries match the scope', () {
      final notes = release_notes.composeReleaseNotes(
        repo: 'leynier/alera',
        tag: 'v0.19.0',
        previousTag: 'v0.18.0',
        bullets: const [],
      );
      expect(notes, isNot(contains("## What's Changed")));
      expect(notes, contains('compare/v0.18.0...v0.19.0'));
    });
  });

  group('option parsing', () {
    test('requires a valid scope and mandatory flags', () {
      expect(
        () => release_notes.parseOptions(['--scope', 'web']),
        throwsArgumentError,
      );
      final options = release_notes.parseOptions([
        '--scope',
        'mobile',
        '--repo',
        'leynier/alera',
        '--tag',
        'mobile-v0.0.2',
        '--target',
        'abc123',
        '--previous-tag',
        'mobile-v0.0.1',
        '--output',
        'notes.md',
      ]);
      expect(options.scope, 'mobile');
      expect(options.previousTag, 'mobile-v0.0.1');
      expect(options.output, 'notes.md');
    });
  });
}
