import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserPage', () {
    test('round trips, copies mutable fields, and preserves identity', () {
      final page = BrowserPage.fromJson(<String, Object?>{
        'pageId': 'page-1',
        'workspaceId': 'workspace-1',
        'profileId': 'work',
        'initialUrl': 'https://example.com/docs',
        'createdAt': '2026-07-27T12:00:00-05:00',
      });

      expect(page.pageId, 'page-1');
      expect(page.workspaceId, 'workspace-1');
      expect(page.profileId, 'work');
      expect(page.initialUrl, Uri.parse('https://example.com/docs'));
      expect(page.createdAt, DateTime.utc(2026, 7, 27, 17));
      expect(page.toJson(), <String, Object?>{
        'pageId': 'page-1',
        'workspaceId': 'workspace-1',
        'profileId': 'work',
        'initialUrl': 'https://example.com/docs',
        'createdAt': '2026-07-27T17:00:00.000Z',
      });

      final unchanged = page.copyWith();
      final copied = page.copyWith(
        profileId: 'personal',
        initialUrl: Uri.parse('about:blank'),
      );
      expect(unchanged.profileId, 'work');
      expect(unchanged.initialUrl, page.initialUrl);
      expect(copied.pageId, page.pageId);
      expect(copied.workspaceId, page.workspaceId);
      expect(copied.createdAt, page.createdAt);
      expect(copied.profileId, 'personal');
      expect(copied.initialUrl, Uri.parse('about:blank'));
    });

    test('rejects malformed required page fields', () {
      final valid = <String, Object?>{
        'pageId': 'page',
        'workspaceId': 'workspace',
        'profileId': 'default',
        'initialUrl': 'about:blank',
        'createdAt': '2026-07-27T17:00:00Z',
      };
      for (final entry in <MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('pageId', 1),
        const MapEntry<String, Object?>('workspaceId', 1),
        const MapEntry<String, Object?>('profileId', 1),
        const MapEntry<String, Object?>('initialUrl', 'http://[::1'),
        const MapEntry<String, Object?>('createdAt', 'invalid'),
      ]) {
        expect(
          () => BrowserPage.fromJson(<String, Object?>{
            ...valid,
            entry.key: entry.value,
          }),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });

    test(
      'blank pages support explicit and default profile and creation time',
      () {
        final explicit = BrowserPage.blank(
          pageId: 'page-1',
          workspaceId: 'workspace-1',
          profileId: 'work',
          createdAt: DateTime.parse('2026-07-27T12:00:00-05:00'),
        );
        final before = DateTime.now().toUtc();
        final defaults = BrowserPage.blank(
          pageId: 'page-2',
          workspaceId: 'workspace-1',
        );
        final after = DateTime.now().toUtc();

        expect(explicit.profileId, 'work');
        expect(explicit.initialUrl, Uri.parse('about:blank'));
        expect(explicit.createdAt, DateTime.utc(2026, 7, 27, 17));
        expect(defaults.profileId, defaultBrowserProfileId);
        expect(defaults.initialUrl, Uri.parse('about:blank'));
        expect(defaults.createdAt.isBefore(before), isFalse);
        expect(defaults.createdAt.isAfter(after), isFalse);
      },
    );
  });

  group('browser permissions', () {
    test('wire aliases normalize to every supported permission type', () {
      final aliases = <BrowserPermissionType, List<String>>{
        BrowserPermissionType.geolocation: <String>[
          'geolocation',
          ' LOCATION ',
        ],
        BrowserPermissionType.camera: <String>[
          'camera',
          'video',
          'video-capture',
        ],
        BrowserPermissionType.microphone: <String>[
          'microphone',
          'audio',
          'audio_capture',
        ],
        BrowserPermissionType.notifications: <String>[
          'notifications',
          'notification',
        ],
        BrowserPermissionType.clipboardRead: <String>['clipboard-read'],
        BrowserPermissionType.clipboardWrite: <String>['clipboard write'],
        BrowserPermissionType.fullscreen: <String>['fullscreen'],
        BrowserPermissionType.persistentStorage: <String>['persistent-storage'],
        BrowserPermissionType.pointerLock: <String>['pointer_lock'],
        BrowserPermissionType.webAuthn: <String>[
          'webauthn',
          'public-key-credentials',
        ],
        BrowserPermissionType.displayCapture: <String>[
          'displaycapture',
          'screen',
          'screen-capture',
        ],
      };

      for (final entry in aliases.entries) {
        for (final alias in entry.value) {
          expect(
            browserPermissionTypeFromWire(alias),
            entry.key,
            reason: alias,
          );
        }
      }
      expect(
        browserPermissionTypeFromWire('future permission'),
        BrowserPermissionType.unknown,
      );
    });

    test('permission requests round trip and default unknown values', () {
      final request = BrowserPermissionRequest.fromJson(<String, Object?>{
        'requestId': 'request-1',
        'pageId': 'page-1',
        'origin': 'https://example.com',
        'permission': 'camera',
        'requestedAt': '2026-07-27T12:00:00-05:00',
        'userGesture': true,
      });

      expect(request.requestId, 'request-1');
      expect(request.pageId, 'page-1');
      expect(request.origin, 'https://example.com');
      expect(request.permission, BrowserPermissionType.camera);
      expect(request.requestedAt, DateTime.utc(2026, 7, 27, 17));
      expect(request.userGesture, isTrue);
      expect(request.toJson(), <String, Object?>{
        'requestId': 'request-1',
        'pageId': 'page-1',
        'origin': 'https://example.com',
        'permission': 'camera',
        'requestedAt': '2026-07-27T17:00:00.000Z',
        'userGesture': true,
      });

      final unknown = BrowserPermissionRequest.fromJson(<String, Object?>{
        'requestId': 'request-2',
        'pageId': 'page-1',
        'origin': 'https://example.com',
        'permission': 'future',
        'requestedAt': '2026-07-27T17:00:00Z',
      });
      expect(unknown.permission, BrowserPermissionType.unknown);
      expect(unknown.userGesture, isFalse);

      final direct = BrowserPermissionRequest(
        requestId: 'request-3',
        pageId: 'page-1',
        origin: 'https://example.com',
        permission: BrowserPermissionType.notifications,
        requestedAt: DateTime.utc(2026),
      );
      expect(direct.userGesture, isFalse);
    });

    test('permission requests reject malformed required fields', () {
      final valid = <String, Object?>{
        'requestId': 'request',
        'pageId': 'page',
        'origin': 'https://example.com',
        'requestedAt': '2026-07-27T17:00:00Z',
      };
      for (final entry in <MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('requestId', 1),
        const MapEntry<String, Object?>('pageId', 1),
        const MapEntry<String, Object?>('origin', 1),
        const MapEntry<String, Object?>('requestedAt', 'invalid'),
      ]) {
        expect(
          () => BrowserPermissionRequest.fromJson(<String, Object?>{
            ...valid,
            entry.key: entry.value,
          }),
          throwsFormatException,
        );
      }
    });

    test(
      'policy forces display capture denial and resolves other decisions',
      () {
        final policy = BrowserPermissionPolicy(
          decisions: <BrowserPermissionType, BrowserPermissionDecision>{
            BrowserPermissionType.displayCapture:
                BrowserPermissionDecision.allow,
            BrowserPermissionType.camera: BrowserPermissionDecision.deny,
          },
        );

        expect(
          policy.decisionFor(BrowserPermissionType.displayCapture),
          BrowserPermissionDecision.deny,
        );
        expect(
          policy.decisionFor(BrowserPermissionType.camera),
          BrowserPermissionDecision.deny,
        );
        expect(
          policy.decisionFor(BrowserPermissionType.microphone),
          BrowserPermissionDecision.ask,
        );
        expect(const BrowserPermissionPolicy().decisions, isEmpty);
      },
    );
  });

  group('BrowserFailure', () {
    test('round trips typed details and renders a stable message', () {
      final failure = BrowserFailure.fromJson(<String, Object?>{
        'code': 'timeout',
        'message': 'The Browser Timed Out.',
        'recoverable': true,
        'details': <String, Object?>{'attempt': 2},
      });

      expect(failure.code, BrowserErrorCode.timeout);
      expect(failure.message, 'The Browser Timed Out.');
      expect(failure.recoverable, isTrue);
      expect(failure.details, <String, Object?>{'attempt': 2});
      expect(failure.toJson(), <String, Object?>{
        'code': 'timeout',
        'message': 'The Browser Timed Out.',
        'recoverable': true,
        'details': <String, Object?>{'attempt': 2},
      });
      expect(
        failure.toString(),
        'BrowserFailure(timeout): The Browser Timed Out.',
      );
      expect(() => failure.details['attempt'] = 3, throwsUnsupportedError);
    });

    test('normalizes generic maps and defaults malformed error values', () {
      final generic = BrowserFailure.fromJson(<String, Object?>{
        'code': 'invalidPayload',
        'message': 'Invalid.',
        'details': <Object?, Object?>{'field': 'url'},
      });
      final fallback = BrowserFailure.fromJson(<String, Object?>{
        'code': 'future',
        'message': 7,
        'details': 'invalid',
      });
      const direct = BrowserFailure(
        code: BrowserErrorCode.engineUnavailable,
        message: 'Unavailable.',
      );

      expect(generic.code, BrowserErrorCode.invalidPayload);
      expect(generic.details, <String, Object?>{'field': 'url'});
      expect(fallback.code, BrowserErrorCode.unknown);
      expect(fallback.message, 'Unknown Browser Error.');
      expect(fallback.recoverable, isFalse);
      expect(fallback.details, isEmpty);
      expect(fallback.toJson(), isNot(contains('details')));
      expect(direct.recoverable, isFalse);
      expect(direct.details, isEmpty);
    });
  });
}
