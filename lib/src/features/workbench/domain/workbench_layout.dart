import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_layout.mapper.dart';
part 'workbench_layout_mutations.dart';

const double workbenchMinSplitRatio = 0.15;
const double workbenchMaxSplitRatio = 0.85;

@MappableEnum()
enum WorkbenchSplitAxis { horizontal, vertical }

enum WorkbenchDropZone { center, left, right, up, down }

@MappableClass()
class WorkbenchPaneGroup({
  required this.id,
  required List<String> tabIds,
  required this.activeTabId,
}) with WorkbenchPaneGroupMappable {
  this : tabIds = List<String>.unmodifiable(tabIds) {
    if (id.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Workbench pane group id must not be empty.',
      );
    }
  }

  final String id;
  final List<String> tabIds;
  final String? activeTabId;

  factory fromJson(Map<String, Object?> json) =>
      WorkbenchPaneGroupMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass(discriminatorKey: 'type')
abstract class const WorkbenchLayoutNode() with WorkbenchLayoutNodeMappable {
  factory leaf(String groupId) = WorkbenchLeafLayoutNode;
  factory split({
    required WorkbenchSplitAxis axis,
    required WorkbenchLayoutNode first,
    required WorkbenchLayoutNode second,
    required double ratio,
  }) = WorkbenchSplitLayoutNode;

  factory fromJson(Map<String, Object?> json) =>
      WorkbenchLayoutNodeMapper.fromMap(Map<String, dynamic>.from(json));

  String? get groupId => null;
  WorkbenchSplitAxis? get axis => null;
  WorkbenchLayoutNode? get first => null;
  WorkbenchLayoutNode? get second => null;
  double? get ratio => null;

  bool get isLeaf => groupId != null;

  List<String> leafGroupIds() {
    final groupId = this.groupId;
    if (groupId != null) {
      return <String>[groupId];
    }
    return <String>[
      ...first?.leafGroupIds() ?? const <String>[],
      ...second?.leafGroupIds() ?? const <String>[],
    ];
  }

  bool containsGroup(String groupId) {
    if (this.groupId == groupId) {
      return true;
    }
    return (first?.containsGroup(groupId) ?? false) ||
        (second?.containsGroup(groupId) ?? false);
  }

  WorkbenchLayoutNode replaceLeaf(
    String targetGroupId,
    WorkbenchLayoutNode replacement,
  ) {
    final groupId = this.groupId;
    if (groupId != null) {
      return groupId == targetGroupId ? replacement : this;
    }
    return WorkbenchLayoutNode.split(
      axis: axis!,
      first: first!.replaceLeaf(targetGroupId, replacement),
      second: second!.replaceLeaf(targetGroupId, replacement),
      ratio: ratio!,
    );
  }

  WorkbenchLayoutNode? pruneGroups(Set<String> validGroupIds) {
    final groupId = this.groupId;
    if (groupId != null) {
      return validGroupIds.contains(groupId) ? this : null;
    }
    final prunedFirst = first!.pruneGroups(validGroupIds);
    final prunedSecond = second!.pruneGroups(validGroupIds);
    if (prunedFirst == null) {
      return prunedSecond;
    }
    if (prunedSecond == null) {
      return prunedFirst;
    }
    return WorkbenchLayoutNode.split(
      axis: axis!,
      first: prunedFirst,
      second: prunedSecond,
      ratio: ratio!,
    );
  }

  WorkbenchLayoutNode updateSplitRatio(List<int> path, double nextRatio) {
    if (path.isEmpty) {
      if (isLeaf) {
        return this;
      }
      return WorkbenchLayoutNode.split(
        axis: axis!,
        first: first!,
        second: second!,
        ratio: nextRatio,
      );
    }
    if (isLeaf) {
      return this;
    }
    final head = path.first;
    final tail = path.sublist(1);
    return WorkbenchLayoutNode.split(
      axis: axis!,
      first: head == 0 ? first!.updateSplitRatio(tail, nextRatio) : first!,
      second: head == 1 ? second!.updateSplitRatio(tail, nextRatio) : second!,
      ratio: ratio!,
    );
  }
}

