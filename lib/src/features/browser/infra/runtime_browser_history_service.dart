import 'package:alera/src/features/browser/application/browser_history_service.dart';
import 'package:alera/src/features/browser/domain/browser_history.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class RuntimeBrowserHistoryService implements BrowserHistoryService {
  const RuntimeBrowserHistoryService(this._client);

  final RuntimeHostClient _client;

  @override
  Future<List<BrowserHistoryEntry>> list({
    String? profileId,
    int limit = 100,
  }) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.history.list', <String, Object?>{
        'profileId': ?profileId,
        'limit': limit.clamp(1, 1000),
      }),
      'Browser history list',
    );
    return <BrowserHistoryEntry>[
      for (final value in browserRuntimeList(response, 'entries'))
        BrowserHistoryEntry.fromJson(
          browserRuntimeItem(value, 'Browser history entry'),
        ),
    ];
  }

  @override
  Future<int> clear({String? profileId}) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.history.clear', <String, Object?>{
        'profileId': ?profileId,
      }),
      'Browser history clear',
    );
    return (response['removed'] as num?)?.toInt() ?? 0;
  }
}
