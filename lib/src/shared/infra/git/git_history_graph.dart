import 'package:alera/src/shared/infra/git/git_diff_models.dart';

const String gitHistoryIncomingChangesId = 'git-history-incoming-changes';
const String gitHistoryOutgoingChangesId = 'git-history-outgoing-changes';

class const GitHistoryGraphNode({
  required final String id,
  required final GitHistoryGraphColorId color,
});

class const GitHistoryItemViewModel({
  required final GitHistoryItem historyItem,
  required final List<GitHistoryGraphNode> inputSwimlanes,
  required final List<GitHistoryGraphNode> outputSwimlanes,
  required final GitHistoryItemViewModelKind kind,
}) {
  GitHistoryItemViewModel copyWith({
    List<GitHistoryGraphNode>? inputSwimlanes,
    List<GitHistoryGraphNode>? outputSwimlanes,
  }) {
    return GitHistoryItemViewModel(
      historyItem: historyItem,
      inputSwimlanes: inputSwimlanes ?? this.inputSwimlanes,
      outputSwimlanes: outputSwimlanes ?? this.outputSwimlanes,
      kind: kind,
    );
  }
}

enum GitHistoryItemViewModelKind {
  head,
  node,
  incomingChanges,
  outgoingChanges,
}

Map<String, GitHistoryGraphColorId?> buildDefaultGitHistoryColorMap({
  GitHistoryItemRef? currentRef,
  GitHistoryItemRef? remoteRef,
  GitHistoryItemRef? baseRef,
}) {
  return <String, GitHistoryGraphColorId?>{
    if (currentRef != null) currentRef.id: gitHistoryRefColor,
    if (remoteRef != null) remoteRef.id: gitHistoryRemoteRefColor,
    if (baseRef != null) baseRef.id: gitHistoryBaseRefColor,
  };
}

List<GitHistoryItemViewModel> buildGitHistoryViewModels(
  GitHistoryResult result,
) {
  return buildGitHistoryViewModelsFromItems(
    result.items,
    colorMap: buildDefaultGitHistoryColorMap(
      currentRef: result.currentRef,
      remoteRef: result.remoteRef,
      baseRef: result.baseRef,
    ),
    currentRef: result.currentRef,
    remoteRef: result.remoteRef,
    baseRef: result.baseRef,
    addIncomingChanges: result.hasIncomingChanges,
    addOutgoingChanges: result.hasOutgoingChanges,
    mergeBase: result.mergeBase,
  );
}

