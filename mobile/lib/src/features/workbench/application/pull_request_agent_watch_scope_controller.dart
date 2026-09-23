import 'dart:convert';

import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'pull_request_agent_watch_scope_controller.g.dart';

final Logger _logger = Logger('PullRequestAgentWatchScopeController');

const _watchScopePrefsKey = 'alera.mobile.pullRequestAgentWatchScope';

/// Last Watch and Fix problems chosen on this phone, remembered like desktop
/// settings so the next watch opens with the same checks/comments/conflicts.
@Riverpod(keepAlive: true)
class PullRequestAgentWatchScopeController
    extends _$PullRequestAgentWatchScopeController {
  @override
  Future<PullRequestAgentWatchScope> build() async {
    try {
      final encoded = await SharedPreferencesAsync().getString(
        _watchScopePrefsKey,
      );
      if (encoded == null || encoded.isEmpty) {
        return PullRequestAgentWatchScope.defaults;
      }
      final decoded = jsonDecode(encoded);
      return decoded is Map
          ? PullRequestAgentWatchScope.fromJson(
              Map<String, Object?>.from(decoded),
            )
          : PullRequestAgentWatchScope.defaults;
    } on Object catch (error, stackTrace) {
      _logger.warning('could not read watch scope', error, stackTrace);
      return PullRequestAgentWatchScope.defaults;
    }
  }

  Future<void> set(PullRequestAgentWatchScope value) async {
    state = AsyncData(value);
    try {
      await SharedPreferencesAsync().setString(
        _watchScopePrefsKey,
        jsonEncode(value.toJson()),
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('could not save watch scope', error, stackTrace);
    }
  }
}
