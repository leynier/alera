import 'package:alera_mobile/src/features/workbench/domain/pull_request_ship_follow_up.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'pull_request_ship_follow_up_controller.g.dart';

final Logger _logger = Logger('PullRequestShipFollowUpController');

const _shipFollowUpPrefsKey = 'alera.mobile.pullRequestShipFollowUp';

/// Last Ship follow-up chosen on this phone, remembered like the desktop Ship
/// split button.
@Riverpod(keepAlive: true)
class PullRequestShipFollowUpController
    extends _$PullRequestShipFollowUpController {
  @override
  Future<PullRequestShipFollowUp> build() async {
    try {
      return PullRequestShipFollowUp.fromName(
        await SharedPreferencesAsync().getString(_shipFollowUpPrefsKey),
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('could not read ship follow-up', error, stackTrace);
      return PullRequestShipFollowUp.none;
    }
  }

  Future<void> set(PullRequestShipFollowUp value) async {
    state = AsyncData(value);
    try {
      await SharedPreferencesAsync().setString(
        _shipFollowUpPrefsKey,
        value.name,
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('could not save ship follow-up', error, stackTrace);
    }
  }
}
