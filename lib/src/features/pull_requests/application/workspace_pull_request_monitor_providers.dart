import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_monitor.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_refresh_signal.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_monitor_providers.g.dart';

const Duration workspacePullRequestPendingPollInterval = Duration(seconds: 30);
const Duration workspacePullRequestInitialPollInterval = Duration(minutes: 1);
const Duration workspacePullRequestMaxPollInterval = Duration(minutes: 5);

class const WorkspacePullRequestMonitorConfiguration({
  required this.targets,
  required this.showStatusInSidebar,
  required this.failureNotificationsEnabled,
}) {
  final List<WorkspacePullRequestMonitorTarget> targets;
  final bool showStatusInSidebar;
  final bool failureNotificationsEnabled;

  String get signature => <Object?>[
    showStatusInSidebar,
    failureNotificationsEnabled,
    for (final target in targets) target.configurationKey,
  ].join('\n');
}

class const WorkspacePullRequestMonitorState({
  this.summaries = const <String, WorkspacePullRequestSummary>{},
  this.refreshRevision = 0,
}) {
  final Map<String, WorkspacePullRequestSummary> summaries;
  final int refreshRevision;
}

@Riverpod(keepAlive: true)
WorkspacePullRequestMonitorLoader workspacePullRequestMonitorLoader(Ref ref) {
  return WorkspacePullRequestMonitorLoader(
    ref.watch(gitBackendProvider),
    ref.watch(forgeProviderRegistryProvider),
    ref.watch(linkedReviewRepositoryProvider),
  );
}

@Riverpod(keepAlive: true)
WorkspacePullRequestMonitorConfiguration
workspacePullRequestMonitorConfiguration(Ref ref) {
  final preferences = ref.watch(
    settingsControllerProvider.select(
      (settings) => (
        showStatusInSidebar: settings.general.showPullRequestStatusInSidebar,
        failureNotificationsEnabled:
            settings.general.pullRequestFailureNotificationsEnabled,
      ),
    ),
  );
  final topology = ref.watch(
    workbenchControllerProvider.select(
      (state) => (
        bootstrapped: state.bootstrapped,
        projects: state.projects,
        workspacesByProject: state.workspacesByProject,
      ),
    ),
  );
  final targets = <WorkspacePullRequestMonitorTarget>[];
  if (topology.bootstrapped &&
      (preferences.showStatusInSidebar ||
          preferences.failureNotificationsEnabled)) {
    for (final project in topology.projects) {
      if (project.kind != ProjectKind.gitRepository) {
        continue;
      }
      final providerOverride = ref
          .watch(effectiveHostingProviderOverrideProvider(project.id))
          .asData
          ?.value;
      for (final workspace
          in topology.workspacesByProject[project.id] ?? const []) {
        final branch = workspace.branch?.trim() ?? '';
        if (!workspace.isActive || branch.isEmpty || branch == 'HEAD') {
          continue;
        }
        targets.add(
          WorkspacePullRequestMonitorTarget(
            projectId: project.id,
            projectName: project.name,
            workspaceId: workspace.id,
            workspaceName: workspace.name,
            repoPath: project.repoPath,
            branch: branch,
            providerOverride: providerOverride,
          ),
        );
      }
    }
  }
  targets.sort((left, right) {
    final projectOrder = left.projectId.compareTo(right.projectId);
    return projectOrder != 0
        ? projectOrder
        : left.workspaceId.compareTo(right.workspaceId);
  });
  return WorkspacePullRequestMonitorConfiguration(
    targets: List<WorkspacePullRequestMonitorTarget>.unmodifiable(targets),
    showStatusInSidebar: preferences.showStatusInSidebar,
    failureNotificationsEnabled: preferences.failureNotificationsEnabled,
  );
}

