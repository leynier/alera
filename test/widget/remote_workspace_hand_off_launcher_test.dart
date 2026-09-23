import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workbench_hand_off_launchers.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SSH Hand Off never resolves its path through local Git', (
    tester,
  ) async {
    var localGitReads = 0;
    final now = DateTime.utc(2026);
    final workspace = Workspace(
      id: 'remote-task',
      instanceId: 'remote-instance',
      projectId: 'project',
      name: 'Remote Task',
      path: r'C:\owner\repository',
      branch: 'remote-topic',
      hostId: 'ssh-fixture',
      createdAt: now,
      updatedAt: now,
      kind: .main,
      status: .active,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitBackendProvider.overrideWith((ref) {
            localGitReads++;
            throw StateError('A remote path must not reach local Git');
          }),
        ],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showHandOffWorkspaceFlow(context, ref, workspace: workspace),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Last recorded remote branch: remote-topic'),
      findsOneWidget,
    );
    expect(find.text('Regenerate Branch Name'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'remote-topic');
    await tester.pump();
    expect(find.text('Replacement Branch *'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(localGitReads, 0);
    expect(tester.takeException(), isNull);
  });
}
