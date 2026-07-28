import 'package:alera/src/features/browser/application/browser_profile_session_switch.dart';
import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_browser_engine.dart';

void main() {
  late FakeBrowserEngine engine;
  late BrowserSessionRegistry registry;

  setUp(() {
    engine = FakeBrowserEngine();
    registry = BrowserSessionRegistry(engine: engine);
  });

  tearDown(() async {
    await registry.dispose();
    await engine.dispose();
  });

  test('keeps the current native page when persistence fails', () async {
    final currentTab = _tab();
    final currentSession = await registry.sessionFor(currentTab);

    await expectLater(
      switchBrowserSessionProfile(
        registry: registry,
        currentSession: currentSession,
        currentTab: currentTab,
        persist: () =>
            Future<WorkspaceTabRecord>.error(StateError('persistence failed')),
      ),
      throwsStateError,
    );

    final unchanged = registry.handleForPageId(currentTab.id);
    expect(unchanged, same(currentSession));
    expect(unchanged?.state.profileId, 'default');
    expect(
      engine.calls.where((call) => call == 'createPage:page-1:false'),
      hasLength(1),
    );
    expect(engine.calls, isNot(contains('close:page-1')));
  });

  test(
    'creates the replacement only after the profile was persisted',
    () async {
      final currentTab = _tab();
      final currentSession = await registry.sessionFor(currentTab);
      final steps = <String>[];

      final replacement = await switchBrowserSessionProfile(
        registry: registry,
        currentSession: currentSession,
        currentTab: currentTab,
        persist: () async {
          steps.add('persist');
          expect(registry.handleForPageId(currentTab.id), same(currentSession));
          return _tab(profileId: 'research');
        },
      );

      expect(steps, <String>['persist']);
      expect(replacement.state.profileId, 'research');
      expect(replacement, isNot(same(currentSession)));
    },
  );
}

WorkspaceTabRecord _tab({String profileId = 'default'}) {
  return WorkspaceTabRecord(
    id: 'page-1',
    workspaceId: 'workspace-1',
    kind: WorkspaceTabKind.browser,
    title: 'New Tab',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    payload: <String, Object?>{
      workspaceTabBrowserProfileIdPayloadKey: profileId,
    },
  );
}
