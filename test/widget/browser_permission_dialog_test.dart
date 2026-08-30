import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/presentation/browser_permission_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returns an origin-scoped permission decision', (tester) async {
    BrowserPermissionPromptResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<BrowserPermissionPromptResult>(
                context: context,
                builder: (_) => BrowserPermissionDialog(
                  request: _request(.camera),
                  profileLabel: 'Research',
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remember For Research'));
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(result?.decision, BrowserPermissionDecision.allow);
    expect(result?.rememberForProfile, isTrue);
  });

  testWidgets('display capture is deny-only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserPermissionDialog(
          request: _request(.displayCapture),
          profileLabel: 'Default',
        ),
      ),
    );

    expect(find.text('Allow'), findsNothing);
    expect(find.text('Deny'), findsOneWidget);
    expect(find.textContaining('Alera does not allow'), findsOneWidget);
  });
}

BrowserPermissionRequest _request(BrowserPermissionType permission) {
  return BrowserPermissionRequest(
    requestId: 'permission-1',
    pageId: 'browser-1',
    origin: 'https://example.com',
    permission: permission,
    requestedAt: .utc(2026, 7, 27),
    userGesture: true,
  );
}
