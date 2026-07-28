import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/presentation/browser_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submits addresses and dispatches toolbar actions', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final actions = <String>[];
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 900,
          child: BrowserToolbar(
            state: _state(canGoBack: true),
            addressController: controller,
            addressFocusNode: focusNode,
            profileLabel: 'Default',
            onBack: () => actions.add('back'),
            onForward: null,
            onStopOrReload: () => actions.add('reload'),
            onSubmitAddress: (value) => submitted = value,
            onShowSecurity: () => actions.add('security'),
            onSelectProfile: () => actions.add('profile'),
            onShowDownloads: () => actions.add('downloads'),
            onOpenDevTools: () => actions.add('devtools'),
            onOpenExternally: () => actions.add('external'),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Go Back'));
    await tester.tap(find.byTooltip('Reload Page'));
    await tester.tap(find.byTooltip('Secure Connection - https://example.com'));
    await tester.tap(find.byTooltip('Browser Profile'));
    await tester.tap(find.byTooltip('Downloads'));
    await tester.tap(find.byTooltip('Open DevTools'));
    await tester.tap(find.byTooltip('Open Externally'));
    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.testTextInput.receiveAction(TextInputAction.done);

    expect(actions, <String>[
      'back',
      'reload',
      'security',
      'profile',
      'downloads',
      'devtools',
      'external',
    ]);
    expect(submitted, 'example.org');
    expect(find.byTooltip('Go Forward'), findsOneWidget);
  });

  testWidgets('keeps the essential controls on compact panes', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox(
            width: 600,
            child: BrowserToolbar(
              state: _state(loading: true),
              addressController: controller,
              addressFocusNode: focusNode,
              profileLabel: 'Research',
              onBack: null,
              onForward: null,
              onStopOrReload: () {},
              onSubmitAddress: (_) {},
              onShowSecurity: () {},
              onSelectProfile: () {},
              onShowDownloads: () {},
              onOpenDevTools: () {},
              onOpenExternally: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Stop Loading'), findsOneWidget);
    expect(find.byTooltip('Browser Profile: Research'), findsOneWidget);
    expect(find.byTooltip('Open DevTools'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Search Or Enter Address',
    );
  });
}

BrowserPageState _state({bool loading = false, bool canGoBack = false}) {
  final page = BrowserPage(
    pageId: 'browser-1',
    workspaceId: 'workspace-1',
    profileId: 'default',
    initialUrl: Uri.parse('https://example.com'),
    createdAt: DateTime.utc(2026, 7, 27),
  );
  return BrowserPageState.initial(page).copyWith(
    url: Uri.parse('https://example.com'),
    loadPhase: loading ? BrowserLoadPhase.started : BrowserLoadPhase.finished,
    loadProgress: loading ? 0.5 : null,
    canGoBack: canGoBack,
    security: const BrowserSecurityState(
      level: BrowserSecurityLevel.secure,
      origin: 'https://example.com',
    ),
  );
}
