import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'quota_host_visibility_controller.g.dart';

const quotaHiddenRuntimeIdsKey = 'quotas.hiddenRuntimeIds';

@Riverpod(keepAlive: true)
class QuotaHostVisibilityController extends _$QuotaHostVisibilityController {
  final _logger = Logger('QuotaHostVisibilityController');
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<Set<String>> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return Set<String>.unmodifiable(
        prefs.getStringList(quotaHiddenRuntimeIdsKey) ?? const <String>[],
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('could not load quota hosts', error, stackTrace);
      rethrow;
    }
  }

  Future<void> setHostVisible(String runtimeId, bool visible) {
    // Serialize read-modify-write so quick changes to different hosts survive.
    final operation = _pendingWrite.then((_) async {
      try {
        final current = await future;
        final hidden = <String>{...current};
        if (visible) {
          hidden.remove(runtimeId);
        } else {
          hidden.add(runtimeId);
        }
        final prefs = await SharedPreferences.getInstance();
        final saved = await prefs.setStringList(
          quotaHiddenRuntimeIdsKey,
          hidden.toList()..sort(),
        );
        if (!saved) throw StateError('Could not save quota hosts.');
        if (ref.mounted) state = AsyncData(Set<String>.unmodifiable(hidden));
      } on Object catch (error, stackTrace) {
        _logger.warning('could not save quota hosts', error, stackTrace);
        rethrow;
      }
    });
    // A failed write must not block later edits; the caller receives the error.
    _pendingWrite = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
