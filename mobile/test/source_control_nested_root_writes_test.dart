import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_explorer_preferences_repository.dart';
import 'support/source_control_fixtures.dart';

void main() {
  testWidgets(
    'a nested source control root hides writes including File Actions',
    (tester) async {
      final client =
          sourceControlClient(
              writableSnapshot(entries: <MobileGitChange>[unstagedChange()]),
            )
            ..sourceControlRootSupported = true
            ..gitRepositoryRoots = const <String>{'service'};
      addTearDown(client.dispose);
      final preferences = MemoryExplorerPreferencesRepository()
        ..saved['host-1/workspace-1'] = const ExplorerPreferences(
          sourceControlRoot: 'service',
        );

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceClientProvider('host-1')
                .overrideWith((ref) async => client),
            explorerPreferencesRepositoryProvider.overrideWith(
              (ref) => preferences,
            ),
          ],
          child: MaterialApp(
            theme: buildAleraMobileDarkTheme(),
            home: const Scaffold(
              body: SourceControlPanel(
                hostId: 'host-1',
                workspaceId: 'workspace-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Source control root: service'), findsOneWidget);
      expect(
        find.text(
          'Clear the nested source control root to stage and commit from mobile.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Stage'), findsNothing);
      expect(find.byTooltip('Source Control Actions'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Fetch'), findsNothing);

      await tester.tap(find.text('main.dart'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('File Actions'), findsNothing);
      expect(client.gitWrites, isEmpty);
    },
  );
}
