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
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;
import '../unit/fake_git_backend.dart';

part 'codex_chat_surface_session_test_cases.dart';
part 'codex_chat_surface_timeline_segment_test_cases.dart';
part 'codex_chat_surface_timeline_file_change_test_cases.dart';
part 'codex_chat_surface_timeline_interaction_test_cases.dart';
part 'codex_chat_surface_timeline_review_test_cases.dart';
part 'codex_chat_surface_timeline_progress_test_cases.dart';
part 'codex_chat_surface_timeline_context_test_cases.dart';
part 'codex_chat_surface_timeline_question_answer_test_cases.dart';
part 'codex_chat_surface_foundation_test_cases.dart';
part 'codex_chat_surface_test_support.dart';
part 'codex_chat_surface_timeline_review_state_test_cases.dart';
part 'codex_chat_surface_session_state_test_cases.dart';
part 'codex_chat_surface_timeline_request_test_cases.dart';
part 'codex_chat_surface_review_dialog_test_cases.dart';
part 'codex_chat_surface_recovery_test_cases.dart';

void main() {
  _registerCodexChatSurfaceRecoveryTests();
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
    final contextIndicator = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is CircularProgressIndicator && widget.value == 0.1,
      ),
    );
    final modelConfiguration = tester.getRect(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
    );
    expect(
      composerShell.right - sendButton.right,
      lessThanOrEqualTo(AleraTokens.space12),
    );
    expect(
      modelConfiguration.left - contextIndicator.right,
      lessThanOrEqualTo(AleraTokens.space4),
    );
    expect(contextIndicator.right, lessThan(modelConfiguration.right));

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
    final type = tester.widget<Text>(find.text('Skill'));
    expect(
      overlay.right - origin.right,
      lessThanOrEqualTo(AleraTokens.space16),
    );
    expect(type.textAlign, TextAlign.right);

    await tester.enterText(
      find.byKey(const ValueKey<String>('codex-composer-text-field')),
      '/',
    );
    await tester.pumpAndSettle();

    final commandDescription = tester.widget<Text>(
      find.text('Start a new Codex chat'),
    );
    expect(commandDescription.textAlign, TextAlign.left);
  });

  registerCodexComposerFoundationTests();
  registerCodexReviewDialogTests();
}
