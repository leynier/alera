import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_search_controller.g.dart';

@riverpod
class WorkspaceSearchController extends _$WorkspaceSearchController {
  @override
  String build(String hostId) => '';

  void setQuery(String value) => state = value;

  void clear() => state = '';
}
