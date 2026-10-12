import 'package:dart_mappable/dart_mappable.dart';

part 'run_detail_tab.mapper.dart';

/// The tabs of a selected run. Resources exists only for isolated runs.
@MappableEnum()
enum RunDetailTab {
  overview('Overview'),
  tasks('Tasks'),
  timeline('Timeline'),
  resources('Resources');

  RunDetailTab(this.label);

  final String label;
}
