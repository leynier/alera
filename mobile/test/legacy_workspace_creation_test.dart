import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('Legacy hosts default both creation modes to a linked worktree', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..supportsSharedCheckoutWorkspaces = false
      ..projectBranches = ['main'];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host').overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: CreateWorkspaceScreen(
            hostId: 'host',
            projects: [
              ProjectSummary(id: 'project', name: 'Project', repoPath: '/repo'),
            ],
            workspaces: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final mode in ['Manual', 'From Prompt']) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      final selector = tester
          .widgetList<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .firstWhere(
            (widget) => widget.segments.any(
              (segment) =>
                  segment.label is Text &&
                  (segment.label as Text).data == 'Project Folder',
            ),
          );
      expect(selector.selected, {false});
      expect(
        selector.segments.firstWhere((segment) => segment.value).enabled,
        isFalse,
      );
      expect(
        selector.segments.firstWhere((segment) => !segment.value).enabled,
        isTrue,
      );
      expect(
        find.text(
          'Update Alera on this host to create tasks in the project folder.',
        ),
        findsOneWidget,
      );
    }
    expect(
      client.calls.where((call) => call.startsWith('createSharedWorkspace')),
      isEmpty,
    );
  });

  test('Legacy shared prompt fails before generating an identity', () async {
    final client = FakeTerminalClient()
      ..supportsSharedCheckoutWorkspaces = false;
    addTearDown(client.dispose);
    await expectLater(
      runPromptWorkspaceCreate(
        client: client,
        loadTerminalClient: () async => client,
        clientMutationId: 'legacy-test',
        request: const PromptWorkspaceCreateRequest(
          hostId: 'host',
          prompt: 'Task',
          projectId: 'project',
          sourceBranch: 'main',
          profileId: 'profile-1',
          workspaceBranches: {},
          useProjectCheckout: true,
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      client.calls.where(
        (call) =>
            call.startsWith('generateWorkspaceIdentity') ||
            call.startsWith('createSharedWorkspace'),
      ),
      isEmpty,
    );
  });
}
