import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/presentation/browser_security_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers only the exact temporary local exception', (
    tester,
  ) async {
    var trusted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => BrowserSecurityDialog(
                  security: BrowserSecurityState(
                    level: BrowserSecurityLevel.certificateFailure,
                    origin: 'https://localhost:8443',
                    challenge: BrowserCertificateChallenge(
                      id: 'challenge-1',
                      host: 'localhost',
                      port: 8443,
                      errorCode: 'untrusted',
                      expiresAt: DateTime.utc(2026, 7, 27, 1),
                      canProceed: true,
                    ),
                  ),
                  onTrustLocalCertificate: () => trusted = true,
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
    expect(find.text('Review Certificate Trust'), findsOneWidget);
    await tester.tap(find.text('Review Certificate Trust'));
    await tester.pumpAndSettle();
    expect(trusted, isTrue);
  });

  testWidgets('does not offer an exception for public hosts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserSecurityDialog(
          security: BrowserSecurityState(
            level: BrowserSecurityLevel.certificateFailure,
            origin: 'https://example.com',
            challenge: BrowserCertificateChallenge(
              id: 'challenge-1',
              host: 'example.com',
              port: 443,
              errorCode: 'expired',
              expiresAt: DateTime.utc(2026, 7, 27, 1),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Review Certificate Trust'), findsNothing);
    expect(
      find.textContaining('Public hosts cannot bypass certificate failures.'),
      findsOneWidget,
    );
  });
}
