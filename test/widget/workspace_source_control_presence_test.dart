import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/presentation/workspace_source_control_presence.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';
import '../unit/fake_source_control_watcher.dart';

void main() {
  testWidgets(
    'retained offstage panels release observation and selected checkout replaces it',
    (tester) async {
      final visible = ValueNotifier(true);
      final path = ValueNotifier('/first');
      final watcher = FakeSourceControlWatcher();
      addTearDown(visible.dispose);
      addTearDown(path.dispose);
      addTearDown(watcher.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gitBackendProvider.overrideWithValue(FakeGitBackend()),
            sourceControlWatcherProvider.overrideWithValue(watcher),
          ],
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, enabled, _) => TickerMode(
                enabled: enabled,
                child: ValueListenableBuilder<String>(
                  valueListenable: path,
                  builder: (context, selected, _) => Consumer(
                    builder: (context, ref, _) {
                      ref.watch(
                        workspaceSourceControlControllerProvider(selected),
                      );
                      return WorkspaceSourceControlPresence(
                        path: selected,
                        child: const SizedBox(),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(watcher.startCount, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkspaceSourceControlPresence)),
      );
      container.invalidate(workspaceSourceControlControllerProvider('/first'));
      await tester.pumpAndSettle();
      expect(watcher.startCount, 2);
      expect(watcher.stopCount, 1);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(watcher.stopCount, 2);
      visible.value = true;
      await tester.pumpAndSettle();
      expect(watcher.startCount, 3);
      path.value = '/second';
      await tester.pumpAndSettle();
      expect(watcher.startCount, 4);
      expect(watcher.stopCount, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(watcher.stopCount, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
