import 'dart:async';
import 'dart:io' show pid;

import 'package:alera/src/features/resource_manager/application/resource_snapshot_projection.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'resource_manager_providers.g.dart';

/// Cadence while the panel is open. Matches the host's own sampling interval,
/// so the UI never polls faster than new data can appear.
const resourceSnapshotOpenInterval = Duration(seconds: 2);

/// Cadence while the panel is closed. The status-bar chip still needs a number,
/// but nobody is watching it change, and each poll keeps the host's sampler
/// alive.
///
/// The host sweeps at whatever cadence it is told, so this is the interval it
/// runs at too: a slower poll is a proportionally cheaper host.
const resourceSnapshotClosedInterval = Duration(seconds: 15);

const _resourceSnapshotTimeout = Duration(seconds: 5);

/// Whether the resource panel is on screen. Drives the polling cadence.
@riverpod
class ResourcePanelOpen extends _$ResourcePanelOpen {
  @override
  bool build() => false;

  void set({required bool open}) => state = open;
}

@Riverpod(keepAlive: true)
Future<ResourceSnapshot> resourceSnapshot(Ref ref) async {
  final open = ref.watch(resourcePanelOpenProvider);
  final client = ref.watch(runtimeHostClientProvider);
  final interval = open
      ? resourceSnapshotOpenInterval
      : resourceSnapshotClosedInterval;
  final timer = Timer.periodic(interval, (_) => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return fetchResourceSnapshot(client: client, appPid: pid, interval: interval);
}

/// Ask the runtime host for its latest sweep.
///
/// [interval] is the cadence this caller polls at. The host sizes both its
/// sampling interval and the window it waits before stopping around it, so an
/// omitted or wrong value leaves the sampler stopped under a client that is
/// still asking.
///
/// A host that predates the resource monitor simply rejects the verb, so a
/// failure degrades to an unavailable snapshot instead of an error state: the
/// chip is ambient UI and must never break the status bar.
Future<ResourceSnapshot> fetchResourceSnapshot({
  required RuntimeHostClient client,
  required int appPid,
  required Duration interval,
}) async {
  try {
    final payload = await client.runtimeRequest(
      'resources.snapshot',
      <String, Object?>{
        'appPid': appPid,
        'intervalMs': interval.inMilliseconds,
      },
      _resourceSnapshotTimeout,
    );
    if (payload is! Map) {
      return ResourceSnapshot.unavailable(
        error: 'The runtime host returned an unexpected resource payload.',
      );
    }
    return ResourceSnapshot.fromJson(Map<String, Object?>.from(payload));
  } catch (error) {
    return ResourceSnapshot.unavailable(error: error.toString());
  }
}

/// The snapshot projected onto the workbench tree, ready to render.
@riverpod
ResourceTree resourceTree(Ref ref, ResourceSortColumn sortColumn) {
  final snapshot = ref.watch(resourceSnapshotProvider).value;
  if (snapshot == null) {
    return ResourceTree.empty;
  }
  final workbench = ref.watch(workbenchControllerProvider);
  return buildResourceTree(
    snapshot: snapshot,
    projects: workbench.projects,
    workspaces: <Workspace>[
      for (final workspaces in workbench.workspacesByProject.values)
        ...workspaces,
    ],
    tabs: <WorkspaceTabRecord>[
      for (final tabs in workbench.tabsByWorkspace.values) ...tabs,
    ],
    sortColumn: sortColumn,
  );
}
