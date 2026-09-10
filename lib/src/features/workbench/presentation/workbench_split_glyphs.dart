import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:flutter/material.dart';

Rect workbenchSplitDirectionFillRect(WorkbenchDropZone zone, Size size) {
  return switch (zone) {
    WorkbenchDropZone.right => Rect.fromLTWH(
      size.width * 0.6,
      0,
      size.width * 0.4,
      size.height,
    ),
    WorkbenchDropZone.left => Rect.fromLTWH(
      0,
      0,
      size.width * 0.4,
      size.height,
    ),
    WorkbenchDropZone.down => Rect.fromLTWH(
      0,
      size.height * 0.6,
      size.width,
      size.height * 0.4,
    ),
    WorkbenchDropZone.up => Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
    WorkbenchDropZone.center => Rect.zero,
  };
}

class const WorkbenchSplitDirectionGlyph({
  super.key,
  required final WorkbenchDropZone zone,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const .square(14),
      painter: WorkbenchSplitDirectionPainter(zone: zone),
    );
  }
}

class const WorkbenchSplitDirectionPainter({
  required final WorkbenchDropZone zone,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const .circular(AleraTokens.radiusSm),
    );
    final fillRect = workbenchSplitDirectionFillRect(zone, size);
    if (!fillRect.isEmpty) {
      canvas
        ..save()
        ..clipRRect(outerRRect)
        ..drawRect(fillRect, Paint()..color = AleraTokens.foreground)
        ..restore();
    }
    canvas.drawRRect(
      outerRRect,
      Paint()
        ..color = AleraTokens.foregroundMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant WorkbenchSplitDirectionPainter oldDelegate) {
    return oldDelegate.zone != zone;
  }
}
