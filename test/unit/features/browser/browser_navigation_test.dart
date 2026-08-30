import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserNavigationPolicy', () {
    test('blank input resolves to the internal empty page', () {
      final target = const BrowserNavigationPolicy().resolve('   ');

      expect(target.url.toString(), 'about:blank');
      expect(target.kind, BrowserNavigationKind.blank);
      expect(target.originalInput, '   ');
    });

    test('resolves hosts, localhost, and configured searches', () {
      const google = BrowserNavigationPolicy();
      const duck = BrowserNavigationPolicy(searchEngine: .duckDuckGo);
      const bing = BrowserNavigationPolicy(searchEngine: .bing);
      const kagi = BrowserNavigationPolicy(searchEngine: .kagi);

      expect(
        google.resolve('example.com/docs').url.toString(),
        'https://example.com/docs',
      );
      expect(
        google.resolve('localhost:8080').url.toString(),
        'http://localhost:8080',
      );
      expect(duck.resolve('flutter riverpod').url.host, 'duckduckgo.com');
      expect(
        duck.resolve('flutter riverpod').kind,
        BrowserNavigationKind.search,
      );
      expect(bing.resolve('flutter riverpod').url.host, 'www.bing.com');
      expect(kagi.resolve('flutter riverpod').url.host, 'kagi.com');
    });

    test('rejects script, data, file URLs, and local paths', () {
      const policy = BrowserNavigationPolicy();

      for (final value in <String>[
        'javascript:alert(1)',
        'data:text/plain,secret',
        'file:///tmp/secret',
        '/tmp/secret',
        r'C:\Users\secret.txt',
      ]) {
        expect(
          () => policy.resolve(value),
          throwsA(
            isA<BrowserFailure>().having(
              (failure) => failure.code,
              'code',
              BrowserErrorCode.navigationBlocked,
            ),
          ),
        );
      }
    });

    test('allows only the internal about blank address', () {
      const policy = BrowserNavigationPolicy();

      expect(policy.resolve('about:blank').kind, BrowserNavigationKind.blank);
      expect(
        () => policy.resolve('about:config'),
        throwsA(isA<BrowserFailure>()),
      );
    });

    test('rejects explicit web URLs without a safe authority', () {
      const policy = BrowserNavigationPolicy();

      for (final value in <String>[
        'https:/missing-host',
        'http:relative',
        'https://user:password@example.com/private',
      ]) {
        expect(
          () => policy.resolve(value),
          throwsA(
            isA<BrowserFailure>().having(
              (failure) => failure.code,
              'code',
              BrowserErrorCode.invalidUrl,
            ),
          ),
          reason: value,
        );
      }
    });

    test('rejects malformed hosts and explicit URI payloads', () {
      const policy = BrowserNavigationPolicy();

      expect(() => policy.resolve('[:::]'), throwsA(isA<BrowserFailure>()));
      expect(
        () => policy.resolve('https://[:::]'),
        throwsA(isA<BrowserFailure>()),
      );
    });
  });

  group('BrowserHistorySensitivityFilter', () {
    test('accepts ordinary web URLs and rejects sensitive state', () {
      expect(
        isPersistableBrowserUrl('https://example.com/docs?q=flutter'),
        isTrue,
      );
      for (final value in <String>[
        'https://user:password@example.com/private',
        'https://example.com/oauth/callback?code=secret',
        'https://example.com/docs?access_token=secret',
        'https://example.com/docs?auth=secret',
        'https://example.com/#id_token=secret',
        'https://example.com/#state=secret',
        'about:blank',
        'file:///tmp/private',
      ]) {
        expect(isPersistableBrowserUrl(value), isFalse, reason: value);
      }
    });
  });

  group('browserPermissionTypeFromWire', () {
    test('covers required permission families', () {
      expect(
        browserPermissionTypeFromWire('geolocation'),
        BrowserPermissionType.geolocation,
      );
      expect(
        browserPermissionTypeFromWire('clipboard-read'),
        BrowserPermissionType.clipboardRead,
      );
      expect(
        browserPermissionTypeFromWire('clipboardWrite'),
        BrowserPermissionType.clipboardWrite,
      );
      expect(
        browserPermissionTypeFromWire('public-key-credentials'),
        BrowserPermissionType.webAuthn,
      );
      expect(
        browserPermissionTypeFromWire('display-capture'),
        BrowserPermissionType.displayCapture,
      );
    });

    test('display capture remains deny even when configured allow', () {
      const policy = BrowserPermissionPolicy(
        decisions: <BrowserPermissionType, BrowserPermissionDecision>{
          BrowserPermissionType.displayCapture: BrowserPermissionDecision.allow,
        },
      );

      expect(
        policy.decisionFor(.displayCapture),
        BrowserPermissionDecision.deny,
      );
    });
  });
}
