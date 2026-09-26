import 'dart:async';

import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/agent_profile_launch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10);
  final profile = AgentProfile(
    id: 'profile-1',
    name: 'Shown Codex',
    agentType: 'codex',
    command: 'codex',
    showInNewTabMenu: true,
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('skip launches the profile without a prompt', (tester) async {
    final launched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo/workspace',
          onLaunch:
              ({required prompt, resumeSessionId, clientMutationId}) async {
                launched.add(prompt);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start Shown Codex'), findsOneWidget);
    await tester.tap(find.text('Start Without Prompt'));
    await tester.pumpAndSettle();

    expect(launched, ['']);
    expect(find.byType(AgentProfileLaunchDialog), findsNothing);
  });

  testWidgets('start agent sends the prompt and attached files', (
    tester,
  ) async {
    final launched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo/workspace',
          pickFiles: () async => <String>['/repo/workspace/lib/main.dart'],
          onLaunch:
              ({required prompt, resumeSessionId, clientMutationId}) async {
                launched.add(prompt);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Review the composer',
    );
    await tester.pump();
    await tester.tap(find.text('Add Files'));
    await tester.pump();
    expect(find.text('main.dart'), findsOneWidget);

    await tester.tap(find.text('Start Agent'));
    await tester.pumpAndSettle();

    expect(launched, ['Review the composer\n\nAttached files:\nlib/main.dart']);
  });

  testWidgets('Control+Enter starts the agent from the prompt field', (
    tester,
  ) async {
    final launched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo/workspace',
          onLaunch:
              ({required prompt, resumeSessionId, clientMutationId}) async {
                launched.add(prompt);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Review the composer',
    );
    await tester.pump();
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyEvent(.enter);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(launched, ['Review the composer']);
    expect(find.byType(AgentProfileLaunchDialog), findsNothing);
  });

  testWidgets('empty Control+Enter explains how to start without a prompt', (
    tester,
  ) async {
    var launched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo',
          onLaunch:
              ({required prompt, resumeSessionId, clientMutationId}) async {
                launched = true;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Initial Prompt'));
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyEvent(.enter);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(launched, isFalse);
    expect(
      find.text('Write a prompt, attach files, or start without a prompt.'),
      findsOneWidget,
    );
    expect(find.text('Start Without Prompt'), findsOneWidget);
  });

  testWidgets('pastes an image as an attachment', (tester) async {
    final clipboard = _FakeTerminalClipboard(imagePath: '/tmp/alera-paste.png');
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo/workspace',
          clipboard: clipboard,
          onLaunch: ({
            required prompt,
            resumeSessionId,
            clientMutationId,
          }) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final promptField = find.widgetWithText(TextField, 'Initial Prompt');
    await tester.tap(promptField);
    await tester.pump();
    final focusContext = tester.binding.focusManager.primaryFocus?.context;
    expect(focusContext, isNotNull);
    Actions.invoke(focusContext!, const PasteTextIntent(.keyboard));
    await tester.pump();
    await tester.pump();

    expect(find.text('alera-paste.png'), findsOneWidget);
  });

  testWidgets('resume keeps drafts and retries the same bound launch', (
    tester,
  ) async {
    final attempts = <({String prompt, String? session, String? mutation})>[];
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo',
          supportsResume: () async => true,
          onLaunch:
              ({required prompt, resumeSessionId, clientMutationId}) async {
                attempts.add((
                  prompt: prompt,
                  session: resumeSessionId,
                  mutation: clientMutationId,
                ));
                if (attempts.length == 1) throw StateError('Resume failed');
                await pending.future;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Keep this draft',
    );
    await tester.tap(find.text('Resume Session'));
    await tester.pumpAndSettle();
    expect(find.text('Initial Prompt'), findsNothing);
    expect(find.text('Add Files'), findsNothing);
    final session = find.widgetWithText(TextField, 'Session ID');
    expect(tester.widget<TextField>(session).focusNode!.hasFocus, isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(session, '--last');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(session, '  sess-123  ');
    await tester.tap(find.text('New Session'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this draft'), findsOneWidget);
    await tester.tap(find.text('Resume Session'));
    await tester.pumpAndSettle();
    expect(find.text('  sess-123  '), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume Session'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Resume failed'), findsOneWidget);
    expect(attempts.single.prompt, isEmpty);
    expect(attempts.single.session, 'sess-123');
    expect(attempts.single.mutation, isNotEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Resume Session'));
    await tester.pump();
    expect(find.text('Resuming session…'), findsOneWidget);
    expect(attempts.length, 2);
    expect(attempts.last.mutation, attempts.first.mutation);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AgentProfileLaunchDialog), findsNothing);
  });

  testWidgets(
    'an old runtime disables resume while new sessions remain available',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AgentProfileLaunchDialog(
            profile: profile,
            workspacePath: '/repo',
            supportsResume: () async => false,
            onLaunch: ({
              required prompt,
              resumeSessionId,
              clientMutationId,
            }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(control.segments.last.enabled, isFalse);
      expect(find.text('Start Without Prompt'), findsOneWidget);
    },
  );

  for (final outcome in ['supported', 'unsupported', 'failed']) {
    testWidgets('resume waits for the capability check: $outcome', (
      tester,
    ) async {
      final support = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: AgentProfileLaunchDialog(
            profile: profile,
            workspacePath: '/repo',
            supportsResume: () => support.future,
            onLaunch: ({
              required prompt,
              resumeSessionId,
              clientMutationId,
            }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final unavailable = find.text(
        'Session resume is unavailable for this runtime or agent.',
      );
      final control = find.byType(SegmentedButton<bool>);
      expect(
        tester.widget<SegmentedButton<bool>>(control).segments.last.enabled,
        isFalse,
      );
      expect(unavailable, findsNothing);
      await tester.tap(find.text('Resume Session'));
      await tester.pumpAndSettle();
      expect(find.text('Session ID'), findsNothing);
      expect(find.text('Start Without Prompt'), findsOneWidget);

      if (outcome == 'failed') {
        support.completeError(StateError('Runtime unavailable'));
      } else {
        support.complete(outcome == 'supported');
      }
      await tester.pumpAndSettle();

      final supported = outcome == 'supported';
      expect(
        tester.widget<SegmentedButton<bool>>(control).segments.last.enabled,
        supported,
      );
      expect(unavailable, supported ? findsNothing : findsOneWidget);
      await tester.tap(find.text('Resume Session'));
      await tester.pumpAndSettle();
      expect(
        find.text('Session ID'),
        supported ? findsOneWidget : findsNothing,
      );
    });
  }
}

final class _FakeTerminalClipboard({final String? imagePath})
    implements TerminalClipboard {
  @override
  Future<List<String>> readFilePaths() async => const <String>[];

  @override
  Future<String?> readText() async => null;

  @override
  Future<String?> saveImageAsTempFile() async => imagePath;

  @override
  Future<void> writeText(String text) async {}
}
