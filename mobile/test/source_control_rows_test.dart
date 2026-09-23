import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:alera_mobile/src/features/workbench/domain/source_control_rows.dart';
import 'package:flutter_test/flutter_test.dart';

const _entries = <MobileGitChange>[
  MobileGitChange(path: 'lib/b.dart', area: 'unstaged', status: 'modified'),
  MobileGitChange(path: 'lib/src/a.dart', area: 'staged', status: 'added'),
  MobileGitChange(
    path: 'docs/new.md',
    oldPath: 'docs/old.md',
    area: 'staged',
    status: 'renamed',
  ),
  MobileGitChange(path: 'notes.txt', area: 'untracked', status: 'untracked'),
];

String _describe(SourceControlRow row) => switch (row) {
  SourceControlSectionRow(:final section) =>
    '${section.key} (${section.entries.length})',
  SourceControlDirectoryRow(:final nodeKey, :final depth, :final fileCount) =>
    '$nodeKey d$depth ($fileCount)',
  SourceControlFileRow(:final change, :final depth, :final showParent) =>
    '${change.path} d$depth${showParent ? ' parent' : ''}',
};

void main() {
  test('groups by area in staged, unstaged, untracked order', () {
    final sections = sourceControlSections(
      _entries,
      MobileGitDiffGroupMode.byArea,
    );

    expect(sections.map((section) => section.label), <String>[
      'Staged',
      'Unstaged',
      'Untracked',
    ]);
  });

  test('unified mode shows one Changes section sorted by path', () {
    final sections = sourceControlSections(
      _entries,
      MobileGitDiffGroupMode.unified,
    );

    expect(sections.single.key, 'section:unified');
    expect(sections.single.entries.map((entry) => entry.path), <String>[
      'docs/new.md',
      'lib/b.dart',
      'lib/src/a.dart',
      'notes.txt',
    ]);
  });

  test('flat view lists files with their parent label', () {
    final rows = sourceControlRows(
      sourceControlSections(_entries, MobileGitDiffGroupMode.unified),
      viewMode: MobileGitDiffViewMode.flat,
      collapsedKeys: const <String>{},
    ).map(_describe);

    expect(rows, <String>[
      'section:unified (4)',
      'docs/new.md d0 parent',
      'lib/b.dart d0 parent',
      'lib/src/a.dart d0 parent',
      'notes.txt d0 parent',
    ]);
  });

  test('tree view lists folders before files with desktop node keys', () {
    final rows = sourceControlRows(
      sourceControlSections(_entries, MobileGitDiffGroupMode.unified),
      viewMode: MobileGitDiffViewMode.tree,
      collapsedKeys: const <String>{},
    ).map(_describe);

    expect(rows, <String>[
      'section:unified (4)',
      'folder:unified:docs d0 (1)',
      'docs/new.md d1',
      'folder:unified:lib d0 (2)',
      'folder:unified:lib/src d1 (1)',
      'lib/src/a.dart d2',
      'lib/b.dart d1',
      'notes.txt d0',
    ]);
  });

  test('collapsed sections and folders hide their contents', () {
    final rows = sourceControlRows(
      sourceControlSections(_entries, MobileGitDiffGroupMode.byArea),
      viewMode: MobileGitDiffViewMode.tree,
      collapsedKeys: const <String>{'section:staged', 'folder:unstaged:lib'},
    ).map(_describe);

    expect(rows, <String>[
      'section:staged (2)',
      'section:unstaged (1)',
      'folder:unstaged:lib d0 (1)',
      'section:untracked (1)',
      'notes.txt d0',
    ]);
  });

  test('collapsible keys cover sections and, in tree view, folders', () {
    final sections = sourceControlSections(
      _entries,
      MobileGitDiffGroupMode.byArea,
    );

    expect(sourceControlCollapsibleKeys(sections, viewMode: .flat), <String>{
      'section:staged',
      'section:unstaged',
      'section:untracked',
    });
    expect(sourceControlCollapsibleKeys(sections, viewMode: .tree), <String>{
      'section:staged',
      'section:unstaged',
      'section:untracked',
      'folder:staged:lib',
      'folder:staged:lib/src',
      'folder:staged:docs',
      'folder:unstaged:lib',
    });
  });

  test('filter matches the path or the old path, ignoring case', () {
    expect(
      filterSourceControlChanges(_entries, 'OLD').map((entry) => entry.path),
      <String>['docs/new.md'],
    );
    expect(
      filterSourceControlChanges(_entries, 'lib/').map((entry) => entry.path),
      <String>['lib/b.dart', 'lib/src/a.dart'],
    );
    expect(filterSourceControlChanges(_entries, '  '), _entries);
  });

  test('view prefs round-trip the panel view options', () {
    const prefs = MobileViewPrefs(
      gitDiffViewMode: MobileGitDiffViewMode.flat,
      gitDiffGroupMode: MobileGitDiffGroupMode.unified,
      searchViewAsTree: true,
      searchIncludeIgnored: true,
    );
    final json = prefs.toJson();

    expect(json['gitDiffViewMode'], 'flat');
    expect(json['gitDiffGroupMode'], 'unified');
    final restored = MobileViewPrefs.fromJson(json);
    expect(restored.gitDiffViewMode, MobileGitDiffViewMode.flat);
    expect(restored.gitDiffGroupMode, MobileGitDiffGroupMode.unified);
    expect(restored.searchViewAsTree, isTrue);
    expect(restored.searchIncludeIgnored, isTrue);
    final legacy = MobileViewPrefs.fromJson(const <String, Object?>{
      'gitDiffViewMode': 'sideways',
    });
    expect(legacy.gitDiffViewMode, MobileGitDiffViewMode.tree);
    expect(legacy.gitDiffGroupMode, MobileGitDiffGroupMode.byArea);
    expect(legacy.searchViewAsTree, isFalse);
  });
}
