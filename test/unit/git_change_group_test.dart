import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitChangeGroup', () {
    test('fromEntries keeps staged unstaged and untracked sections', () {
      const entries = <GitChangeEntry>[
        GitChangeEntry(
          path: 'lib/new.dart',
          area: .untracked,
          status: .untracked,
        ),
        GitChangeEntry(
          path: 'lib/dirty.dart',
          area: .unstaged,
          status: .modified,
        ),
        GitChangeEntry(
          path: 'lib/staged.dart',
          area: .staged,
          status: .modified,
        ),
      ];

      final groups = GitChangeGroup.fromEntries(entries);
      expect(groups.map((group) => group.label).toList(), <String>[
        'Staged',
        'Unstaged',
        'Untracked',
      ]);
      expect(groups.every((group) => !group.unified), isTrue);
    });

    test('unifiedFromEntries merges areas and keeps dual-area paths', () {
      const entries = <GitChangeEntry>[
        GitChangeEntry(
          path: 'lib/new.dart',
          area: .untracked,
          status: .untracked,
        ),
        GitChangeEntry(
          path: 'lib/dirty.dart',
          area: .unstaged,
          status: .modified,
        ),
        GitChangeEntry(
          path: 'lib/dirty.dart',
          area: .staged,
          status: .modified,
        ),
        GitChangeEntry(
          path: 'lib/staged.dart',
          area: .staged,
          status: .modified,
        ),
      ];

      final groups = GitChangeGroup.unifiedFromEntries(entries);
      expect(groups, hasLength(1));
      final group = groups.single;
      expect(group.unified, isTrue);
      expect(group.label, 'Changes');
      expect(
        group.entries
            .map((entry) => '${entry.area.key}:${entry.path}')
            .toList(),
        <String>[
          'staged:lib/dirty.dart',
          'unstaged:lib/dirty.dart',
          'untracked:lib/new.dart',
          'staged:lib/staged.dart',
        ],
      );
      expect(
        group.treeRows
            .where((row) => row.kind == GitChangeTreeRowKind.file)
            .map((row) => '${row.entry!.area.key}:${row.path}')
            .toList(),
        <String>[
          'staged:lib/dirty.dart',
          'unstaged:lib/dirty.dart',
          'untracked:lib/new.dart',
          'staged:lib/staged.dart',
        ],
      );
    });
  });
}
