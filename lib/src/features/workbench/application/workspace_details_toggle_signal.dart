import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_details_toggle_signal.g.dart';

@riverpod
class WorkspaceDetailsToggleSignal extends _$WorkspaceDetailsToggleSignal {
  @override
  int build(String workspaceId) => 0;
  void toggle() => state++;
}
