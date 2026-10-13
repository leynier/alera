import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runs/application/run_board_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';
import 'package:alera/src/features/runs/infra/foreground_board_watch.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_timeline_page.g.dart';

/// Newest entries first; [nextCursor] continues with older ones.
class RunTimelineView {
  const RunTimelineView(this.items, this.nextCursor);

  final List<RunTimelineEntry> items;
  final String? nextCursor;
}

const int runTimelinePageSize = 50;

/// The newest page is watched; older pages are appended on demand. Entries
/// never change once written, so a refreshed newest page merges with the
/// older pages already loaded instead of dropping them.
@Riverpod(retry: runNoRetry)
class RunTimeline extends _$RunTimeline {
  final List<RunTimelineEntry> _older = <RunTimelineEntry>[];
  String? _olderCursor;
  bool _continued = false;

  @override
  Stream<RunPageRead<RunTimelineView>> build(
    String runId,
    RunTimelineFilter filter,
  ) {
    _older.clear();
    _olderCursor = null;
    _continued = false;
    final repository = ref.watch(runRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository
          .watchTimeline(runId, limit: runTimelinePageSize, kinds: filter.kinds)
          .map((page) => RunPageRead(_merge(page))),
    );
  }

  RunTimelineView _merge(RunTimelinePage newest) {
    if (!_continued) return RunTimelineView(newest.items, newest.nextCursor);
    final seen = <String>{};
    return RunTimelineView(
      List.unmodifiable(<RunTimelineEntry>[
        for (final entry in <RunTimelineEntry>[...newest.items, ..._older])
          if (seen.add(entry.id)) entry,
      ]),
      _olderCursor,
    );
  }

  Future<void> loadOlder() async {
    final current = state.asData?.value;
    final cursor = current?.data.nextCursor;
    if (current == null || current.loadingMore || cursor == null) return;
    final data = current.data;
    state = AsyncData(RunPageRead(data, loadingMore: true));
    try {
      final page = await ref
          .read(runRepositoryProvider)
          .readTimeline(
            runId,
            cursor: cursor,
            limit: runTimelinePageSize,
            kinds: filter.kinds,
          );
      if (!ref.mounted || !identical(state.asData?.value.data, data)) return;
      final seen = <String>{};
      final loaded = <RunTimelineEntry>[
        for (final entry in <RunTimelineEntry>[...data.items, ...page.items])
          if (seen.add(entry.id)) entry,
      ];
      // Keep everything loaded, not only the older page: entries a refresh
      // pushes out of the newest page must not leave a gap.
      _older
        ..clear()
        ..addAll(loaded);
      _olderCursor = page.nextCursor;
      _continued = true;
      state = AsyncData(
        RunPageRead(
          RunTimelineView(List.unmodifiable(loaded), page.nextCursor),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.asData?.value.data, data)) {
        state = AsyncData(RunPageRead(data, pageError: error));
      }
    }
  }
}
