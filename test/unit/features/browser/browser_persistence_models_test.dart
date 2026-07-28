import 'package:alera/src/features/browser/domain/browser_history.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history entries round-trip current and legacy field names', () {
    final entry = BrowserHistoryEntry.fromJson(<String, Object?>{
      'id': 'history-1',
      'profileId': 'profile-1',
      'url': 'https://example.com/docs',
      'title': 'Example Docs',
      'lastVisitedAt': '2026-07-27T10:00:00-06:00',
      'visitCount': 3.9,
      'workspaceId': 'workspace-1',
      'pageId': 'page-1',
    });

    expect(entry.lastVisitedAt, DateTime.utc(2026, 7, 27, 16));
    expect(entry.visitCount, 3);
    expect(entry.pageId, 'page-1');
    expect(entry.toJson(), <String, Object?>{
      'id': 'history-1',
      'profileId': 'profile-1',
      'url': 'https://example.com/docs',
      'title': 'Example Docs',
      'visitedAt': '2026-07-27T16:00:00.000Z',
      'visitCount': 3,
      'workspaceId': 'workspace-1',
      'tabId': 'page-1',
    });
  });

  test('closed tabs normalize legacy ids and preserve payloads', () {
    final closed = BrowserClosedTab.fromJson(<String, Object?>{
      'pageId': 'page-1',
      'workspaceId': 'workspace-1',
      'profileId': 'profile-1',
      'url': 'https://example.com/closed',
      'title': 'Closed Page',
      'closedAt': '2026-07-27T10:00:00-06:00',
      'payload': <Object?, Object?>{'scrollY': 12},
    });

    expect(closed.id, 'page-1');
    expect(closed.payload, <String, Object?>{'scrollY': 12});
    expect(() => closed.payload['new'] = true, throwsUnsupportedError);
    expect(closed.toJson(), <String, Object?>{
      'id': 'page-1',
      'workspaceId': 'workspace-1',
      'profileId': 'profile-1',
      'url': 'https://example.com/closed',
      'title': 'Closed Page',
      'payload': <String, Object?>{'scrollY': 12},
      'closedAt': '2026-07-27T16:00:00.000Z',
    });
  });

  test('profile sources normalize unknown families and optional names', () {
    final source = BrowserProfileSource.fromJson(<String, Object?>{
      'family': 'future-browser',
      'profileName': '  Profile 2  ',
      'importedAt': '2026-07-27T10:00:00-06:00',
    });

    expect(source.family, BrowserImportSourceFamily.manual);
    expect(source.profileName, 'Profile 2');
    expect(source.toJson(), <String, Object?>{
      'family': 'manual',
      'profileName': 'Profile 2',
      'importedAt': '2026-07-27T16:00:00.000Z',
    });
  });

  test('profiles infer default kind and round-trip optional metadata', () {
    final profile = BrowserProfile.fromJson(<String, Object?>{
      'id': defaultBrowserProfileId,
      'label': ' Default ',
      'kind': 'future-kind',
      'persistent': false,
      'createdAt': '2026-07-27T10:00:00-06:00',
      'updatedAt': '2026-07-27T11:00:00-06:00',
      'source': <String, Object?>{
        'family': 'firefox',
        'importedAt': '2026-07-27T09:00:00-06:00',
      },
    });

    expect(profile.id, defaultBrowserProfileId);
    expect(profile.label, 'Default');
    expect(profile.kind, BrowserProfileKind.defaultProfile);
    expect(profile.isDefault, isTrue);
    expect(profile.persistent, isFalse);
    expect(profile.toJson(), <String, Object?>{
      'id': defaultBrowserProfileId,
      'label': 'Default',
      'kind': 'defaultProfile',
      'persistent': false,
      'createdAt': '2026-07-27T16:00:00.000Z',
      'updatedAt': '2026-07-27T17:00:00.000Z',
      'source': <String, Object?>{
        'family': 'firefox',
        'importedAt': '2026-07-27T15:00:00.000Z',
      },
    });

    final isolated = BrowserProfile.fromJson(<String, Object?>{
      'id': 'isolated-1',
      'label': 'Isolated',
      'kind': 'future-kind',
      'createdAt': '2026-07-27T16:00:00Z',
    });
    expect(isolated.kind, BrowserProfileKind.isolated);
    expect(isolated.isDefault, isFalse);
  });
}
