import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_service.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

void main() {
  testWidgets('git diff panel hides zero-valued line counts', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
            added: 12,
            removed: 0,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitBackendProvider.overrideWithValue(backend),
          settingsControllerProvider.overrideWith(
            () => _PanelSettingsController(AleraSettings.defaults),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 420,
              child: WorkspaceGitDiffPanel(
                workspace: _workspace(),
                viewMode: GitDiffViewMode.flat,
                onViewModeChanged: (_) {},
                onOpenGitDiff: ({area, relativePath, required scope}) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+12'), findsOneWidget);
    expect(find.text('-0'), findsNothing);
  });

  testWidgets('git diff panel shows relative paths in flat rows', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
          GitChangeEntry(
            path: 'test/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitBackendProvider.overrideWithValue(backend),
          settingsControllerProvider.overrideWith(
            () => _PanelSettingsController(AleraSettings.defaults),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 420,
              child: WorkspaceGitDiffPanel(
                workspace: _workspace(),
                viewMode: GitDiffViewMode.flat,
                onViewModeChanged: (_) {},
                onOpenGitDiff: ({area, relativePath, required scope}) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lib/foo.dart'), findsOneWidget);
    expect(find.text('test/foo.dart'), findsOneWidget);
    expect(find.text('foo.dart'), findsNothing);
  });

  testWidgets('stage all dispatches workspace scoped stage', (tester) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stage all'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'stage').single.args,
      <String, Object?>{'path': '/tmp/project', 'filePath': null},
    );
  });

  testWidgets('primary source control action is compact and clickable', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    final splitButton = find.ancestor(
      of: find.text('Stage all'),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 28,
      ),
    );
    expect(splitButton, findsOneWidget);
    expect(tester.getSize(splitButton).height, 28);

    final primaryAction = find.ancestor(
      of: find.text('Stage all'),
      matching: find.byType(InkWell),
    );
    expect(
      tester.widget<InkWell>(primaryAction).mouseCursor,
      SystemMouseCursors.click,
    );

    final dropdownToggle = find.ancestor(
      of: find.descendant(
        of: splitButton,
        matching: find.byIcon(AleraIcons.chevronDown),
      ),
      matching: find.byType(InkWell),
    );
    expect(
      tester.widget<InkWell>(dropdownToggle).mouseCursor,
      SystemMouseCursors.click,
    );
  });

  testWidgets('file actions stage and unstage selected paths', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stage').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unstage').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls
          .where((call) => call.method == 'stage')
          .map((call) => call.args['filePath']),
      contains('lib/new.dart'),
    );
    expect(
      backend.calls
          .where((call) => call.method == 'unstage')
          .map((call) => call.args['filePath']),
      contains('lib/staged.dart'),
    );
  });

  testWidgets('rename file actions include source and destination paths', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            oldPath: 'lib/old.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.renamed,
          ),
          GitChangeEntry(
            path: 'lib/dirty_new.dart',
            oldPath: 'lib/dirty_old.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.renamed,
          ),
          GitChangeEntry(
            path: 'lib/staged_new.dart',
            oldPath: 'lib/staged_old.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.renamed,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stage').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unstage').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Discard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls
          .where((call) => call.method == 'stage')
          .map((call) => call.args['filePath']),
      containsAllInOrder(<String>['lib/old.dart', 'lib/new.dart']),
    );
    expect(
      backend.calls
          .where((call) => call.method == 'unstage')
          .map((call) => call.args['filePath']),
      containsAllInOrder(<String>[
        'lib/staged_old.dart',
        'lib/staged_new.dart',
      ]),
    );
    expect(
      backend.calls
          .where((call) => call.method == 'discard')
          .map((call) => call.args['filePath']),
      containsAllInOrder(<String>['lib/old.dart', 'lib/new.dart']),
    );
  });

  testWidgets('discard requires confirmation before backend call', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/changed.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Discard').last);
    await tester.pumpAndSettle();
    expect(backend.calls.where((call) => call.method == 'discard'), isEmpty);

    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'discard').single.args,
      <String, Object?>{'path': '/tmp/project', 'filePath': 'lib/changed.dart'},
    );
  });

  testWidgets('failed source control actions keep current changes visible', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..pushError = const GitCliException('rejected push')
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Source control actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.text('lib/foo.dart'), findsOneWidget);

    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets('refresh stays available after initial load failure', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..statusError = const GitInternalException('index locked');

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.text('index locked'), findsOneWidget);

    expect(find.byTooltip('Refresh'), findsOneWidget);

    backend.statusError = null;
    backend.gitStatusResult = const GitStatusResult(
      entries: <GitChangeEntry>[],
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('No changes'), findsOneWidget);
    expect(
      backend.calls.where((call) => call.method == 'status').length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('stash is disabled for untracked-only changes', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Source control actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stash'));
    await tester.pumpAndSettle();

    expect(backend.calls.where((call) => call.method == 'stash'), isEmpty);
  });

  testWidgets('commit uses message and staged entries only', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.enterText(_messageField(), 'commit staged file');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'commit').single.args,
      <String, Object?>{
        'path': '/tmp/project',
        'message': 'commit staged file',
      },
    );
    final editableText = _messageEditable(tester);
    expect(editableText.controller.text, isEmpty);
  });

  testWidgets('amend opens head message and submits edited text', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
        headMessage: 'previous commit message',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Source control actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit amend'));
    await tester.pumpAndSettle();

    expect(find.text('Amend commit'), findsOneWidget);
    final amendField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == 'previous commit message',
    );
    expect(amendField, findsOneWidget);

    await tester.enterText(amendField, 'edited commit message');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amend'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'amendCommit').single.args,
      <String, Object?>{
        'path': '/tmp/project',
        'message': 'edited commit message',
      },
    );
    expect(_messageEditable(tester).controller.text, isEmpty);
  });

  testWidgets('amend is disabled without staged changes', (tester) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'main',
        upstream: 'origin/main',
        headMessage: 'previous commit message',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/unstaged.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Source control actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit amend'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'amendCommit'),
      isEmpty,
    );
    expect(find.text('Amend commit'), findsNothing);
  });

  testWidgets('failed commit keeps the typed message', (tester) async {
    final backend = FakeGitBackend()
      ..commitError = const GitInternalException('index locked')
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.enterText(_messageField(), 'commit that fails');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'commit').single.args,
      <String, Object?>{'path': '/tmp/project', 'message': 'commit that fails'},
    );
    final editableText = _messageEditable(tester);
    expect(editableText.controller.text, 'commit that fails');
  });

  testWidgets('commit message clears when workspace path changes', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(
      tester,
      backend: backend,
      workspace: _workspace(id: 'workspace-a', path: '/tmp/project-a'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_messageField(), 'message for workspace a');
    await tester.pumpAndSettle();
    expect(find.text('message for workspace a'), findsOneWidget);

    await _pumpPanel(
      tester,
      backend: backend,
      workspace: _workspace(id: 'workspace-b', path: '/tmp/project-b'),
    );
    await tester.pumpAndSettle();

    final editableText = _messageEditable(tester);
    expect(editableText.controller.text, isEmpty);
  });

  testWidgets('generated commit message is ignored after workspace changes', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final service = _FakeAiTextGenerationService();

    await _pumpPanel(
      tester,
      backend: backend,
      service: service,
      workspace: _workspace(id: 'workspace-a', path: '/tmp/project-a'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Generate commit message with AI'));
    await tester.pump();
    expect(service.requests.single.workspacePath, '/tmp/project-a');

    await _pumpPanel(
      tester,
      backend: backend,
      service: service,
      workspace: _workspace(id: 'workspace-b', path: '/tmp/project-b'),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Generate commit message with AI'));
    await tester.pump();
    expect(service.requests.last.workspacePath, '/tmp/project-b');

    service.completeAt(0, 'feat: stale message');
    await tester.pump();

    expect(find.text('Generating with AI'), findsOneWidget);
    expect(find.byTooltip('Stop generating commit message'), findsOneWidget);
    expect(find.byIcon(AleraIcons.stop), findsNothing);
    expect(tester.widget<TextField>(_messageField()).enabled, isFalse);
    expect(_messageEditable(tester).controller.text, isEmpty);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    await gesture.moveTo(
      tester.getCenter(find.byTooltip('Stop generating commit message')),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byIcon(AleraIcons.stop), findsOneWidget);
    await gesture.removePointer();

    service.completeAt(1, 'feat: workspace b message');
    await tester.pumpAndSettle();

    expect(
      _messageEditable(tester).controller.text,
      'feat: workspace b message',
    );
    expect(service.canceled, <String>[
      '/tmp/project-a::${AiTextGenerationOperation.commitMessage.key}',
    ]);
  });

  testWidgets('running commit message generation is canceled on dispose', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final service = _FakeAiTextGenerationService();

    await _pumpPanel(
      tester,
      backend: backend,
      service: service,
      workspace: _workspace(path: '/tmp/project-a'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Generate commit message with AI'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(service.canceled, <String>[
      '/tmp/project-a::${AiTextGenerationOperation.commitMessage.key}',
    ]);
  });

  testWidgets('AI commit message action is hidden when AI text is disabled', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(
      tester,
      backend: backend,
      settings: AleraSettings.defaults.copyWith(
        aiTextGeneration: AiTextGenerationSettings.defaults.copyWith(
          enabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Generate commit message with AI'), findsNothing);
  });

  test('sync without upstream fails before pull or push', () async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(branch: 'feature');
    final container = ProviderContainer(
      overrides: [gitBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);
    final provider = workspaceSourceControlControllerProvider('/tmp/project');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);

    await expectLater(
      container.read(provider.notifier).sync(),
      throwsA(isA<NoUpstreamException>()),
    );

    expect(backend.calls.where((call) => call.method == 'pull'), isEmpty);
    expect(backend.calls.where((call) => call.method == 'push'), isEmpty);
  });

  testWidgets(
    'sync is disabled without upstream while push remains available',
    (tester) async {
      final backend = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature',
        );

      await _pumpPanel(tester, backend: backend);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Source control actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      expect(backend.calls.where((call) => call.method == 'pull'), isEmpty);
      expect(backend.calls.where((call) => call.method == 'push'), isEmpty);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(backend.calls.where((call) => call.method == 'push'), isNotEmpty);
    },
  );

  testWidgets('stash pop opens selector and pops selected stash', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(entries: <GitChangeEntry>[])
      ..gitStashEntries = const <GitStashEntry>[
        GitStashEntry(
          index: 0,
          reference: 'stash@{0}',
          message: 'wip on main',
          oid: 'abc123',
        ),
      ];

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Source control actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stash pop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stash@{0}'));
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'stashPop').single.args,
      <String, Object?>{'path': '/tmp/project', 'stashIndex': 0},
    );
  });

  testWidgets('groups are ordered as staged unstaged and untracked', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/new.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
          GitChangeEntry(
            path: 'lib/dirty.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
          GitChangeEntry(
            path: 'lib/staged.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Staged')).dy,
      lessThan(tester.getTopLeft(find.text('Unstaged')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Unstaged')).dy,
      lessThan(tester.getTopLeft(find.text('Untracked')).dy),
    );
  });

  testWidgets('filter narrows visible files without flattening groups', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/visible.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
          GitChangeEntry(
            path: 'test/hidden.dart',
            area: GitChangeArea.untracked,
            status: GitChangeStatus.untracked,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(_filterField(), findsNothing);

    await tester.tap(find.byTooltip('Search files'));
    await tester.pumpAndSettle();

    await tester.enterText(_filterField(), 'visible');
    await tester.pumpAndSettle();

    expect(find.text('Unstaged'), findsOneWidget);
    expect(find.text('lib/visible.dart'), findsOneWidget);
    expect(find.text('test/hidden.dart'), findsNothing);

    await tester.tap(find.byTooltip('Hide file filter'));
    await tester.pumpAndSettle();

    expect(_filterField(), findsOneWidget);
    expect(find.text('test/hidden.dart'), findsNothing);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(_filterField(), findsNothing);
    expect(find.text('lib/visible.dart'), findsOneWidget);
    expect(find.text('test/hidden.dart'), findsOneWidget);
  });

  testWidgets('commit message field has extra top padding', (tester) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(entries: <GitChangeEntry>[]);

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    final messageField = tester.widget<TextField>(_messageField());
    expect(messageField.decoration?.suffixIcon, isNull);
    expect(
      messageField.decoration?.contentPadding,
      const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space16,
        AleraTokens.space8,
        AleraTokens.space8,
      ),
    );
  });

  testWidgets('sections and visible rows can be collapsed together', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/dirty.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.text('lib/dirty.dart'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse all'));
    await tester.pumpAndSettle();

    expect(find.text('Unstaged'), findsOneWidget);
    expect(find.text('lib/dirty.dart'), findsNothing);

    await tester.tap(find.byTooltip('Expand all'));
    await tester.pumpAndSettle();

    expect(find.text('lib/dirty.dart'), findsOneWidget);
  });

  testWidgets('section and folder actions dispatch scoped area operations', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/src/dirty.dart',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpPanel(tester, backend: backend, viewMode: GitDiffViewMode.tree);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stage').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stage').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Discard').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    expect(
      backend.calls.where((call) => call.method == 'stageArea').first.args,
      <String, Object?>{
        'path': '/tmp/project',
        'area': GitChangeArea.unstaged,
        'filePath': null,
      },
    );
    expect(
      backend.calls.where((call) => call.method == 'stageArea').last.args,
      <String, Object?>{
        'path': '/tmp/project',
        'area': GitChangeArea.unstaged,
        'filePath': 'lib/src',
      },
    );
    expect(
      backend.calls.where((call) => call.method == 'discardArea').single.args,
      <String, Object?>{
        'path': '/tmp/project',
        'area': GitChangeArea.unstaged,
        'filePath': 'lib/src',
      },
    );
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required FakeGitBackend backend,
  Workspace? workspace,
  GitDiffViewMode viewMode = GitDiffViewMode.flat,
  AiTextGenerationService? service,
  AleraSettings settings = AleraSettings.defaults,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(backend),
        settingsControllerProvider.overrideWith(
          () => _PanelSettingsController(settings),
        ),
        if (service != null)
          aiTextGenerationServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 520,
            child: WorkspaceGitDiffPanel(
              workspace: workspace ?? _workspace(),
              viewMode: viewMode,
              onViewModeChanged: (_) {},
              onOpenGitDiff: ({area, relativePath, required scope}) async {},
            ),
          ),
        ),
      ),
    ),
  );
}

