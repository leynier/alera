import 'package:dart_mappable/dart_mappable.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';

part 'run_board_location.mapper.dart';

@MappableClass()
class RunBoardLocation with RunBoardLocationMappable {
  const RunBoardLocation({
    this.visible = false,
    this.projectId,
    this.workspaceId,
    this.search = '',
    this.bucket,
    this.runId,
    this.taskId,
  });
  final bool visible;
  final String? projectId;
  final String? workspaceId;
  final String search;
  final RunBoardBucket? bucket;
  final String? runId;
  final String? taskId;
}
