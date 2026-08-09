import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/application/codex_composer_draft_store.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:alera/src/features/codex_chat/presentation/codex_chat_surface.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;

part 'codex_chat_surface_session_test_cases.dart';
part 'codex_chat_surface_timeline_segment_test_cases.dart';
part 'codex_chat_surface_timeline_review_test_cases.dart';
part 'codex_chat_surface_timeline_progress_test_cases.dart';
part 'codex_chat_surface_timeline_context_test_cases.dart';
part 'codex_chat_surface_timeline_question_answer_test_cases.dart';

void main() {
  test('allows only standard external URI schemes', () {
    for (final value in <String>[
      'https://example.com/path',
      'http://example.com/path',
      'mailto:user@example.com',
      'tel:+1234',
      'sms:+1234',
    ]) {
      expect(codexShouldLaunchExternalUri(value, Uri.parse(value)), isTrue);
    }
    for (final value in <String>[
      'file:///repo/readme.md',
      'vscode://file/repo/readme.md',
      'custom-handler://run/action',
      r'C:\repo\readme.md',
    ]) {
      expect(codexShouldLaunchExternalUri(value, Uri.parse(value)), isFalse);
    }
  });

  test('resolves compact Markdown file line references', () {
    final target = resolveCodexMarkdownFileTarget(
      workspacePath: '/repo/workspace',
      rawLink: 'readme.md:44',
    );

    expect(target?.path, p.join('/repo/workspace', 'readme.md'));
    expect(target?.line, 44);
  });

  testWidgets('Markdown links expose a click cursor', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GptMarkdown('[**README**](https://example.com)')),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 11,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final formattedLink = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('README'),
    );
    expect(formattedLink, findsOneWidget);
    await mouse.moveTo(tester.getCenter(formattedLink));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
    expect(
      _containsBoldSpan(tester.widget<RichText>(formattedLink).text),
      isTrue,
    );
  });

  test('resolves extensionless compact Markdown file line references', () {
    final target = resolveCodexMarkdownFileTarget(
      workspacePath: '/repo/workspace',
      rawLink: 'Makefile:42',
    );

    expect(target?.path, p.join('/repo/workspace', 'Makefile'));
    expect(target?.line, 42);
  });

  test('decodes compact Markdown file line references', () {
    final target = resolveCodexMarkdownFileTarget(
      workspacePath: '/repo/workspace',
      rawLink: 'release%20notes.md:44',
    );

    expect(target?.path, p.join('/repo/workspace', 'release notes.md'));
    expect(target?.line, 44);
  });

  test(
    'resolves fragmented file URIs without passing the fragment to Dart',
    () {
      final filePath = Platform.isWindows
          ? r'C:\repo\workspace\readme.md'
          : '/repo/workspace/readme.md';
      final uri = Uri.file(
        filePath,
        windows: Platform.isWindows,
      ).replace(fragment: 'L42');

      final target = resolveCodexMarkdownFileTarget(
        workspacePath: Platform.isWindows
            ? r'C:\repo\workspace'
            : '/repo/workspace',
        rawLink: uri.toString(),
      );

      expect(target?.path, filePath);
      expect(target?.line, 42);
    },
  );

  testWidgets('renders rich timeline cells and structured approval controls', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Answer from Codex'), findsOneWidget);
    expect(find.text('Thinking'), findsNothing);
    expect(find.textContaining('Current Codex'), findsOneWidget);
    expect(find.text('Ask For Approval'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsWidgets);
    expect(find.text('dart'), findsOneWidget);
    expect(find.textContaining('void main'), findsOneWidget);
    expect(find.text('Implement Plan'), findsNothing);

    final timeline = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('File changes'),
      200,
      scrollable: timeline,
    );
    await tester.tap(find.text('File changes'));
    await tester.pump();
    expect(find.text('@@ -1 +1 @@'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Allow For Session'),
      200,
      scrollable: timeline,
    );
    expect(find.text('Allow For Session'), findsOneWidget);

    final contextIndicator = find.byWidgetPredicate(
      (widget) => widget is CircularProgressIndicator && widget.value == 0.1,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(contextIndicator));
    await tester.pump();
    expect(find.text('Context Window'), findsOneWidget);
  });

  testWidgets('keeps history visible while offering rollout recovery', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      recovery: const <String, Object?>{
        'kind': 'missingRollout',
        'message': 'The saved Codex context is no longer available.',
      },
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.textContaining('Answer from Codex'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-thread-recovery')),
      findsOneWidget,
    );
    expect(find.text('Continue In New Thread'), findsOneWidget);
    final composer = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('codex-composer-text-field')),
    );
    expect(composer.enabled, isFalse);

    await tester.tap(find.text('Continue In New Thread'));
    await tester.pump();
    expect(client.recoveryRequests, 1);
  });

  testWidgets('offers cancel turn for legacy approval requests', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(approvalMethod: 'execCommandApproval');
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final timeline = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Cancel Turn'),
      200,
      scrollable: timeline,
    );
    expect(find.text('Cancel Turn'), findsOneWidget);
  });

  testWidgets('resolves file mentions from the resumed thread cwd', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(activeCwd: '/repo/resumed-workspace');
    final workspaceFiles = _RecordingWorkspaceFileService();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
          workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    await tester.enterText(find.byType(TextField).last, '@readme');
    await tester.pump(const Duration(milliseconds: 250));

    expect(workspaceFiles.startedWorkspacePath, '/repo/resumed-workspace');
    expect(
      workspaceFiles.savedPromptWorkspacePaths.last,
      '/repo/resumed-workspace',
    );
  });

  testWidgets('opens the combined model configuration menu', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      collaborationModes: const <Map<String, Object?>>[
        <String, Object?>{'mode': 'default'},
        <String, Object?>{'mode': 'plan'},
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);

    final composerShell = tester.getRect(
      find.byKey(const ValueKey<String>('codex-composer-shell')),
    );
    final sendButton = tester.getRect(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    expect(
      composerShell.right - sendButton.right,
      lessThanOrEqualTo(AleraTokens.space12),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Mode'), findsNothing);
  });

  testWidgets('long model labels remain responsive in a narrow pane', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      modelDisplayName: 'GPT-5.6-Sol-With-An-Intentionally-Long-Display-Name',
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, width: 320);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
      findsOneWidget,
    );
  });

  testWidgets('keeps non-plan collaboration modes in advanced configuration', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      collaborationModes: const <Map<String, Object?>>[
        <String, Object?>{'mode': 'default'},
        <String, Object?>{'mode': 'plan'},
        <String, Object?>{'mode': 'pair'},
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);

    await tester.tap(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mode'), findsOneWidget);
    await tester.tap(find.text('Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsNWidgets(2));
    expect(find.text('Pair'), findsOneWidget);
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(find.text('Pair'), findsOneWidget);
  });

  testWidgets('adds dropped workspace paths as file attachments', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);

    final target = tester.widget<DragTarget<TerminalPathDragPayload>>(
      find.byType(DragTarget<TerminalPathDragPayload>),
    );
    target.onAcceptWithDetails!(
      DragTargetDetails<TerminalPathDragPayload>(
        data: const TerminalPathDragData(paths: <String>['/tmp/notes.md']),
        offset: Offset.zero,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('codex-attached-file-/tmp/notes.md')),
      findsOneWidget,
    );
    expect(find.byType(AleraFileIcon), findsWidgets);
  });

  testWidgets('aligns catalog origins to the overlay edge', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      skills: const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'name': 'Agent Canvas',
            'path': '/skills/agent-canvas',
            'description': 'Publish structured canvas updates.',
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);

    await tester.enterText(
      find.byKey(const ValueKey<String>('codex-composer-text-field')),
      r'$',
    );
    await tester.pumpAndSettle();

    final overlay = tester.getRect(
      find.byKey(const ValueKey<String>('codex-composer-overlay-scroll')),
    );
    final origin = tester.getRect(find.text('Personal'));
    expect(
      overlay.right - origin.right,
      lessThanOrEqualTo(AleraTokens.space16),
    );
  });

  testWidgets('an immediately sent dropped path stays with that prompt', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'Inspect this file');
    await tester.pump();

    final target = tester.widget<DragTarget<TerminalPathDragPayload>>(
      find.byType(DragTarget<TerminalPathDragPayload>),
    );
    target.onAcceptWithDetails!(
      DragTargetDetails<TerminalPathDragPayload>(
        data: const TerminalPathDragData(paths: <String>['/tmp/notes.md']),
        offset: Offset.zero,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(client.startTurnPayloads, hasLength(1));
    final input = client.startTurnPayloads.single['input']! as List<Object?>;
    expect(
      input.whereType<Map>().any(
        (part) => part['text']?.toString().contains('/tmp/notes.md') == true,
      ),
      isTrue,
    );
  });

  test('classifies local directories for dropped attachments', () async {
    final directory = await Directory.systemTemp.createTemp(
      'alera-codex-directory-attachment-',
    );
    addTearDown(() => directory.delete(recursive: true));

    expect(await codexAttachmentPathIsDirectory(directory.path), isTrue);
  });

  test('arrow up preserves drafts that can be soft wrapped', () {
    const draft =
        'This draft is intentionally long enough to wrap across several visual lines in a narrow composer.';
    expect(
      codexCanNavigatePromptHistory(
        key: LogicalKeyboardKey.arrowUp,
        value: const TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        ),
        browsingHistory: false,
      ),
      isFalse,
    );
    expect(
      codexCanNavigatePromptHistory(
        key: LogicalKeyboardKey.arrowUp,
        value: const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        ),
        browsingHistory: false,
      ),
      isTrue,
    );
  });

  testWidgets('stale mention results do not add an attachment', (tester) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenMatches: const <native.WorkspaceQuickOpenMatch>[
        native.WorkspaceQuickOpenMatch(
          relativePath: 'assets/logo.png',
          score: 0,
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@logo');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('assets/logo.png'), findsOneWidget);

    await tester.enterText(composer, 'different text');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('codex-composer-file-bar')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(composer).controller?.text,
      'different text',
    );
  });

  testWidgets('catalog input invalidates an in-flight mention search', (
    tester,
  ) async {
    final search = Completer<List<native.WorkspaceQuickOpenMatch>>();
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenSearch: search,
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@logo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(composer, r'$');
    await tester.pump(const Duration(milliseconds: 250));

    search.complete(const <native.WorkspaceQuickOpenMatch>[
      native.WorkspaceQuickOpenMatch(
        relativePath: 'assets/stale.png',
        score: 0,
      ),
    ]);
    await tester.pump();

    expect(find.text('assets/stale.png'), findsNothing);
  });

  testWidgets('skill removal targets the selected token occurrence', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      skills: const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'name': 'review',
            'path': '/skills/review/SKILL.md',
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, r'$review before $rev');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('review'));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      r'$review before $review ',
    );
    await tester.enterText(composer, r'$review before $review $rev');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('review'));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      r'$review before $review ',
    );
    await tester.tap(find.byIcon(AleraIcons.close));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      r'$review before ',
    );
  });

  testWidgets('removing an image mention also removes its composer token', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenMatches: const <native.WorkspaceQuickOpenMatch>[
        native.WorkspaceQuickOpenMatch(
          relativePath: 'assets/logo.png',
          score: 0,
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@logo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('assets/logo.png'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    const attachmentKey = ValueKey<String>(
      'codex-attached-file-/repo/workspace/assets/logo.png',
    );
    expect(find.byKey(attachmentKey), findsOneWidget);
    expect(
      tester.widget<TextField>(composer).controller?.text,
      'assets/logo.png ',
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(attachmentKey),
        matching: find.byIcon(AleraIcons.close),
      ),
    );
    await tester.pump();

    expect(find.byKey(attachmentKey), findsNothing);
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
  });

  testWidgets('selecting an existing mention still resolves its query', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenMatches: const <native.WorkspaceQuickOpenMatch>[
        native.WorkspaceQuickOpenMatch(relativePath: 'readme.md', score: 0),
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@read');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller?.text, 'readme.md ');

    await tester.enterText(composer, 'readme.md @read');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller?.text, 'readme.md ');
    expect(
      find.byKey(
        const ValueKey<String>('codex-mentioned-file-mention-readme.md'),
      ),
      findsOneWidget,
    );
  });

  registerCodexTimelineSegmentTests();
  registerCodexTimelineReviewTests();
  registerCodexTimelineProgressTests();
  registerCodexTimelineContextTests();
  registerCodexTimelineQuestionAnswerTests();
  registerCodexChatSurfaceSessionTests();
}

