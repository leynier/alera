import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/browser/domain/browser_annotation.dart';
import 'package:flutter/material.dart';

enum BrowserAnnotationInputMode { element, region }

class BrowserAnnotationOverlay extends StatefulWidget {
  const BrowserAnnotationOverlay({
    super.key,
    required this.capture,
    required this.mode,
    required this.onModeChanged,
    required this.onElementSelected,
    required this.onRegionSelected,
    required this.onDelete,
    required this.onCancel,
    required this.onDone,
  });

  final BrowserAnnotationCapture capture;
  final BrowserAnnotationInputMode mode;
  final ValueChanged<BrowserAnnotationInputMode> onModeChanged;
  final ValueChanged<Rect> onElementSelected;
  final ValueChanged<Rect> onRegionSelected;
  final ValueChanged<BrowserAnnotationComment> onDelete;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  State<BrowserAnnotationOverlay> createState() =>
      _BrowserAnnotationOverlayState();
}

class _BrowserAnnotationOverlayState extends State<BrowserAnnotationOverlay> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  Rect _imageRect(Size size) {
    final viewport = Size(
      widget.capture.viewportWidth.toDouble(),
      widget.capture.viewportHeight.toDouble(),
    );
    if (viewport.isEmpty || size.isEmpty) return Offset.zero & size;
    final scale = (size.width / viewport.width).clamp(
      0.0,
      size.height / viewport.height,
    );
    final rendered = Size(viewport.width * scale, viewport.height * scale);
    return Rect.fromLTWH(
      (size.width - rendered.width) / 2,
      (size.height - rendered.height) / 2,
      rendered.width,
      rendered.height,
    );
  }

  Rect _normalizedToImage(Rect normalized, Rect imageRect) => Rect.fromLTWH(
    imageRect.left + normalized.left * imageRect.width,
    imageRect.top + normalized.top * imageRect.height,
    normalized.width * imageRect.width,
    normalized.height * imageRect.height,
  );

  Rect _localSelection(Rect imageRect) {
    final start = _dragStart ?? Offset.zero;
    final current = _dragCurrent ?? start;
    final selection = Rect.fromPoints(start, current).intersect(imageRect);
    return Rect.fromLTWH(
      ((selection.left - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
      ((selection.top - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
      (selection.width / imageRect.width).clamp(0.0, 1.0),
      (selection.height / imageRect.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final imageRect = _imageRect(size);
        final dragRect = _dragStart == null
            ? null
            : _normalizedToImage(_localSelection(imageRect), imageRect);
        return Material(
          color: AleraTokens.bg,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.file(
                File(widget.capture.imagePath),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AleraTokens.bg,
                  child: Center(child: Text('Annotation preview unavailable.')),
                ),
              ),
              CustomPaint(
                painter: _BrowserAnnotationPainter(
                  imageRect: imageRect,
                  comments: widget.capture.comments,
                  selection: dragRect,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: widget.mode == BrowserAnnotationInputMode.element
                    ? (details) => widget.onElementSelected(
                        _selectionFromPoint(details.localPosition, imageRect),
                      )
                    : null,
                onPanStart: widget.mode == BrowserAnnotationInputMode.region
                    ? (details) => setState(() {
                        _dragStart = details.localPosition;
                        _dragCurrent = details.localPosition;
                      })
                    : null,
                onPanUpdate: widget.mode == BrowserAnnotationInputMode.region
                    ? (details) =>
                          setState(() => _dragCurrent = details.localPosition)
                    : null,
                onPanEnd: widget.mode == BrowserAnnotationInputMode.region
                    ? (_) {
                        final start = _dragStart;
                        final current = _dragCurrent;
                        if (start != null && current != null) {
                          final selection = Rect.fromPoints(
                            start,
                            current,
                          ).intersect(imageRect);
                          if (selection.width >= 8 && selection.height >= 8) {
                            widget.onRegionSelected(
                              _selectionFromRect(selection, imageRect),
                            );
                          }
                        }
                        setState(() {
                          _dragStart = null;
                          _dragCurrent = null;
                        });
                      }
                    : null,
              ),
              Positioned(
                top: AleraTokens.space8,
                left: AleraTokens.space8,
                right: AleraTokens.space8,
                child: _AnnotationToolbar(
                  mode: widget.mode,
                  commentCount: widget.capture.comments.length,
                  onModeChanged: widget.onModeChanged,
                  onCancel: widget.onCancel,
                  onDone: widget.onDone,
                ),
              ),
              if (widget.capture.comments.isNotEmpty)
                Positioned(
                  left: AleraTokens.space8,
                  right: AleraTokens.space8,
                  bottom: AleraTokens.space8,
                  child: _AnnotationCommentStrip(
                    comments: widget.capture.comments,
                    onDelete: widget.onDelete,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Rect _selectionFromPoint(Offset point, Rect imageRect) => Rect.fromLTWH(
    ((point.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
    ((point.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
    0,
    0,
  );

  Rect _selectionFromRect(Rect rect, Rect imageRect) => Rect.fromLTWH(
    ((rect.left - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
    ((rect.top - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
    (rect.width / imageRect.width).clamp(0.0, 1.0),
    (rect.height / imageRect.height).clamp(0.0, 1.0),
  );
}

class _AnnotationToolbar extends StatelessWidget {
  const _AnnotationToolbar({
    required this.mode,
    required this.commentCount,
    required this.onModeChanged,
    required this.onCancel,
    required this.onDone,
  });

  final BrowserAnnotationInputMode mode;
  final int commentCount;
  final ValueChanged<BrowserAnnotationInputMode> onModeChanged;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      border: Border.all(color: AleraTokens.borderSubtle),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        children: <Widget>[
          const Icon(AleraIcons.edit, size: AleraTokens.iconMd),
          const SizedBox(width: AleraTokens.space6),
          Text('Annotate Page', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: AleraTokens.space12),
          SegmentedButton<BrowserAnnotationInputMode>(
            segments: const <ButtonSegment<BrowserAnnotationInputMode>>[
              ButtonSegment(
                value: BrowserAnnotationInputMode.element,
                label: Text('Element'),
              ),
              ButtonSegment(
                value: BrowserAnnotationInputMode.region,
                label: Text('Region'),
              ),
            ],
            selected: <BrowserAnnotationInputMode>{mode},
            onSelectionChanged: (values) => onModeChanged(values.first),
          ),
          const Spacer(),
          Text('$commentCount Comments'),
          const SizedBox(width: AleraTokens.space8),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          FilledButton(onPressed: onDone, child: const Text('Add To Codex')),
        ],
      ),
    ),
  );
}

class _AnnotationCommentStrip extends StatelessWidget {
  const _AnnotationCommentStrip({
    required this.comments,
    required this.onDelete,
  });

  final List<BrowserAnnotationComment> comments;
  final ValueChanged<BrowserAnnotationComment> onDelete;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 120),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: comments.length,
      separatorBuilder: (_, _) => const SizedBox(width: AleraTokens.space6),
      itemBuilder: (context, index) {
        final comment = comments[index];
        return Container(
          width: 260,
          padding: const EdgeInsets.all(AleraTokens.space8),
          decoration: BoxDecoration(
            color: AleraTokens.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: AleraTokens.space8,
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  comment.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AleraIconButton(
                tooltip: 'Remove Comment',
                icon: AleraIcons.close,
                onPressed: () => onDelete(comment),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _BrowserAnnotationPainter extends CustomPainter {
  const _BrowserAnnotationPainter({
    required this.imageRect,
    required this.comments,
    this.selection,
  });

  final Rect imageRect;
  final List<BrowserAnnotationComment> comments;
  final Rect? selection;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = AleraTokens.info
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var index = 0; index < comments.length; index++) {
      final anchor = comments[index].anchor;
      final rect = Rect.fromLTWH(
        imageRect.left + anchor.x * imageRect.width,
        imageRect.top + anchor.y * imageRect.height,
        anchor.width * imageRect.width,
        anchor.height * imageRect.height,
      );
      canvas.drawRect(rect, stroke);
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(color: AleraTokens.onAccent, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final badge = Rect.fromLTWH(rect.left, rect.top, 18, 18);
      canvas.drawRect(badge, Paint()..color = AleraTokens.info);
      label.paint(canvas, badge.topLeft + const Offset(5, 2));
    }
    if (selection != null) {
      canvas.drawRect(
        selection!,
        Paint()
          ..color = AleraTokens.info.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(selection!, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _BrowserAnnotationPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.comments != comments ||
      oldDelegate.selection != selection;
}