List<GitHistoryItemViewModel> buildGitHistoryViewModelsFromItems(
  List<GitHistoryItem> historyItems, {
  Map<String, GitHistoryGraphColorId?> colorMap =
      const <String, GitHistoryGraphColorId?>{},
  GitHistoryItemRef? currentRef,
  GitHistoryItemRef? remoteRef,
  GitHistoryItemRef? baseRef,
  bool addIncomingChanges = false,
  bool addOutgoingChanges = false,
  String? mergeBase,
}) {
  var colorIndex = -1;
  final viewModels = <GitHistoryItemViewModel>[];

  for (final historyItem in historyItems) {
    final kind = historyItem.id == currentRef?.revision
        ? GitHistoryItemViewModelKind.head
        : GitHistoryItemViewModelKind.node;
    final inputSwimlanes =
        (viewModels.lastOrNull?.outputSwimlanes ??
                const <GitHistoryGraphNode>[])
            .map(_cloneNode)
            .toList(growable: true);
    final outputSwimlanes = <GitHistoryGraphNode>[];
    var firstParentAdded = false;

    if (historyItem.parentIds.isNotEmpty) {
      for (final node in inputSwimlanes) {
        if (node.id == historyItem.id) {
          if (!firstParentAdded) {
            outputSwimlanes.add(
              GitHistoryGraphNode(
                id: historyItem.parentIds.first,
                color: _labelColor(historyItem, colorMap) ?? node.color,
              ),
            );
            firstParentAdded = true;
          }
          continue;
        }
        outputSwimlanes.add(_cloneNode(node));
      }
    }

    for (
      var index = firstParentAdded ? 1 : 0;
      index < historyItem.parentIds.length;
      index += 1
    ) {
      var color = index == 0
          ? _labelColor(historyItem, colorMap)
          : _parentLabelColor(
              historyItems,
              historyItem.parentIds[index],
              colorMap,
            );
      if (color == null) {
        colorIndex = _rotate(colorIndex + 1, gitHistoryLaneColors.length);
        color = gitHistoryLaneColors[colorIndex];
      }
      outputSwimlanes.add(
        GitHistoryGraphNode(id: historyItem.parentIds[index], color: color),
      );
    }

    final references =
        historyItem.references
            .map((itemRef) {
              var color = colorMap[itemRef.id];
              if (colorMap.containsKey(itemRef.id) && color == null) {
                final inputIndex = inputSwimlanes.indexWhere(
                  (node) => node.id == historyItem.id,
                );
                final circleIndex = inputIndex == -1
                    ? inputSwimlanes.length
                    : inputIndex;
                if (circleIndex < outputSwimlanes.length) {
                  color = outputSwimlanes[circleIndex].color;
                } else if (circleIndex < inputSwimlanes.length) {
                  color = inputSwimlanes[circleIndex].color;
                } else {
                  color = gitHistoryRefColor;
                }
              }
              return itemRef.copyWith(color: color);
            })
            .toList(growable: false)
          ..sort(
            (a, b) => compareGitHistoryRefs(
              a,
              b,
              currentRef: currentRef,
              remoteRef: remoteRef,
              baseRef: baseRef,
            ),
          );

    viewModels.add(
      GitHistoryItemViewModel(
        historyItem: historyItem.copyWith(references: references),
        inputSwimlanes: List<GitHistoryGraphNode>.unmodifiableOf(
          inputSwimlanes,
        ),
        outputSwimlanes: List<GitHistoryGraphNode>.unmodifiableOf(
          outputSwimlanes,
        ),
        kind: kind,
      ),
    );
  }

  _addIncomingOutgoingChangesHistoryItems(
    viewModels,
    currentRef: currentRef,
    remoteRef: remoteRef,
    addIncomingChanges: addIncomingChanges,
    addOutgoingChanges: addOutgoingChanges,
    mergeBase: mergeBase,
  );

  return viewModels;
}

int compareGitHistoryRefs(
  GitHistoryItemRef a,
  GitHistoryItemRef b, {
  GitHistoryItemRef? currentRef,
  GitHistoryItemRef? remoteRef,
  GitHistoryItemRef? baseRef,
}) {
  int order(GitHistoryItemRef itemRef) {
    if (itemRef.id == currentRef?.id) {
      return 1;
    }
    if (itemRef.id == remoteRef?.id) {
      return 2;
    }
    if (itemRef.id == baseRef?.id) {
      return 3;
    }
    if (itemRef.color != null) {
      return 4;
    }
    return 99;
  }

  return order(a).compareTo(order(b));
}

int gitHistoryItemLaneIndex(GitHistoryItemViewModel viewModel) {
  final inputIndex = viewModel.inputSwimlanes.indexWhere(
    (node) => node.id == viewModel.historyItem.id,
  );
  return inputIndex == -1 ? viewModel.inputSwimlanes.length : inputIndex;
}

int gitHistoryMergeParentLaneIndex(
  GitHistoryItemViewModel viewModel,
  String parentId,
) {
  return _findLastIndex(
    viewModel.outputSwimlanes,
    (node) => node.id == parentId,
  );
}

GitHistoryGraphNode _cloneNode(GitHistoryGraphNode node) {
  return GitHistoryGraphNode(id: node.id, color: node.color);
}

GitHistoryGraphColorId? _labelColor(
  GitHistoryItem item,
  Map<String, GitHistoryGraphColorId?> colorMap,
) {
  if (item.id == gitHistoryIncomingChangesId) {
    return gitHistoryRemoteRefColor;
  }
  if (item.id == gitHistoryOutgoingChangesId) {
    return gitHistoryRefColor;
  }
  for (final itemRef in item.references) {
    if (colorMap.containsKey(itemRef.id)) {
      return colorMap[itemRef.id];
    }
  }
  return null;
}

GitHistoryGraphColorId? _parentLabelColor(
  List<GitHistoryItem> items,
  String parentId,
  Map<String, GitHistoryGraphColorId?> colorMap,
) {
  for (final item in items) {
    if (item.id == parentId) {
      return _labelColor(item, colorMap);
    }
  }
  return null;
}

