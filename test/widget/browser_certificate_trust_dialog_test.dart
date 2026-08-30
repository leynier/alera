import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/presentation/browser_certificate_trust_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows exact profile scope and all trust choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserCertificateTrustDialog(
          request: _request(),
          profileLabel: 'Development',
          canPersist: true,
        ),
      ),
    );

    expect(find.text('Trust Local Certificate?'), findsOneWidget);
    expect(
      find.textContaining('every port and tab in Development'),
      findsOneWidget,
    );
    expect(find.text('Trust For This Session'), findsOneWidget);
    expect(find.text('Always Trust'), findsOneWidget);
    expect(find.textContaining('AA:AA:AA'), findsOneWidget);
  });

  testWidgets('ephemeral profiles cannot choose permanent trust', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserCertificateTrustDialog(
          request: _request(),
          profileLabel: 'Temporary',
          canPersist: false,
        ),
      ),
    );

    expect(find.text('Trust For This Session'), findsOneWidget);
    expect(find.text('Always Trust'), findsNothing);
  });
}

BrowserTlsRequest _request() {
  return BrowserTlsRequest(
    pageId: 'page',
    host: 'service.local',
    fingerprintSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    subject: 'Local Service',
    issuer: 'Development CA',
    errors: const <BrowserTlsErrorType>{BrowserTlsErrorType.untrustedIssuer},
    requestedAt: .utc(2026, 7, 28),
  );
}