Future<void> _pumpComposerSurface(
  WidgetTester tester,
  _SurfaceRuntimeClient client, {
  WorkspaceFileService? workspaceFiles,
  double width = 1000,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        if (workspaceFiles != null)
          workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 800,
            child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
}

Workspace _workspace() {
  final now = DateTime.utc(2026);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Workspace',
    path: '/repo/workspace',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab({
  String id = 'codex-tab',
  String workspaceId = 'workspace-1',
}) {
  final now = DateTime.utc(2026);
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: WorkspaceTabKind.codex,
    title: 'Codex',
    createdAt: now,
    updatedAt: now,
  );
}

final class _SurfaceRuntimeClient implements RuntimeHostClient {
  _SurfaceRuntimeClient({
    this.recovery,
    this.approvalMethod = 'item/commandExecution/requestApproval',
    this.activeCwd,
    this.supportsSessions = false,
    this.supportsTurnPolicy = true,
    this.historyNextCursor,
    this.historyTimelineCells = const <Object?>[],
    this.historyGate,
    this.pendingRequests,
    this.threadListResponse,
    this.permissionMode,
    this.timelineCells,
    this.activeTurnId,
    this.modelDisplayName = 'Current Codex',
    this.skills = const <String, Object?>{'data': <Object?>[]},
    this.collaborationModes = const <Map<String, Object?>>[
      <String, Object?>{'mode': 'plan'},
    ],
  });

  final Map<String, Object?>? recovery;
  final String approvalMethod;
  final String? activeCwd;
  final bool supportsSessions;
  final bool supportsTurnPolicy;
  final String? historyNextCursor;
  final List<Object?> historyTimelineCells;
  final Completer<void>? historyGate;
  final List<Object?>? pendingRequests;
  final Map<String, Object?>? threadListResponse;
  final String? permissionMode;
  final List<Object?>? timelineCells;
  final String? activeTurnId;
  final String modelDisplayName;
  final Map<String, Object?> skills;
  final List<Map<String, Object?>> collaborationModes;
  final List<String> requestTypes = <String>[];
  final List<Map<String, Object?>> startTurnPayloads = <Map<String, Object?>>[];
  final List<Map<String, Object?>> responsePayloads = <Map<String, Object?>>[];
  int recoveryRequests = 0;
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requestTypes.add(type);
    if (type == 'status.get') {
      return <String, Object?>{
        'runtimeCapabilities': <String>[
          if (supportsSessions) aleraRuntimeHostCodexSessionsCapability,
          if (supportsTurnPolicy) aleraRuntimeHostCodexTurnPolicyCapability,
        ],
      };
    }
    if (type == 'codex.thread.open') {
      return <String, Object?>{
        'threadId': supportsSessions
            ? 'thread-current'
            : recovery == null
            ? null
            : 'thread-recovery',
        'cwd': activeCwd,
        'historyNextCursor': historyNextCursor,
        if (permissionMode != null)
          'configuration': <String, Object?>{
            'selectedModel': 'gpt-current',
            'reasoningEffort': 'medium',
            'speedMode': 'normal',
            'permissionMode': permissionMode,
            'planMode': false,
            'collaborationMode': null,
          },
        'recovery': recovery,
        'snapshot': <String, Object?>{
          'timelineCells':
              timelineCells ??
              <Object?>[
                <String, Object?>{
                  'id': 'request',
                  'kind': 'userMessage',
                  'status': 'completed',
                  'createdAt': '2026-08-02T11:59:00Z',
                  'updatedAt': '2026-08-02T11:59:00Z',
                  'markdownText': 'Inspect the workspace',
                },
                <String, Object?>{
                  'id': 'answer',
                  'kind': 'assistantMessage',
                  'status': 'completed',
                  'createdAt': '2026-08-02T12:00:00Z',
                  'updatedAt': '2026-08-02T12:00:00Z',
                  'markdownText':
                      'Answer from Codex\n\n![Malformed](data:not-valid)\n\n```dart\nvoid main() {}\n```',
                },
                <String, Object?>{
                  'id': 'reasoning',
                  'kind': 'reasoning',
                  'status': 'completed',
                  'createdAt': '2026-08-02T12:00:00Z',
                  'updatedAt': '2026-08-02T12:00:00Z',
                  'markdownText': 'Reasoning',
                },
                <String, Object?>{
                  'id': 'diff',
                  'kind': 'diff',
                  'status': 'completed',
                  'createdAt': '2026-08-02T12:00:00Z',
                  'updatedAt': '2026-08-02T12:00:00Z',
                  'title': 'File changes',
                  'detailsText': 'diff --git a/a b/a\n@@ -1 +1 @@\n-old\n+new',
                },
                <String, Object?>{
                  'id': 'plan',
                  'kind': 'plan',
                  'status': 'completed',
                  'createdAt': '2026-08-02T12:00:00Z',
                  'updatedAt': '2026-08-02T12:00:00Z',
                  'markdownText': '1. Inspect\n2. Implement',
                },
              ],
          'contextUsed': 1000,
          'contextLimit': 10000,
          'activeTurnId': activeTurnId,
          'pendingRequests':
              pendingRequests ??
              <Object?>[
                <String, Object?>{
                  'id': 1,
                  'method': approvalMethod,
                  'params': <String, Object?>{
                    'command': 'git status',
                    'reason': 'Read the workspace',
                  },
                },
              ],
        },
      };
    }
    if (type == 'codex.thread.list') {
      return threadListResponse ?? const <String, Object?>{'data': <Object?>[]};
    }
    if (type == 'codex.thread.resume' ||
        type == 'codex.thread.new' ||
        type == 'codex.thread.clear') {
      return <String, Object?>{
        'threadId': type == 'codex.thread.resume'
            ? 'thread-resumed'
            : 'thread-fresh',
        'cwd': activeCwd ?? '/repo/workspace',
        'snapshot': const <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
        },
      };
    }
    if (type == 'codex.thread.history') {
      await historyGate?.future;
      return <String, Object?>{
        'snapshot': <String, Object?>{
          'timelineCells': historyTimelineCells,
          'pendingRequests': const <Object?>[],
        },
      };
    }
    if (type == 'codex.thread.recover') {
      recoveryRequests += 1;
      return <String, Object?>{
        'threadId': null,
        'snapshot': <String, Object?>{
          'timelineCells': const <Object?>[],
          'pendingRequests': const <Object?>[],
        },
      };
    }
    if (type == 'codex.turn.start') {
      startTurnPayloads.add(payload);
      return const <String, Object?>{};
    }
    if (type == 'codex.response') {
      responsePayloads.add(payload);
      return const <String, Object?>{};
    }
    if (type == 'codex.model.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-current',
            'displayName': modelDisplayName,
            'isDefault': true,
            'supportsFastMode': true,
          },
        ],
      };
    }
    if (type == 'codex.collaborationModes.list') {
      return <String, Object?>{'data': collaborationModes};
    }
    if (type == 'codex.skills.list') return skills;
    return <String, Object?>{'data': const <Object?>[]};
  }

  void dispose() => _events.close();

  void emit(RuntimeHostEvent event) => _events.add(event);
}

