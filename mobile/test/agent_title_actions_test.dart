import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';
import 'support/fake_terminal_client.dart';

void main() {
  for (final kind in ['terminal', 'codex']) {
    for (final mode in [
      'unsupported',
      'generate',
      'regenerate',
      'busy',
      'error',
    ]) {
      testWidgets('$kind title action handles $mode', (tester) async {
        final client = _TitleClient()
          ..supportsAgentTitles = mode != 'unsupported'
          ..failGeneration = mode == 'error'
          ..tabs = [
            WorkspaceTabSummary(
              id: 'tab',
              workspaceId: 'workspace-1',
              kind: kind,
              title: 'Agent Task',
              payload: {
                'terminalSessionId': 'session-tab',
                if (mode == 'regenerate') 'agentTitleSource': 'generated',
                if (mode == 'busy') 'agentTitleStatus': 'generating',
              },
            ),
          ];
        final codex = FakeMobileCodexClient();
        addTearDown(client.dispose);
        addTearDown(codex.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              terminalClientProvider('host')
                  .overrideWith((ref) async => client),
              workspaceClientProvider('host')
                  .overrideWith((ref) async => client),
              mobileCodexClientProvider('host')
                  .overrideWith((ref) async => codex),
            ],
            child: const MaterialApp(
              home: WorkspaceTabsScreen(
                hostId: 'host',
                workspace: WorkspaceSummary(
                  id: 'workspace-1',
                  projectId: 'project',
                  name: 'Workspace',
                  path: '/repo',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Agent Task'));
        await tester.pumpAndSettle();
        final label = mode == 'busy'
            ? 'Generating title...'
            : mode == 'regenerate'
            ? 'Regenerate Title'
            : 'Generate Title';
        expect(
          find.text(label),
          mode == 'unsupported' ? findsNothing : findsOneWidget,
        );
        if (mode == 'busy') {
          expect(find.byTooltip('Generating title...'), findsOneWidget);
          expect(
            tester
                .widget<ListTile>(
                  find.ancestor(
                    of: find.text(label),
                    matching: find.byType(ListTile),
                  ),
                )
                .enabled,
            isFalse,
          );
        } else if (mode != 'unsupported') {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(client.calls, contains('generateTitle:tab'));
          expect(find.text('Agent Task'), findsOneWidget);
          if (mode == 'error') {
            expect(
              find.textContaining('Could not generate title:'),
              findsOneWidget,
            );
          }
        }
      });
    }
  }
}

class _TitleClient extends FakeTerminalClient
    implements MobileAgentTitleClient {
  @override
  bool supportsAgentTitles = true;
  bool failGeneration = false;
  @override
  Future<void> generateAgentTitle(WorkspaceTabSummary tab) async {
    calls.add('generateTitle:${tab.id}');
    if (failGeneration) throw StateError('Provider unavailable');
  }
}
