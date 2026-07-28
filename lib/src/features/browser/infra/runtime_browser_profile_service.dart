import 'package:alera/src/features/browser/application/browser_profile_service.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

final class RuntimeBrowserProfileService implements BrowserProfileService {
  RuntimeBrowserProfileService(
    this._client, {
    RuntimeChangeCoalescer? coalescer,
  }) : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeHostClient _client;
  final RuntimeChangeCoalescer _coalescer;

  @override
  Future<List<BrowserProfile>> list() async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.profiles.list'),
      'Browser profile list',
    );
    return <BrowserProfile>[
      for (final value in browserRuntimeList(response, 'profiles'))
        BrowserProfile.fromJson(
          _profileJson(browserRuntimeItem(value, 'Browser profile')),
        ),
    ];
  }

  @override
  Stream<List<BrowserProfile>> watchAll() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'browserProfilesChanged'},
      readSnapshot: list,
      coalesceKey: 'browserProfiles',
      coalescer: _coalescer,
    );
  }

  @override
  Future<BrowserProfile> upsert({
    String? id,
    required String name,
    bool persistent = true,
    BrowserProfileSource? source,
  }) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.profiles.upsert', <String, Object?>{
        'id': ?id,
        'name': name,
        'persistent': persistent,
        'source': ?source?.toJson(),
      }),
      'Browser profile upsert',
    );
    return BrowserProfile.fromJson(
      _profileJson(browserRuntimeItem(response['profile'], 'Browser profile')),
    );
  }

  @override
  Future<void> validateRemoval(String profileId) async {
    browserRuntimeSuccessMap(
      await _client.runtimeRequest(
        'browser.profiles.validateRemoval',
        <String, Object?>{'id': profileId},
      ),
      'Browser profile removal validation',
    );
  }

  @override
  Future<bool> remove(String profileId) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.profiles.remove', <String, Object?>{
        'id': profileId,
      }),
      'Browser profile removal',
    );
    return response['removed'] == true;
  }
}

Map<String, Object?> _profileJson(Map<String, Object?> value) {
  return <String, Object?>{
    ...value,
    'label': value['name'],
    'kind': value['isDefault'] == true
        ? BrowserProfileKind.defaultProfile.name
        : BrowserProfileKind.isolated.name,
  };
}
