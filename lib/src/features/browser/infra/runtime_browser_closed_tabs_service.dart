import 'package:alera/src/features/browser/application/browser_closed_tabs_service.dart';
import 'package:alera/src/features/browser/domain/browser_history.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class const RuntimeBrowserClosedTabsService(
  final RuntimeHostClient _client,
) implements BrowserClosedTabsService {
  @override
  Future<bool> close(String pageId) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.tabs.close', <String, Object?>{
        'pageId': pageId,
      }),
      'Browser tab close',
    );
    return response['closed'] == true;
  }

  @override
  Future<List<BrowserClosedTab>> list({
    String? profileId,
    int limit = 10,
  }) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.closedTabs.list', <String, Object?>{
        'profileId': ?profileId,
        'limit': limit.clamp(1, 1000),
      }),
      'Closed browser tab list',
    );
    return <BrowserClosedTab>[
      for (final value in browserRuntimeList(response, 'tabs'))
        BrowserClosedTab.fromJson(
          browserRuntimeItem(value, 'Closed browser tab'),
        ),
    ];
  }

  @override
  Future<bool> remove(String closedTabId) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest(
        'browser.closedTabs.remove',
        <String, Object?>{'id': closedTabId},
      ),
      'Closed browser tab removal',
    );
    return response['removed'] == true;
  }

  @override
  Future<String> reopen(String closedTabId, {String? targetGroupId}) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.tabs.reopen', <String, Object?>{
        'id': closedTabId,
        'targetGroupId': ?targetGroupId,
      }),
      'Closed browser tab reopen',
    );
    final pageId = response['pageId'];
    if (pageId is! String || pageId.isEmpty) {
      throw const FormatException(
        'Closed browser tab reopen response has no pageId.',
      );
    }
    return pageId;
  }
}
