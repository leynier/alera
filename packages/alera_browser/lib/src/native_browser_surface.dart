import 'dart:async';

import 'package:flutter/widgets.dart';

typedef AleraBrowserBoundsChanged =
    Future<void> Function(Rect bounds, double scale);

final class AleraNativeBrowserSurface extends StatefulWidget {
  const AleraNativeBrowserSurface({required this.onBoundsChanged, super.key});

  final AleraBrowserBoundsChanged onBoundsChanged;

  @override
  State<AleraNativeBrowserSurface> createState() =>
      _AleraNativeBrowserSurfaceState();
}

final class _AleraNativeBrowserSurfaceState
    extends State<AleraNativeBrowserSurface>
    with WidgetsBindingObserver {
  Rect? _lastBounds;
  double? _lastScale;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleBoundsUpdate();
  }

  @override
  void didUpdateWidget(covariant AleraNativeBrowserSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleBoundsUpdate();
  }

  @override
  void didChangeMetrics() {
    _scheduleBoundsUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleBoundsUpdate() {
    if (_updateScheduled) {
      return;
    }
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) {
        return;
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          renderObject.size.isEmpty) {
        return;
      }
      final origin = renderObject.localToGlobal(Offset.zero);
      final bounds = origin & renderObject.size;
      final scale = MediaQuery.devicePixelRatioOf(context);
      if (bounds == _lastBounds && scale == _lastScale) {
        return;
      }
      _lastBounds = bounds;
      _lastScale = scale;
      unawaited(widget.onBoundsChanged(bounds, scale));
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBoundsUpdate();
    // Layout-only size changes (sidebar/split resize without metrics change)
    // must still push page.setBounds to the native overlay.
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        _scheduleBoundsUpdate();
        return true;
      },
      child: const SizeChangedLayoutNotifier(child: SizedBox.expand()),
    );
  }
}