void _addIncomingOutgoingChangesHistoryItems(
  List<GitHistoryItemViewModel> viewModels, {
  GitHistoryItemRef? currentRef,
  GitHistoryItemRef? remoteRef,
  bool addIncomingChanges = false,
  bool addOutgoingChanges = false,
  String? mergeBase,
}) {
  if (currentRef?.revision == remoteRef?.revision || mergeBase == null) {
    return;
  }
  if (addIncomingChanges &&
      remoteRef != null &&
      remoteRef.revision != mergeBase) {
    _addIncomingChangesHistoryItem(viewModels, remoteRef, mergeBase);
  }
  if (addOutgoingChanges &&
      currentRef?.revision != null &&
      currentRef!.revision != mergeBase) {
    _addOutgoingChangesHistoryItem(viewModels, currentRef, mergeBase);
  }
}

void _addIncomingChangesHistoryItem(
  List<GitHistoryItemViewModel> viewModels,
  GitHistoryItemRef remoteRef,
  String mergeBase,
) {
  final beforeIndex = _findLastIndex(
    viewModels,
    (viewModel) =>
        viewModel.outputSwimlanes.any((node) => node.id == mergeBase),
  );
  final afterIndex = viewModels.indexWhere(
    (viewModel) => viewModel.historyItem.id == mergeBase,
  );
  if (afterIndex == -1) {
    return;
  }
  final before = beforeIndex == -1 ? null : viewModels[beforeIndex];
  final incomingChangeMerged =
      before?.historyItem.parentIds.length == 2 &&
      before!.historyItem.parentIds.contains(mergeBase);
  if (incomingChangeMerged) {
    return;
  }
  final after = viewModels[afterIndex];
  final inputSwimlanes = (before?.outputSwimlanes ?? after.inputSwimlanes)
      .map((node) => _remoteBoundaryInputNode(node, mergeBase))
      .toList(growable: true);
  final outputSwimlanes = after.inputSwimlanes.map(_cloneNode).toList();
  _ensureIncomingRemoteLane(inputSwimlanes, outputSwimlanes, mergeBase);

  if (before != null) {
    viewModels[beforeIndex] = before.copyWith(
      inputSwimlanes: before.inputSwimlanes
          .map((node) => _remoteBoundaryInputNode(node, mergeBase))
          .toList(growable: false),
      outputSwimlanes: inputSwimlanes.map(_cloneNode).toList(growable: false),
    );
  }

  final displayIdLength =
      viewModels.firstOrNull?.historyItem.displayId?.length ?? 0;
  viewModels.insert(
    afterIndex,
    GitHistoryItemViewModel(
      historyItem: GitHistoryItem(
        id: gitHistoryIncomingChangesId,
        parentIds: <String>[mergeBase],
        subject: 'Incoming Changes',
        message: '',
        displayId: List<String>.filled(displayIdLength, '0').join(),
        author: remoteRef.name,
      ),
      inputSwimlanes: List<GitHistoryGraphNode>.unmodifiableOf(inputSwimlanes),
      outputSwimlanes: List<GitHistoryGraphNode>.unmodifiableOf(
        outputSwimlanes,
      ),
      kind: .incomingChanges,
    ),
  );
  viewModels[afterIndex + 1] = after.copyWith(
    inputSwimlanes: outputSwimlanes.map(_cloneNode).toList(growable: false),
  );
}

