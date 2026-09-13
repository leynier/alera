import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/presentation/issue_url_field.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/presentation/prompt_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://github.com/leynier/alera/issues/758';

void main() {
  testWidgets('a resolved issue fills an empty prompt and is submitted', (
    tester,
  ) async {
    final requests = <PromptWorkspaceCreateRequest>[];
    await _pumpDialog(tester, requests.add);

    await tester.enterText(find.widgetWithText(TextField, 'Issue URL'), _url);
    await tester.pump(issueUrlResolveDelay);
    await tester.pumpAndSettle();

    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!
        .text;
    expect(prompt, 'Link an issue\n\nBody\n\n$_url');

    await tester.ensureVisible(find.text('Create And Start Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create And Start Agent'));
    await tester.pumpAndSettle();
    expect(requests.single.issueUrl, _url);
    expect(requests.single.prompt, prompt);
  });

  testWidgets('a typed prompt is kept when the issue resolves', (tester) async {
    await _pumpDialog(tester, (_) {});
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Only fix the tests',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Issue URL'), _url);
    await tester.pump(issueUrlResolveDelay);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
          .controller!
          .text,
      'Only fix the tests',
    );
  });
}

class _Settings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

Future<void> _pumpDialog(
  WidgetTester tester,
  void Function(PromptWorkspaceCreateRequest request) onEnqueue,
) async {
  final now = DateTime.utc(2026, 9, 12);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final profile = AgentProfile(
    id: 'profile-1',
    name: 'Codex',
    agentType: 'codex',
    command: 'codex',
    createdAt: now,
    updatedAt: now,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsControllerProvider.overrideWith(_Settings.new)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PromptWorkspaceDialog(
                  projects: <Project>[project],
                  agentProfiles: <AgentProfile>[profile],
                  loadBranches: (_) async => <String>['main'],
                  checkBranchExists: (_, _) async => false,
                  workspaceBranches: (_) => const <String>{},
                  parentWorkspaces: const <Workspace>[],
                  generateIdentity: ({
                    required operationId,
                    required projectId,
                    required prompt,
                  }) async => throw UnimplementedError(),
                  cancelGeneration: (_) async {},
                  createWorkspace: ({
                    required project,
                    required sourceBranch,
                    required newBranchName,
                    required name,
                    parentWorkspaceId,
                    hostId,
                    issueUrl,
                  }) async => throw UnimplementedError(),
                  launchAgent: ({
                    required workspaceId,
                    required profileId,
                    required prompt,
                    required clientMutationId,
                    required requireIdempotency,
                  }) async => throw UnimplementedError(),
                  supportsIdempotentAgentLaunch: () async => true,
                  fetchIssue: (_) async => const IssueDetails(
                    provider: .github,
                    url: _url,
                    number: 758,
                    title: 'Link an issue',
                    state: .open,
                    body: 'Body',
                  ),
                  enqueuePrompt: (request) {
                    onEnqueue(request);
                    return Future<void>.value();
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
