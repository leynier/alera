import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/agent_profile_launch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          onLaunch: ({required prompt}) async {
            launched.add(prompt);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start Shown Codex'), findsOneWidget);
    await tester.tap(find.text('Skip'));
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
          onLaunch: ({required prompt}) async {
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

  testWidgets('pastes an image as an attachment', (tester) async {
    final clipboard = _FakeTerminalClipboard(imagePath: '/tmp/alera-paste.png');
    await tester.pumpWidget(
      MaterialApp(
        home: AgentProfileLaunchDialog(
          profile: profile,
          workspacePath: '/repo/workspace',
          clipboard: clipboard,
          onLaunch: ({required prompt}) async {},
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
}

final class _FakeTerminalClipboard({
  final String? text,
  final String? imagePath,
  final List<String> filePaths = const <String>[],
}) implements TerminalClipboard {
  @override
  Future<List<String>> readFilePaths() async => filePaths;

  @override
  Future<String?> readText() async => text;

  @override
  Future<String?> saveImageAsTempFile() async => imagePath;

  @override
  Future<void> writeText(String text) async {}
}