@MappableClass(discriminatorValue: 'leaf')
class WorkbenchLeafLayoutNode(this.groupId)
    extends WorkbenchLayoutNode
    with WorkbenchLeafLayoutNodeMappable {
  this {
    if (groupId.isEmpty) {
      throw ArgumentError.value(
        groupId,
        'groupId',
        'Workbench layout leaf group id must not be empty.',
      );
    }
  }

  @override
  final String groupId;
}

@MappableClass(discriminatorValue: 'split')
class WorkbenchSplitLayoutNode({
  required this.axis,
  required this.first,
  required this.second,
  required double ratio,
}) extends WorkbenchLayoutNode with WorkbenchSplitLayoutNodeMappable {
  this : ratio = _clampWorkbenchSplitRatio(ratio);

  @override
  final WorkbenchSplitAxis axis;

  @override
  final WorkbenchLayoutNode first;

  @override
  final WorkbenchLayoutNode second;

  @override
  final double ratio;
}

@MappableClass()
class WorkbenchLayout({
  required this.workspaceId,
  required this.root,
  required Map<String, WorkbenchPaneGroup> groups,
  required this.activeGroupId,
}) with WorkbenchLayoutMappable {
  this : groups = Map<String, WorkbenchPaneGroup>.unmodifiable(groups) {
    if (workspaceId.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'Workbench layout workspace id must not be empty.',
      );
    }
    if (activeGroupId.isEmpty) {
      throw ArgumentError.value(
        activeGroupId,
        'activeGroupId',
        'Workbench layout active group id must not be empty.',
      );
    }
  }

  final String workspaceId;
  final WorkbenchLayoutNode root;
  final Map<String, WorkbenchPaneGroup> groups;
  final String activeGroupId;

  static String defaultGroupId(String workspaceId) => '$workspaceId/main';

  factory single({
    required String workspaceId,
    required List<String> tabIds,
    String? groupId,
  }) {
    final resolvedGroupId = groupId ?? defaultGroupId(workspaceId);
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: .leaf(resolvedGroupId),
      groups: <String, WorkbenchPaneGroup>{
        resolvedGroupId: WorkbenchPaneGroup(
          id: resolvedGroupId,
          tabIds: tabIds,
          activeTabId: tabIds.isEmpty ? null : tabIds.last,
        ),
      },
      activeGroupId: resolvedGroupId,
    );
  }

  factory fromJson(Map<String, Object?> json) =>
      WorkbenchLayoutMapper.fromMap(Map<String, dynamic>.from(json));
}

WorkbenchSplitAxis? _axisForZone(WorkbenchDropZone zone) {
  return switch (zone) {
    WorkbenchDropZone.left ||
    WorkbenchDropZone.right => WorkbenchSplitAxis.horizontal,
    WorkbenchDropZone.up ||
    WorkbenchDropZone.down => WorkbenchSplitAxis.vertical,
    WorkbenchDropZone.center => null,
  };
}

WorkbenchLayoutNode _resolvedMergedRoot(
  WorkbenchLayoutNode root,
  Set<String> groupIds,
  String siblingGroupId,
) => root.pruneGroups(groupIds) ?? WorkbenchLayoutNode.leaf(siblingGroupId);

double _clampWorkbenchSplitRatio(double ratio) {
  if (ratio < workbenchMinSplitRatio) {
    return workbenchMinSplitRatio;
  }
  if (ratio > workbenchMaxSplitRatio) {
    return workbenchMaxSplitRatio;
  }
  return ratio;
}

String? _firstSiblingGroupId(WorkbenchLayoutNode node, String groupId) {
  if (node.isLeaf) {
    return null;
  }
  final first = node.first!;
  final second = node.second!;
  if (first.groupId == groupId) {
    final siblings = second.leafGroupIds();
    return siblings.isEmpty ? null : siblings.first;
  }
  if (second.groupId == groupId) {
    final siblings = first.leafGroupIds();
    return siblings.isEmpty ? null : siblings.first;
  }
  if (first.containsGroup(groupId)) {
    return _firstSiblingGroupId(first, groupId);
  }
  if (second.containsGroup(groupId)) {
    return _firstSiblingGroupId(second, groupId);
  }
  return null;
}
