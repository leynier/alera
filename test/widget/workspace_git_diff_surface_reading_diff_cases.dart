part of 'workspace_git_diff_surface_test.dart';

void _registerWorkspaceGitDiffSurfaceReadingDiffTests() {
  testWidgets('diff surface cancels the request from the replaced tab', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/old.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 0,
          ),
        ],
      );
    final service = _BlockingReadingDiffService(backend);
    final oldTab = _diffTab(
      filePath: 'lib/old.dart',
      oldPath: 'lib/older.dart',
      title: 'old.dart',
    );

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: oldTab,
      readingDiffService: service,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pump();
    expect(service.started.single.filePath, 'lib/old.dart');
    expect(service.started.single.oldPath, 'lib/older.dart');

    await _pumpDiffSurface(
      tester,
      backend: backend,
      tab: _diffTab(filePath: 'lib/new.dart', title: 'new.dart'),
      readingDiffService: service,
    );
    await tester.pumpAndSettle();

    expect(service.canceled.single.filePath, 'lib/old.dart');
  });

  testWidgets(
    'unrelated tab metadata does not cancel reading diff generation',
    (tester) async {
      final backend = FakeGitBackend()
        ..gitDiffResult = const GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/main.dart',
              area: .unstaged,
              status: .modified,
              lines: <GitDiffLine>[GitDiffLine.addition('+new')],
              added: 1,
              removed: 1,
            ),
          ],
        );
      final service = _BlockingReadingDiffService(backend);
      final tab = _diffTab(filePath: 'lib/main.dart', title: 'main.dart');

      await _pumpDiffSurface(
        tester,
        backend: backend,
        tab: tab,
        readingDiffService: service,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Generate Reading Diff'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Reading Diff').last);
      await tester.pump();

      final reconstructed = WorkspaceTabRecord(
        id: tab.id,
        workspaceId: tab.workspaceId,
        kind: tab.kind,
        title: 'Renamed While Generating',
        createdAt: tab.createdAt,
        updatedAt: tab.updatedAt.add(const Duration(seconds: 1)),
        payload: <String, Object?>{
          ...tab.payload,
          workspaceTabManualTitlePayloadKey: true,
        },
      );
      await _pumpDiffSurface(
        tester,
        backend: backend,
        tab: reconstructed,
        readingDiffService: service,
      );
      await tester.pump();

      expect(service.canceled, isEmpty);
      expect(find.byTooltip('Cancel Reading Diff'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel Reading Diff'));
      await tester.pump();
      expect(service.canceled, hasLength(1));
    },
  );

  testWidgets('diff surface keeps reading diff failures visible', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      )
      ..readingDiffPatchResult = Uint8List.fromList(
        'diff --git a/lib/main.dart b/lib/main.dart\n'
                '--- a/lib/main.dart\n'
                '+++ b/lib/main.dart\n'
                '@@ -1 +1 @@\n'
                '-old\n'
                '+new\n'
            .codeUnits,
      );
    final readingDiffService = _PreparedReadingDiffService(backend);

    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: readingDiffService,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    expect(find.text('Generate Reading Diff'), findsNWidgets(2));
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pumpAndSettle();

    expect(find.text('Reading diff generation failed'), findsOneWidget);
    expect(
      find.text('Codex failed: Invalid schema for response format.'),
      findsOneWidget,
    );
  });

  testWidgets('diff surface keeps cancel visible when AI Assist is disabled', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      );
    final service = _BlockingReadingDiffService(backend);
    final settingsController = _MutableSettingsController(.defaults);
    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: service,
      settingsController: settingsController,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pump();

    settingsController.setAiAssistEnabled(false);
    await tester.pump();

    expect(find.byTooltip('Cancel Reading Diff'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel Reading Diff'));
    await tester.pump();
    expect(service.canceled, hasLength(1));
  });

  testWidgets('diff surface cancels before preparation opens confirmation', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      );
    final service = _BlockingPreparationReadingDiffService(backend);
    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: service,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pump();
    expect(find.byTooltip('Cancel Reading Diff'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel Reading Diff'));
    await tester.pump();
    expect(service.canceled, hasLength(1));

    service.completePreparation();
    await tester.pumpAndSettle();

    expect(find.text('Generate Reading Diff'), findsNothing);
    expect(find.byTooltip('Generate Reading Diff'), findsOneWidget);
  });

  testWidgets('diff surface blocks retry until cancellation completes', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      );
    final service = _BlockingReadingDiffService(
      backend,
      completeOnCancel: false,
    );
    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: service,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pump();

    await tester.tap(find.byTooltip('Cancel Reading Diff'));
    await tester.pump();

    expect(service.canceled, hasLength(1));
    expect(find.byTooltip('Cancel Reading Diff'), findsOneWidget);
    expect(find.byTooltip('Generate Reading Diff'), findsNothing);

    service.completeCancellation();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Generate Reading Diff'), findsOneWidget);
  });

  testWidgets('diff refresh waits for reading diff cancellation', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      );
    final service = _BlockingReadingDiffService(
      backend,
      completeOnCancel: false,
    );
    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: service,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pump();

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    expect(service.canceled, hasLength(1));
    expect(find.byTooltip('Cancel Reading Diff'), findsOneWidget);
    expect(find.byTooltip('Generate Reading Diff'), findsNothing);

    service.completeCancellation();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Generate Reading Diff'), findsOneWidget);
  });

  testWidgets(
    'diff surface keeps original toggle after AI Assist is disabled',
    (tester) async {
      final backend = FakeGitBackend()
        ..gitDiffResult = const GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/main.dart',
              area: .unstaged,
              status: .modified,
              lines: <GitDiffLine>[GitDiffLine.addition('+new')],
              added: 1,
              removed: 1,
            ),
          ],
        );
      final settingsController = _MutableSettingsController(.defaults);
      await _pumpDiffSurface(
        tester,
        backend: backend,
        readingDiffService: _CachedReadingDiffService(backend),
        settingsController: settingsController,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Generate Reading Diff'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show Original Diff'), findsOneWidget);

      settingsController.setAiAssistEnabled(false);
      await tester.pump();

      expect(find.byTooltip('Show Original Diff'), findsOneWidget);
      expect(find.byTooltip('Regenerate Reading Diff'), findsNothing);
      await tester.tap(find.byTooltip('Show Original Diff'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show Reading Diff'), findsOneWidget);
      expect(find.text('+snapshot-value'), findsOneWidget);
    },
  );

  testWidgets('failed regeneration preserves the prior original snapshot', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+new')],
            added: 1,
            removed: 1,
          ),
        ],
      );
    final service = _RegenerationFailureReadingDiffService(backend);
    await _pumpDiffSurface(
      tester,
      backend: backend,
      readingDiffService: service,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Generate Reading Diff'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Regenerate Reading Diff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Reading Diff').last);
    await tester.pumpAndSettle();
    expect(find.text('Reading diff generation failed'), findsOneWidget);

    await tester.tap(find.byTooltip('Show Original Diff'));
    await tester.pumpAndSettle();
    expect(find.text('+snapshot-value'), findsOneWidget);
    expect(find.text('+replacement-snapshot'), findsNothing);
  });
}
