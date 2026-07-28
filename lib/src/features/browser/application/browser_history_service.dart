import 'package:alera/src/features/browser/domain/browser_history.dart';

abstract interface class BrowserHistoryService {
  Future<List<BrowserHistoryEntry>> list({String? profileId, int limit = 100});

  Future<int> clear({String? profileId});
}
