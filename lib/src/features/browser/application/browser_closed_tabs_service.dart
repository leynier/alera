import 'package:alera/src/features/browser/domain/browser_history.dart';

abstract interface class BrowserClosedTabsService {
  Future<bool> close(String pageId);

  Future<List<BrowserClosedTab>> list({String? profileId, int limit = 10});

  Future<bool> remove(String closedTabId);

  Future<String> reopen(String closedTabId, {String? targetGroupId});
}
