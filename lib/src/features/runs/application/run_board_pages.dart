import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/infra/foreground_board_watch.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_board_pages.g.dart';

/// A watched read plus the state of loading its next page.
class RunPageRead<T> {
  const RunPageRead(this.data, {this.loadingMore = false, this.pageError});

  final T data;
  final bool loadingMore;
  final Object? pageError;
}

Duration? runNoRetry(int count, Object error) => null;

/// How many attention rows the status-bar hover card lists.
const int runAttentionPreviewLimit = 5;

/// The attention bucket: its count for the chip and rail, and its newest rows
/// for the hover card. Hidden windows do no reads.
@Riverpod(retry: runNoRetry)
Stream<RunBoardPage> runBoardAttention(Ref ref) {
  final repository = ref.watch(runRepositoryProvider);
  return foregroundBoardWatch(
    ref.watch(appForegroundProvider),
    () => repository.watchBoard(
      const RunBoardQuery(
        bucket: RunBucket.attention,
        limit: runAttentionPreviewLimit,
      ),
    ),
  );
}

@Riverpod(retry: runNoRetry)
class RunBoardListPage extends _$RunBoardListPage {
  @override
  Stream<RunPageRead<RunBoardPage>> build({
    String? projectId,
    String? workspaceId,
    String search = '',
    RunBucket? bucket,
  }) {
    final repository = ref.watch(runRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository.watchBoard(_query()).map(RunPageRead.new),
    );
  }

  RunBoardQuery _query({RunBoardCursor? cursor}) => RunBoardQuery(
    projectId: projectId,
    workspaceId: workspaceId,
    search: search.isEmpty ? null : search,
    bucket: bucket,
    cursor: cursor,
  );

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null ||
        current.loadingMore ||
        current.data.nextCursor == null) {
      return;
    }
    final data = current.data;
    state = AsyncData(RunPageRead(data, loadingMore: true));
    try {
      final next = await ref
          .read(runRepositoryProvider)
          .readBoard(_query(cursor: data.nextCursor));
      if (!ref.mounted || !identical(state.asData?.value.data, data)) return;
      if (next.revision != data.revision) {
        throw StateError('The run list changed. Refresh to continue.');
      }
      state = AsyncData(
        RunPageRead(
          RunBoardPage(
            revision: next.revision,
            counts: next.counts,
            items: List.unmodifiable([...data.items, ...next.items]),
            nextCursor: next.nextCursor,
          ),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.asData?.value.data, data)) {
        state = AsyncData(RunPageRead(data, pageError: error));
      }
    }
  }
}
