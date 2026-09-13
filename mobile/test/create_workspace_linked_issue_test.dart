import 'package:alera_mobile/src/app/app_navigation.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_issue_url_field.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

const _url = 'https://github.com/leynier/alera/issues/758';

class _FakeLinkedIssues extends LinkedIssuesController {
  @override
  Future<MobileLinkedIssueSnapshot> build(String hostId) async =>
      const MobileLinkedIssueSnapshot(supported: true);

  @override
  Future<MobileIssueDetails> fetch(String url) async =>
      const MobileIssueDetails(
        url: _url,
        number: 758,
        title: 'Link an issue',
        state: 'open',
        body: 'Body',
      );
}

Future<FakeTerminalClient> _pump(
  WidgetTester tester, {
  required bool supportsLinkedIssues,
}) async {
  final client = FakeTerminalClient()..projectBranches = const <String>['main'];
  addTearDown(client.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        linkedIssuesControllerProvider('host-1')
            .overrideWith(_FakeLinkedIssues.new),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
      ],
      child: MaterialApp(
        navigatorKey: aleraNavigatorKey,
        home: CreateWorkspaceScreen(
          hostId: 'host-1',
          projects: const <ProjectSummary>[
            ProjectSummary(
              id: 'project-1',
              name: 'Alera',
              repoPath: '/repo/alera',
            ),
          ],
          workspaces: const [],
          supportsLinkedIssues: supportsLinkedIssues,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

String _text(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  testWidgets('a resolved issue fills the manual branch and name', (
    tester,
  ) async {
    await _pump(tester, supportsLinkedIssues: true);
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(MobileIssueUrlField), _url);
    await tester.pump(mobileIssueUrlResolveDelay);
    await tester.pumpAndSettle();
    expect(_text(tester, 'Branch Name'), '758-link-an-issue');
    expect(_text(tester, 'Display Name (Optional)'), 'Link an issue');

    await tester.enterText(
      find.widgetWithText(TextField, 'Branch Name'),
      'mine',
    );
    await tester.enterText(find.byType(MobileIssueUrlField), '$_url#top');
    await tester.pump(mobileIssueUrlResolveDelay);
    await tester.pumpAndSettle();
    expect(_text(tester, 'Branch Name'), 'mine');
  });

  testWidgets('a resolved issue fills an empty prompt', (tester) async {
    await _pump(tester, supportsLinkedIssues: true);
    await tester.enterText(find.byType(MobileIssueUrlField), _url);
    await tester.pump(mobileIssueUrlResolveDelay);
    await tester.pumpAndSettle();
    expect(_text(tester, 'Initial Prompt'), 'Link an issue\n\nBody\n\n$_url');
  });

  testWidgets('the issue field is hidden without host support', (tester) async {
    await _pump(tester, supportsLinkedIssues: false);
    expect(find.byType(MobileIssueUrlField), findsNothing);
  });
}
