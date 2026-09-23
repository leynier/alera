import 'package:alera/src/features/workbench/application/workspace_explorer_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceExplorerSessionStore', () {
    test('saves compact expansion and scroll state', () {
      final store = WorkspaceExplorerSessionStore();
      const session = WorkspaceExplorerSession(
        expandedRelativePaths: <String>{'src', 'src/app'},
        scrollOffset: 96,
      );

      store.save('w-1', session);

      expect(store.peek('w-1')?.expandedRelativePaths, <String>{
        'src',
        'src/app',
      });
      expect(store.peek('w-1')?.scrollOffset, 96);
    });

    test('drops empty sessions instead of retaining them', () {
      final store = WorkspaceExplorerSessionStore()
        ..save(
          'w-1',
          const WorkspaceExplorerSession(
            expandedRelativePaths: <String>{'src'},
            scrollOffset: 32,
          ),
        )
        ..save(
          'w-1',
          const WorkspaceExplorerSession(expandedRelativePaths: <String>{}),
        );

      expect(store.peek('w-1'), isNull);
    });

    test('retain keeps only active workspace ids', () {
      final store = WorkspaceExplorerSessionStore()
        ..save(
          'active',
          const WorkspaceExplorerSession(
            expandedRelativePaths: <String>{'src'},
          ),
        )
        ..save(
          'idle',
          const WorkspaceExplorerSession(
            expandedRelativePaths: <String>{'lib'},
          ),
        );

      store.retain(<String>{'active'});

      expect(store.peek('active'), isNotNull);
      expect(store.peek('idle'), isNull);
    });

    test('save ignores workspaces that retain already dropped', () {
      final store = WorkspaceExplorerSessionStore()..retain(<String>{'active'});

      store.save(
        'idle',
        const WorkspaceExplorerSession(expandedRelativePaths: <String>{'src'}),
      );

      expect(store.peek('idle'), isNull);
    });
  });
}