void _addOutgoingChangesHistoryItem(
  List<GitHistoryItemViewModel> viewModels,
  GitHistoryItemRef currentRef,
  String mergeBase,
) {
  final currentRevision = currentRef.revision;
  if (currentRevision == null) {
    return;
  }
  final currentIndex = viewModels.indexWhere(
    (viewModel) =>
        viewModel.kind == GitHistoryItemViewModelKind.head &&
        viewModel.historyItem.id == currentRevision,
  );
  final anchorIndex = currentIndex == -1
      ? _firstVisibleOutgoingIndex(viewModels, mergeBase)
      : currentIndex;
  if (anchorIndex == -1) {
    return;
  }
  final anchorRevision = currentIndex == -1
      ? viewModels[anchorIndex].historyItem.id
      : currentRevision;
  final displayIdLength =
      viewModels.firstOrNull?.historyItem.displayId?.length ?? 0;
  final inputSwimlanes = viewModels[anchorIndex].inputSwimlanes
      .map(_cloneNode)
      .toList(growable: false);
  final outputSwimlanes = inputSwimlanes.map(_cloneNode).toList(growable: true)
    ..add(GitHistoryGraphNode(id: anchorRevision, color: gitHistoryRefColor));
  viewModels.insert(
    anchorIndex,
    GitHistoryItemViewModel(
      historyItem: GitHistoryItem(
        id: gitHistoryOutgoingChangesId,
        parentIds: <String>[anchorRevision],
        subject: 'Outgoing Changes',
        message: '',
        displayId: List<String>.filled(displayIdLength, '0').join(),
        author: currentRef.name,
      ),
      inputSwimlanes: inputSwimlanes,
      outputSwimlanes: List<GitHistoryGraphNode>.unmodifiableOf(
        outputSwimlanes,
      ),
      kind: .outgoingChanges,
    ),
  );
  viewModels[anchorIndex + 1] = viewModels[anchorIndex + 1].copyWith(
    inputSwimlanes: <GitHistoryGraphNode>[
      ...viewModels[anchorIndex + 1].inputSwimlanes,
      GitHistoryGraphNode(id: anchorRevision, color: gitHistoryRefColor),
    ],
  );
}

int _firstVisibleOutgoingIndex(
  List<GitHistoryItemViewModel> viewModels,
  String mergeBase,
) {
  final mergeBaseIndex = viewModels.indexWhere(
    (viewModel) => viewModel.historyItem.id == mergeBase,
  );
  final endIndex = mergeBaseIndex == -1 ? viewModels.length : mergeBaseIndex;
  for (var index = 0; index < endIndex; index += 1) {
    final itemId = viewModels[index].historyItem.id;
    if (itemId == gitHistoryIncomingChangesId ||
        itemId == gitHistoryOutgoingChangesId) {
      continue;
    }
    return index;
  }
  return -1;
}

GitHistoryGraphNode _remoteBoundaryInputNode(
  GitHistoryGraphNode node,
  String mergeBase,
) {
  if (node.id == mergeBase && node.color == gitHistoryRemoteRefColor) {
    return const GitHistoryGraphNode(
      id: gitHistoryIncomingChangesId,
      color: gitHistoryRemoteRefColor,
    );
  }
  return _cloneNode(node);
}

void _ensureIncomingRemoteLane(
  List<GitHistoryGraphNode> inputSwimlanes,
  List<GitHistoryGraphNode> outputSwimlanes,
  String mergeBase,
) {
  if (!_hasNode(outputSwimlanes, mergeBase, gitHistoryRemoteRefColor)) {
    final localMergeBaseIndex = outputSwimlanes.indexWhere(
      (node) => node.id == mergeBase && node.color == gitHistoryRefColor,
    );
    outputSwimlanes.insert(
      localMergeBaseIndex == -1
          ? inputSwimlanes.length
          : localMergeBaseIndex + 1,
      GitHistoryGraphNode(id: mergeBase, color: gitHistoryRemoteRefColor),
    );
  }
  if (_hasNode(
    inputSwimlanes,
    gitHistoryIncomingChangesId,
    gitHistoryRemoteRefColor,
  )) {
    return;
  }
  final remoteMergeBaseIndex = outputSwimlanes.indexWhere(
    (node) => node.id == mergeBase && node.color == gitHistoryRemoteRefColor,
  );
  inputSwimlanes.insert(
    remoteMergeBaseIndex == -1 ? inputSwimlanes.length : remoteMergeBaseIndex,
    const GitHistoryGraphNode(
      id: gitHistoryIncomingChangesId,
      color: gitHistoryRemoteRefColor,
    ),
  );
}

bool _hasNode(
  List<GitHistoryGraphNode> nodes,
  String id,
  GitHistoryGraphColorId color,
) {
  return nodes.any((node) => node.id == id && node.color == color);
}

int _findLastIndex<T>(List<T> items, bool Function(T item) predicate) {
  for (var index = items.length - 1; index >= 0; index -= 1) {
    if (predicate(items[index])) {
      return index;
    }
  }
  return -1;
}

int _rotate(int index, int length) {
  return ((index % length) + length) % length;
}
