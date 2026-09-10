import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:flutter/material.dart';

WorkbenchDropZone resolveWorkbenchPaneDropZone({
  required Size paneSize,
  required Offset localPosition,
}) {
  if (paneSize.width <= 0 || paneSize.height <= 0) {
    return WorkbenchDropZone.center;
  }
  final localX = localPosition.dx.clamp(0, paneSize.width);
  final localY = localPosition.dy.clamp(0, paneSize.height);
  final centerRect = workbenchCenterDropRect(paneSize);
  final local = Offset(localX.toDouble(), localY.toDouble());
  if (centerRect.contains(local)) {
    return WorkbenchDropZone.center;
  }

  final horizontalOverflow = local.dx < centerRect.left
      ? centerRect.left - local.dx
      : math.max(0, local.dx - centerRect.right);
  final verticalOverflow = local.dy < centerRect.top
      ? centerRect.top - local.dy
      : math.max(0, local.dy - centerRect.bottom);

  if (horizontalOverflow >= verticalOverflow) {
    return local.dx < paneSize.width / 2
        ? WorkbenchDropZone.left
        : WorkbenchDropZone.right;
  }
  return local.dy < paneSize.height / 2
      ? WorkbenchDropZone.up
      : WorkbenchDropZone.down;
}

Rect resolveWorkbenchDropOverlayRect({
  required WorkbenchDropZone zone,
  required Size paneSize,
}) {
  return switch (zone) {
    WorkbenchDropZone.left => Rect.fromLTWH(
      0,
      0,
      paneSize.width / 2,
      paneSize.height,
    ),
    WorkbenchDropZone.right => Rect.fromLTWH(
      paneSize.width / 2,
      0,
      paneSize.width / 2,
      paneSize.height,
    ),
    WorkbenchDropZone.up => Rect.fromLTWH(
      0,
      0,
      paneSize.width,
      paneSize.height / 2,
    ),
    WorkbenchDropZone.down => Rect.fromLTWH(
      0,
      paneSize.height / 2,
      paneSize.width,
      paneSize.height / 2,
    ),
    WorkbenchDropZone.center => workbenchCenterDropRect(paneSize),
  };
}

bool isWorkbenchPaneDropActionEnabled({
  required String sourceGroupId,
  required String targetGroupId,
  required int targetTabCount,
  required WorkbenchDropZone zone,
}) {
  if (sourceGroupId != targetGroupId) {
    return true;
  }
  if (targetTabCount <= 1) {
    return false;
  }
  return zone != WorkbenchDropZone.center;
}

int resolveWorkbenchTabStripGapIndex({
  required int chipIndex,
  required double localDx,
  required double chipWidth,
}) {
  return localDx < chipWidth / 2 ? chipIndex : chipIndex + 1;
}

int? resolveWorkbenchTabStripDropIndex({
  required List<String> tabIds,
  required String sourceGroupId,
  required String targetGroupId,
  required String draggedTabId,
  required int gapIndex,
}) {
  final clamped = gapIndex.clamp(0, tabIds.length);
  if (sourceGroupId != targetGroupId) {
    return clamped;
  }
  final sourceIndex = tabIds.indexOf(draggedTabId);
  if (sourceIndex < 0) {
    return clamped;
  }
  final adjusted = clamped > sourceIndex ? clamped - 1 : clamped;
  return adjusted == sourceIndex ? null : adjusted;
}

Rect workbenchCenterDropRect(Size paneSize) {
  const centerWidthFactor = 0.36;
  const centerHeightFactor = 0.36;
  final width = math.min(
    paneSize.width,
    math.max(AleraTokens.space48 * 2, paneSize.width * centerWidthFactor),
  );
  final height = math.min(
    paneSize.height,
    math.max(AleraTokens.space48 * 2, paneSize.height * centerHeightFactor),
  );
  return Rect.fromLTWH(
    (paneSize.width - width) / 2,
    (paneSize.height - height) / 2,
    width,
    height,
  );
}
