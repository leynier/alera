import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_hosts_visible_host.g.dart';

/// The host Settings > Remote Hosts is showing, if any. Link toasts stay
/// quiet for it because its state is already on screen.
@Riverpod(keepAlive: true)
class RemoteHostsVisibleHost extends _$RemoteHostsVisibleHost {
  @override
  String? build() => null;

  void show(String hostId) {
    if (ref.mounted) {
      state = hostId;
    }
  }

  /// Clears [hostId] only if it is still the one shown, so a pane that is
  /// replaced does not clear what its successor published.
  void hide(String hostId) {
    if (ref.mounted && state == hostId) {
      state = null;
    }
  }
}