/// One timer and one refresh pipeline for every workspace. Provider calls are
/// grouped by repository in [WorkspacePullRequestMonitorLoader], and the timer
/// parks while the app is hidden unless failure notifications are enabled.
@Riverpod(keepAlive: true)
class WorkspacePullRequestMonitorController
    extends _$WorkspacePullRequestMonitorController {
  List<WorkspacePullRequestMonitorTarget> _targets =
      const <WorkspacePullRequestMonitorTarget>[];
  String _configurationSignature = '';
  bool _showStatusInSidebar = false;
  bool _failureNotificationsEnabled = false;
  bool _isForeground = true;
  bool _refreshing = false;
  bool _refreshRequested = false;
  bool _disposed = false;
  int _generation = 0;
  Duration _pollInterval = workspacePullRequestInitialPollInterval;
  Timer? _timer;
  StreamSubscription<bool>? _foregroundSubscription;

  @override
  WorkspacePullRequestMonitorState build() {
    final foreground = ref.watch(appForegroundProvider);
    _isForeground = foreground.isForeground;
    _foregroundSubscription = foreground.changes.distinct().listen(
      _handleForegroundChanged,
    );
    ref.listen<WorkspacePullRequestMonitorConfiguration>(
      workspacePullRequestMonitorConfigurationProvider,
      (_, configuration) {
        scheduleMicrotask(() => _configure(configuration));
      },
      fireImmediately: true,
    );
    ref.listen<int>(workspacePullRequestRefreshSignalProvider, (
      previous,
      next,
    ) {
      if (previous != null && next != previous) {
        _schedule(Duration.zero);
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      unawaited(_foregroundSubscription?.cancel());
    });
    return const WorkspacePullRequestMonitorState();
  }

  Future<void> refreshNow() async {
    if (_disposed || !_shouldRun) {
      return;
    }
    if (_refreshing) {
      _refreshRequested = true;
      return;
    }
    _timer?.cancel();
    _timer = null;
    _refreshing = true;
    final generation = _generation;
    final targets = List<WorkspacePullRequestMonitorTarget>.from(_targets);
    try {
      final result = await ref
          .read(workspacePullRequestMonitorLoaderProvider)
          .load(targets: targets, previous: state.summaries);
      if (_disposed || generation != _generation) {
        _refreshRequested = true;
        return;
      }
      final next = result.summaries;
      final changed = !_summaryMapsEqual(state.summaries, next);
      state = WorkspacePullRequestMonitorState(
        summaries: next,
        refreshRevision: state.refreshRevision + 1,
      );
      if (result.hadErrors) {
        _pollInterval = _doubleCapped(
          _pollInterval,
          workspacePullRequestMaxPollInterval,
        );
      } else if (next.values.any((summary) => summary.checksPending)) {
        _pollInterval = workspacePullRequestPendingPollInterval;
      } else if (changed) {
        _pollInterval = workspacePullRequestInitialPollInterval;
      } else {
        _pollInterval = _doubleCapped(
          _pollInterval,
          workspacePullRequestMaxPollInterval,
        );
      }
    } finally {
      _refreshing = false;
      if (!_disposed) {
        if (_refreshRequested) {
          _refreshRequested = false;
          _schedule(Duration.zero);
        } else {
          _schedule(_pollInterval);
        }
      }
    }
  }

  bool get _shouldRun =>
      _targets.isNotEmpty &&
      (_failureNotificationsEnabled || (_showStatusInSidebar && _isForeground));

  void _configure(WorkspacePullRequestMonitorConfiguration configuration) {
    if (_disposed || configuration.signature == _configurationSignature) {
      return;
    }
    _configurationSignature = configuration.signature;
    _targets = configuration.targets;
    _showStatusInSidebar = configuration.showStatusInSidebar;
    _failureNotificationsEnabled = configuration.failureNotificationsEnabled;
    _generation++;
    _pollInterval = workspacePullRequestInitialPollInterval;
    final activeWorkspaceIds = <String>{
      for (final target in _targets) target.workspaceId,
    };
    final pruned = <String, WorkspacePullRequestSummary>{
      for (final entry in state.summaries.entries)
        if (activeWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    if (!_summaryMapsEqual(state.summaries, pruned)) {
      state = WorkspacePullRequestMonitorState(
        summaries: Map<String, WorkspacePullRequestSummary>.unmodifiable(
          pruned,
        ),
        refreshRevision: state.refreshRevision,
      );
    }
    if (!_shouldRun) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _schedule(Duration.zero);
  }

  void _handleForegroundChanged(bool foreground) {
    if (_disposed || foreground == _isForeground) {
      return;
    }
    _isForeground = foreground;
    if (_shouldRun) {
      _pollInterval = workspacePullRequestInitialPollInterval;
      _schedule(Duration.zero);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = null;
    if (!_shouldRun || _disposed) {
      return;
    }
    _timer = Timer(delay, () => unawaited(refreshNow()));
  }
}

@riverpod
WorkspacePullRequestSummary? workspacePullRequestSummary(
  Ref ref,
  String workspaceId,
) {
  final visible = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.showPullRequestStatusInSidebar,
    ),
  );
  if (!visible) {
    return null;
  }
  return ref.watch(
    workspacePullRequestMonitorControllerProvider.select(
      (monitor) => monitor.summaries[workspaceId],
    ),
  );
}

Duration _doubleCapped(Duration value, Duration maximum) {
  final doubled = Duration(microseconds: value.inMicroseconds * 2);
  return doubled > maximum ? maximum : doubled;
}

bool _summaryMapsEqual(
  Map<String, WorkspacePullRequestSummary> left,
  Map<String, WorkspacePullRequestSummary> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
