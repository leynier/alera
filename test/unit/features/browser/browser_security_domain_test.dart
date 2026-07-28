import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserCertificateChallenge', () {
    test('round trips all fields and normalizes time and port', () {
      final challenge = BrowserCertificateChallenge.fromJson(<String, Object?>{
        'id': 'challenge-1',
        'host': 'localhost',
        'port': 8443.9,
        'errorCode': 'self_signed',
        'fingerprint': 'AA:BB',
        'expiresAt': '2026-07-27T12:00:00-05:00',
        'canProceed': true,
      });

      expect(challenge.id, 'challenge-1');
      expect(challenge.host, 'localhost');
      expect(challenge.port, 8443);
      expect(challenge.errorCode, 'self_signed');
      expect(challenge.fingerprint, 'AA:BB');
      expect(challenge.expiresAt, DateTime.utc(2026, 7, 27, 17));
      expect(challenge.canProceed, isTrue);
      expect(challenge.toJson(), <String, Object?>{
        'id': 'challenge-1',
        'host': 'localhost',
        'port': 8443,
        'errorCode': 'self_signed',
        'fingerprint': 'AA:BB',
        'expiresAt': '2026-07-27T17:00:00.000Z',
        'canProceed': true,
      });
    });

    test('uses optional defaults and rejects malformed required fields', () {
      final minimal = BrowserCertificateChallenge.fromJson(<String, Object?>{
        'id': 'challenge-2',
        'host': 'example.com',
        'port': 443,
        'errorCode': 'expired',
        'expiresAt': '2026-07-27T17:00:00Z',
      });
      expect(minimal.fingerprint, isNull);
      expect(minimal.canProceed, isFalse);
      expect(minimal.toJson(), isNot(contains('fingerprint')));

      for (final invalid in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{
          'id': 1,
          'host': 'example.com',
          'port': 443,
          'errorCode': 'expired',
          'expiresAt': '2026-07-27T17:00:00Z',
        },
        <String, Object?>{
          'id': 'id',
          'host': 7,
          'port': 443,
          'errorCode': 'expired',
          'expiresAt': '2026-07-27T17:00:00Z',
        },
        <String, Object?>{
          'id': 'id',
          'host': 'example.com',
          'port': '443',
          'errorCode': 'expired',
          'expiresAt': '2026-07-27T17:00:00Z',
        },
        <String, Object?>{
          'id': 'id',
          'host': 'example.com',
          'port': 443,
          'errorCode': 9,
          'expiresAt': '2026-07-27T17:00:00Z',
        },
        <String, Object?>{
          'id': 'id',
          'host': 'example.com',
          'port': 443,
          'errorCode': 'expired',
          'expiresAt': 'not-a-date',
        },
      ]) {
        expect(
          () => BrowserCertificateChallenge.fromJson(invalid),
          throwsFormatException,
        );
      }
    });
  });

  group('BrowserSecurityState', () {
    test('round trips nested challenges and classifies secure states', () {
      final state = BrowserSecurityState.fromJson(<String, Object?>{
        'level': 'certificateFailure',
        'origin': 'https://localhost:8443',
        'challenge': <Object?, Object?>{
          'id': 'challenge',
          'host': 'localhost',
          'port': 8443,
          'errorCode': 'self_signed',
          'expiresAt': '2026-07-27T17:00:00Z',
        },
      });

      expect(state.level, BrowserSecurityLevel.certificateFailure);
      expect(state.origin, 'https://localhost:8443');
      expect(state.challenge?.id, 'challenge');
      expect(state.isSecure, isFalse);
      expect(state.toJson()['challenge'], isA<Map<String, Object?>>());

      for (final level in BrowserSecurityLevel.values) {
        final value = BrowserSecurityState(level: level);
        expect(
          value.isSecure,
          level == BrowserSecurityLevel.secure ||
              level == BrowserSecurityLevel.local,
        );
      }
    });

    test('unknown and optional state fields use safe defaults', () {
      final state = BrowserSecurityState.fromJson(<String, Object?>{
        'level': 'future-level',
        'challenge': 'invalid',
      });

      expect(state.level, BrowserSecurityLevel.unknown);
      expect(state.origin, isNull);
      expect(state.challenge, isNull);
      expect(state.toJson(), <String, Object?>{'level': 'unknown'});
      expect(BrowserSecurityState.unknown.level, BrowserSecurityLevel.unknown);
    });
  });

  test('TLS requests retain optional callback context', () {
    final requestedAt = DateTime.utc(2026, 7, 27);
    final request = BrowserTlsRequest(
      pageId: 'page-1',
      url: Uri.parse('https://localhost'),
      description: 'Self-signed certificate',
      requestedAt: requestedAt,
    );
    final minimal = BrowserTlsRequest(
      pageId: 'page-2',
      requestedAt: requestedAt,
    );

    expect(request.pageId, 'page-1');
    expect(request.url, Uri.parse('https://localhost'));
    expect(request.description, 'Self-signed certificate');
    expect(request.requestedAt, requestedAt);
    expect(minimal.url, isNull);
    expect(minimal.description, isNull);
  });

  test('URL security covers uncommitted, remote, local, and invalid URLs', () {
    final uncommitted = browserSecurityForUrl(
      Uri.parse('https://example.com:8443/docs'),
      committed: false,
    );
    expect(uncommitted.level, BrowserSecurityLevel.unknown);
    expect(uncommitted.origin, 'https://example.com:8443');

    final invalid = browserSecurityForUrl(
      Uri.parse('about:blank'),
      committed: true,
    );
    expect(invalid.level, BrowserSecurityLevel.unknown);
    expect(invalid.origin, isNull);

    expect(
      browserSecurityForUrl(
        Uri.parse('https://example.com'),
        committed: true,
      ).level,
      BrowserSecurityLevel.secure,
    );
    expect(
      browserSecurityForUrl(
        Uri.parse('http://example.com'),
        committed: true,
      ).level,
      BrowserSecurityLevel.insecure,
    );
    for (final url in <String>[
      'http://localhost',
      'http://app.localhost',
      'http://[::1]',
      'http://0.0.0.0',
      'http://127.12.34.56',
    ]) {
      final state = browserSecurityForUrl(Uri.parse(url), committed: true);
      expect(state.level, BrowserSecurityLevel.local, reason: url);
      expect(state.isSecure, isTrue);
    }

    expect(browserOrigin(Uri.parse('mailto:user@example.com')), isNull);
    expect(browserOrigin(Uri(scheme: 'https', path: 'relative')), isNull);
    expect(
      browserOrigin(Uri.parse('https://example.com:9443/path')),
      'https://example.com:9443',
    );
  });
}
