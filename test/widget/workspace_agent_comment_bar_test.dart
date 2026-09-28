import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/presentation/workspace_agent_comment_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists comments and removes one', (tester) async {
    var sent = false;
    var cleared = false;
    final removed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceAgentCommentDraftBar(
            comments: const <WorkspaceAgentComment>[
              WorkspaceAgentComment(
                id: 'a',
                kind: WorkspaceAgentCommentKind.file,
                path: 'lib/a.dart',
                body: 'Extract this helper.',
                lineRange: WorkspaceAgentCommentLineRange(
                  startLine: 12,
                  endLine: 18,
                ),
              ),
              WorkspaceAgentComment(
                id: 'b',
                kind: WorkspaceAgentCommentKind.diff,
                path: 'lib/b.dart',
                body: 'This looks wrong.',
                areaLabel: 'Unstaged',
              ),
            ],
            onSend: () => sent = true,
            onClear: () => cleared = true,
            onRemove: removed.add,
          ),
        ),
      ),
    );

    expect(find.text('2 Comments'), findsOneWidget);
    expect(find.text('lib/a.dart · lines 12-18'), findsOneWidget);
    expect(find.text('Extract this helper.'), findsOneWidget);
    expect(find.text('lib/b.dart · (Unstaged)'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Comment').first);
    await tester.pump();
    expect(removed, <String>['a']);

    await tester.tap(find.text('Send to Agent'));
    await tester.pump();
    expect(sent, isTrue);

    await tester.tap(find.byTooltip('Clear Comments'));
    await tester.pump();
    expect(cleared, isTrue);
  });

  for (final withProfiles in [true, false]) {
    testWidgets(
      'copies comment batch and keeps drafts (profiles: $withProfiles)',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        final now = DateTime.utc(2026, 9, 8);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsControllerProvider.overrideWith(() => _Settings()),
              agentProfilesProvider.overrideWith(
                () => _Profiles(<AgentProfile>[
                  if (withProfiles)
                    AgentProfile(
                      id: 'profile-1',
                      name: 'Codex Builder',
                      agentType: 'codex',
                      command: 'codex',
                      description: 'Implementation',
                      createdAt: now,
                      updatedAt: now,
                    ),
                ]),
              ),
            ],
            child: const _DispatchHarness(),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(_DispatchHarness)),
        );
        container
            .read(
              workspaceAgentCommentControllerProvider('workspace-1').notifier,
            )
            .add(
              const WorkspaceAgentComment(
                id: 'a',
                kind: WorkspaceAgentCommentKind.file,
                path: 'lib/a.dart',
                body: 'Extract this helper.',
                lineRange: WorkspaceAgentCommentLineRange(
                  startLine: 12,
                  endLine: 18,
                ),
                snippet: 'final value = compute();',
              ),
            );
        container
            .read(
              workspaceAgentCommentControllerProvider('workspace-1').notifier,
            )
            .add(
              const WorkspaceAgentComment(
                id: 'b',
                kind: WorkspaceAgentCommentKind.diff,
                path: 'lib/b.dart',
                body: 'This looks wrong.',
                areaLabel: 'Unstaged',
                hunkHeader: '@@ -10,6 +12,8 @@ class Bar',
              ),
            );
        await tester.pump();

        expect(find.text('2 Comments'), findsOneWidget);
        await tester.tap(find.text('Send to Agent'));
        await tester.pumpAndSettle();

        expect(find.text('Send Comments to Agent'), findsOneWidget);
        expect(
          find.text(
            'These 2 comments will be sent together. Choose a running agent or open a new tab from a profile.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Codex Builder'),
          withProfiles ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.byTooltip('Copy Prompt'));
        await tester.pumpAndSettle();
        expect(
          copied,
          'Please act on these comments in the current workspace.\n\n'
          '## 1. File `lib/a.dart` lines 12-18\n'
          '```\nfinal value = compute();\n```\n'
          'Comment:\nExtract this helper.\n\n'
          '## 2. Diff `lib/b.dart` (Unstaged) hunk `@@ -10,6 +12,8 @@ class Bar`\n'
          'Comment:\nThis looks wrong.',
        );
        expect(find.text('Send Comments to Agent'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('2 Comments'), findsOneWidget);
        expect(
          container.read(
            workspaceAgentCommentControllerProvider('workspace-1'),
          ),
          hasLength(2),
        );
      },
    );
  }
}

class const _DispatchHarness() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: WorkspaceAgentCommentDraftScope(workspaceId: 'workspace-1'),
      ),
    );
  }
}

class _Profiles(final List<AgentProfile> profiles) extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => profiles;
}

class _Settings() extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}
