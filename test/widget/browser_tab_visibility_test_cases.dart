import 'package:alera/src/features/browser/application/browser_profile_service.dart';
import 'package:alera/src/features/browser/application/browser_providers.dart';
import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera/src/features/browser/presentation/browser_tab_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/features/browser/fake_browser_engine.dart';

void registerNativeBrowserVisibilityTest() {
  testWidgets(
    'hidden retained browser releases registry and native widget leases',
    (tester) async {
      final engine = FakeBrowserEngine();
      final registry = BrowserSessionRegistry(engine: engine);
      final platform = _BrowserSurfacePlatform();
      final client = AleraBrowserClient(platform: platform);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final tab = WorkspaceTabRecord(
        id: 'page-1',
        workspaceId: 'workspace-1',
        title: 'Browser',
        kind: WorkspaceTabKind.browser,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        payload: {'browserUrl': 'https://example.test'},
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              browserSessionRegistryProvider.overrideWithValue(registry),
              browserProfileServiceProvider.overrideWithValue(_Profiles()),
              aleraBrowserClientProvider.overrideWithValue(client),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder(
                  valueListenable: visible,
                  builder: (context, value, child) => Visibility(
                    visible: value,
                    maintainState: true,
                    child: child!,
                  ),
                  child: BrowserTabSurface(tab: tab),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        final pageId = registry.sessions.single.pageId;
        final state = tester.state(find.byType(BrowserTabSurface));
        expect(engine.calls, contains('attach:$pageId'));
        expect(platform.calls, ['attach:$pageId']);
        visible.value = false;
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(find.byType(BrowserTabSurface), findsNothing);
        expect(
          tester.state(find.byType(BrowserTabSurface, skipOffstage: false)),
          same(state),
        );
        expect(engine.calls.last, 'detach:$pageId');
        expect(platform.calls.last, 'detach:$pageId');
        visible.value = true;
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(engine.calls.last, 'attach:$pageId');
        expect(platform.calls.last, 'attach:$pageId');
        expect(
          engine.calls.where((call) => call.startsWith('createPage:')),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await client.dispose();
        await registry.dispose();
        await engine.dispose();
      }
    },
  );
}

class _BrowserSurfacePlatform implements AleraBrowserPlatform {
  final calls = <String>[];
  @override
  Stream<AleraBrowserEvent> get events => const Stream.empty();
  @override
  Widget buildPageView(String pageId, {Key? key}) => SizedBox(key: key);
  @override
  Future<void> attachPage(String pageId) async => calls.add('attach:$pageId');
  @override
  Future<void> detachPage(String pageId) async => calls.add('detach:$pageId');
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements BrowserProfileService {
  @override
  Future<List<BrowserProfile>> list() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
