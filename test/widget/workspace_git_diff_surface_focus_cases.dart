part of 'workspace_git_diff_surface_test.dart';

void _registerWorkspaceGitDiffSurfaceFocusTests() {
  testWidgets(
    'diff surface requests focus when clicked so its pane activates',
    (tester) async {
      final backend = FakeGitBackend()..gitDiffResult = _focusCaseDiff();
      var paneFocused = false;

      await _pumpDiffSurface(
        tester,
        backend: backend,
        onPaneFocusChange: (hasFocus) => paneFocused = hasFocus,
      );
      await tester.pumpAndSettle();

      expect(paneFocused, isFalse);

      await tester.tap(find.text('+  next();'));
      await tester.pump();

      expect(paneFocused, isTrue);
      expect(
        find.ancestor(
          of: find.byWidget(
            tester.binding.focusManager.primaryFocus!.context!.widget,
          ),
          matching: find.byType(WorkspaceGitDiffSurface),
        ),
        findsOneWidget,
        reason: 'the surface itself must hold focus, not the route scope',
      );
    },
  );

  testWidgets('diff surface claims focus on mount when it is the active pane', (
    tester,
  ) async {
    final backend = FakeGitBackend()..gitDiffResult = _focusCaseDiff();
    var paneFocused = false;

    await _pumpDiffSurface(
      tester,
      backend: backend,
      autofocus: true,
      onPaneFocusChange: (hasFocus) => paneFocused = hasFocus,
    );
    await tester.pump();
    await tester.pump();

    expect(paneFocused, isTrue);
  });
}

GitDiffResult _focusCaseDiff() {
  return const GitDiffResult(
    files: <GitDiffFile>[
      GitDiffFile(
        path: 'lib/large.dart',
        area: .unstaged,
        status: .modified,
        lines: <GitDiffLine>[
          GitDiffLine.hunk('@@ -10,2 +12,3 @@ class Foo'),
          GitDiffLine.context(' void start() {'),
          GitDiffLine.addition('+  next();'),
        ],
        added: 1,
        removed: 0,
      ),
    ],
  );
}
