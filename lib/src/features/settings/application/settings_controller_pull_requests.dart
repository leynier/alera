part of 'settings_controller.dart';

mixin _SettingsControllerPullRequestSettings on _$SettingsController {
  SettingsController get _pullRequestSettingsController =>
      this as SettingsController;

  Future<void> setShowPullRequestStatusInSidebar(bool value) {
    final controller = _pullRequestSettingsController;
    return controller._serialize(() async {
      if (state.general.showPullRequestStatusInSidebar == value) {
        return;
      }
      await controller._save(
        state.copyWith(
          general: state.general.copyWith(
            showPullRequestStatusInSidebar: value,
          ),
        ),
      );
    });
  }

  Future<void> setPullRequestFailureNotificationsEnabled(bool value) {
    final controller = _pullRequestSettingsController;
    return controller._serialize(() async {
      if (state.general.pullRequestFailureNotificationsEnabled == value) {
        return;
      }
      await controller._save(
        state.copyWith(
          general: state.general.copyWith(
            pullRequestFailureNotificationsEnabled: value,
          ),
        ),
      );
    });
  }
}
