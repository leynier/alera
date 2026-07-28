import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera/src/features/browser/domain/browser_settings.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_closed_tabs_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_history_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_permission_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_profile_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_settings_service.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile service retains import source metadata', () async {
    final client = _FakeRuntimeHostClient((type, payload) {
      expect(type, 'browser.profiles.list');
      return <String, Object?>{
        'ok': true,
        'profiles': <Object?>[
          <String, Object?>{
            'id': 'work',
            'name': 'Work',
            'persistent': true,
            'isDefault': false,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-02-01T00:00:00Z',
            'source': <String, Object?>{
              'family': 'chrome',
              'profileName': 'Profile 1',
              'importedAt': '2026-02-01T00:00:00Z',
            },
          },
        ],
      };
    });

    final profiles = await RuntimeBrowserProfileService(client).list();

    expect(profiles.single.label, 'Work');
    expect(profiles.single.source?.family, BrowserImportSourceFamily.chrome);
    expect(profiles.single.source?.profileName, 'Profile 1');
  });

  test('profile removal validation is non-destructive', () async {
    final requests = <String>[];
    final client = _FakeRuntimeHostClient((type, payload) {
      requests.add(type);
      expect(payload['id'], 'work');
      return switch (type) {
        'browser.profiles.validateRemoval' => <String, Object?>{
          'ok': true,
          'id': 'work',
        },
        'browser.profiles.remove' => <String, Object?>{
          'ok': true,
          'removed': true,
        },
        _ => throw StateError(type),
      };
    });
    final service = RuntimeBrowserProfileService(client);

    await service.validateRemoval('work');
    expect(await service.remove('work'), isTrue);

    expect(requests, <String>[
      'browser.profiles.validateRemoval',
      'browser.profiles.remove',
    ]);
  });

  test('history and closed tab services map host catalog shapes', () async {
    final client = _FakeRuntimeHostClient((type, payload) {
      return switch (type) {
        'browser.history.list' => <String, Object?>{
          'ok': true,
          'entries': <Object?>[
            <String, Object?>{
              'id': 'history-1',
              'profileId': 'work',
              'workspaceId': 'workspace-1',
              'tabId': 'page-1',
              'url': 'https://example.com',
              'title': 'Example',
              'visitedAt': '2026-01-01T00:00:00Z',
            },
          ],
        },
        'browser.closedTabs.list' => <String, Object?>{
          'ok': true,
          'tabs': <Object?>[
            <String, Object?>{
              'id': 'closed-1',
              'profileId': 'work',
              'workspaceId': 'workspace-1',
              'url': 'https://example.com',
              'title': 'Example',
              'payload': <String, Object?>{'browserProfileId': 'work'},
              'closedAt': '2026-01-01T00:00:00Z',
            },
          ],
        },
        'browser.tabs.close' => <String, Object?>{'ok': true, 'closed': true},
        _ => throw StateError(type),
      };
    });

    final history = await RuntimeBrowserHistoryService(client).list();
    final closed = await RuntimeBrowserClosedTabsService(client).list();

    expect(history.single.pageId, 'page-1');
    expect(closed.single.id, 'closed-1');
    expect(
      await RuntimeBrowserClosedTabsService(client).close('page-1'),
      isTrue,
    );
  });

  test('settings service uses the typed search engine contract', () async {
    final client = _FakeRuntimeHostClient((type, payload) {
      if (type == 'browser.settings.get') {
        return <String, Object?>{
          'ok': true,
          'settings': <String, Object?>{'searchEngine': 'kagi'},
        };
      }
      expect(payload['searchEngine'], 'bing');
      return <String, Object?>{'ok': true, 'settings': payload};
    });
    final service = RuntimeBrowserSettingsService(client);

    expect((await service.get()).searchEngine, BrowserSearchEngine.kagi);
    expect(
      (await service.set(
        const BrowserSettings(searchEngine: BrowserSearchEngine.bing),
      )).searchEngine,
      BrowserSearchEngine.bing,
    );
  });

  test(
    'permission service scopes decisions and persists concrete choices',
    () async {
      final requests = <(String, Map<String, Object?>)>[];
      final client = _FakeRuntimeHostClient((type, payload) {
        requests.add((type, payload));
        if (type == 'browser.permissions.list') {
          return <String, Object?>{
            'ok': true,
            'permissions': <Object?>[
              <String, Object?>{
                'profileId': 'work',
                'origin': 'https://example.com',
                'permission': 'camera',
                'decision': 'allow',
                'updatedAt': '2026-01-01T00:00:00Z',
              },
            ],
          };
        }
        return <String, Object?>{'ok': true, 'permission': payload};
      });
      final service = RuntimeBrowserPermissionService(client);

      expect(
        await service.decisionFor(
          profileId: 'work',
          origin: 'https://example.com',
          permission: BrowserPermissionType.camera,
        ),
        BrowserPermissionDecision.allow,
      );
      await service.remember(
        profileId: 'work',
        origin: 'https://example.com',
        permission: BrowserPermissionType.camera,
        decision: BrowserPermissionDecision.deny,
      );

      expect(requests[0].$2['profileId'], 'work');
      expect(requests[0].$2['origin'], 'https://example.com');
      expect(requests[1].$1, 'browser.permissions.set');
      expect(requests[1].$2['decision'], 'deny');
    },
  );
}

typedef _RuntimeHandler =
    Object? Function(String type, Map<String, Object?> payload);

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  const _FakeRuntimeHostClient(this._handler);

  final _RuntimeHandler _handler;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async => _handler(type, payload);
}