final class _SurfaceSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

final class _RecordingWorkspaceFileService extends WorkspaceFileService {
  _RecordingWorkspaceFileService({
    this.quickOpenMatches = const <native.WorkspaceQuickOpenMatch>[],
    this.quickOpenSearch,
    this.savedPrompts = const <native.CodexSavedPrompt>[],
  });

  final List<native.WorkspaceQuickOpenMatch> quickOpenMatches;
  final Completer<List<native.WorkspaceQuickOpenMatch>>? quickOpenSearch;
  final List<native.CodexSavedPrompt> savedPrompts;
  String? startedWorkspacePath;
  final List<String> savedPromptWorkspacePaths = <String>[];

  @override
  Future<List<native.CodexSavedPrompt>> listCodexSavedPrompts({
    required String workspacePath,
  }) async {
    savedPromptWorkspacePaths.add(workspacePath);
    return savedPrompts;
  }

  @override
  Future<native.WorkspaceQuickOpenSession> startQuickOpenSession({
    required String workspacePath,
  }) async {
    startedWorkspacePath = workspacePath;
    return const native.WorkspaceQuickOpenSession(
      id: 'quick-open-session',
      indexedFileCount: 1,
    );
  }

  @override
  Future<List<native.WorkspaceQuickOpenMatch>> searchQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
    required String query,
    int limit = 50,
  }) async => quickOpenSearch?.future ?? quickOpenMatches;

  @override
  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  }) async {}
}
