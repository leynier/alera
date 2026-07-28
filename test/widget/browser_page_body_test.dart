import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/presentation/browser_page_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blocks the surface when the capability gate is not met', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserPageBody(
          state: _state().copyWith(
            engineAvailability: BrowserEngineAvailability.unavailable,
            capabilityReason: 'WebKitGTK 4.1 Is Not Installed.',
          ),
          surface: const Text('Native Surface'),
          onRetry: () {},
          onOpenExternally: () {},
        ),
      ),
    );

    expect(find.text('Browser Engine Unavailable'), findsOneWidget);
    expect(find.text('WebKitGTK 4.1 Is Not Installed.'), findsOneWidget);
    expect(find.text('Native Surface'), findsNothing);
  });

  testWidgets('shows recovery actions for a failed navigation', (tester) async {
    var retries = 0;
    var externalOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserPageBody(
          state: _state().copyWith(
            loadPhase: BrowserLoadPhase.failed,
            error: const BrowserFailure(
              code: BrowserErrorCode.navigationBlocked,
              message: 'The Page Was Blocked.',
              recoverable: true,
            ),
          ),
          surface: const Text('Native Surface'),
          onRetry: () => retries += 1,
          onOpenExternally: () => externalOpens += 1,
        ),
      ),
    );

    await tester.tap(find.text('Try Again'));
    await tester.tap(find.text('Open Externally'));

    expect(retries, 1);
    expect(externalOpens, 1);
    expect(find.text('Native Surface'), findsNothing);
  });

  testWidgets('renders the native surface for an available page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserPageBody(
          state: _state(),
          surface: const Text('Native Surface'),
          onRetry: () {},
          onOpenExternally: () {},
        ),
      ),
    );

    expect(find.text('Native Surface'), findsOneWidget);
  });

  test('native surface visibility excludes blank and failed states', () {
    expect(browserStateShowsNativeSurface(_state()), isTrue);
    expect(
      browserStateShowsNativeSurface(
        _state().copyWith(url: Uri.parse('about:blank')),
      ),
      isFalse,
    );
    expect(
      browserStateShowsNativeSurface(
        _state().copyWith(loadPhase: BrowserLoadPhase.failed),
      ),
      isFalse,
    );
  });
}

BrowserPageState _state() {
  final page = BrowserPage(
    pageId: 'browser-1',
    workspaceId: 'workspace-1',
    profileId: 'default',
    initialUrl: Uri.parse('https://example.com'),
    createdAt: DateTime.utc(2026, 7, 27),
  );
  return BrowserPageState.initial(page);
}