class _PanelSettingsController extends SettingsController {
  _PanelSettingsController(this._settings);

  final AleraSettings _settings;

  @override
  AleraSettings build() => _settings;
}

class _FakeAiTextGenerationService implements AiTextGenerationService {
  final List<AiTextGenerationRequest> requests = <AiTextGenerationRequest>[];
  final List<String> canceled = <String>[];
  final List<Completer<AiTextGenerationResult>> _results =
      <Completer<AiTextGenerationResult>>[];

  @override
  Future<AiTextGenerationResult> generate(AiTextGenerationRequest request) {
    requests.add(request);
    final result = Completer<AiTextGenerationResult>();
    _results.add(result);
    return result.future;
  }

  @override
  void cancel(String workspacePath, AiTextGenerationOperation operation) {
    canceled.add('$workspacePath::${operation.key}');
  }

  void completeAt(int index, String text) {
    _results[index].complete(
      AiTextGenerationResult(text: text, agentLabel: 'Codex'),
    );
  }
}

Finder _messageField() {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == 'Message',
  );
}

Finder _filterField() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.hintText == 'Filter files...',
  );
}

EditableText _messageEditable(WidgetTester tester) {
  return tester.widget<EditableText>(
    find.descendant(of: _messageField(), matching: find.byType(EditableText)),
  );
}

Workspace _workspace({
  String id = 'workspace-1',
  String path = '/tmp/project',
}) {
  final now = DateTime.utc(2026, 6, 6);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: 'Main',
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}
