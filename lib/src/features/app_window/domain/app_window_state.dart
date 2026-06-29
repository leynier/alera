import 'dart:ui';

class AppWindowBounds {
  const AppWindowBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0;

  Rect toRect() => Rect.fromLTWH(left, top, width, height);

  Map<String, Object> toJson() => <String, Object>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  static AppWindowBounds? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final left = _doubleFrom(source['left']);
    final top = _doubleFrom(source['top']);
    final width = _doubleFrom(source['width']);
    final height = _doubleFrom(source['height']);
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    final bounds = AppWindowBounds(
      left: left,
      top: top,
      width: width,
      height: height,
    );
    return bounds.isValid ? bounds : null;
  }

  static AppWindowBounds fromRect(Rect rect) {
    return AppWindowBounds(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppWindowBounds &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

class AppWindowState {
  const AppWindowState({
    this.normalBounds,
    this.maximized = false,
    this.fullScreen = false,
  });

  final AppWindowBounds? normalBounds;
  final bool maximized;
  final bool fullScreen;

  Map<String, Object?> toJson() => <String, Object?>{
    'normalBounds': normalBounds?.toJson(),
    'maximized': maximized,
    'fullScreen': fullScreen,
  };

  static AppWindowState? fromJson(Object? source) {
    if (source is! Map) {
      return null;
    }
    final fullScreen = source['fullScreen'] == true;
    return AppWindowState(
      normalBounds: AppWindowBounds.fromJson(source['normalBounds']),
      maximized: fullScreen ? false : source['maximized'] == true,
      fullScreen: fullScreen,
    );
  }

  AppWindowState copyWith({
    AppWindowBounds? normalBounds,
    bool clearNormalBounds = false,
    bool? maximized,
    bool? fullScreen,
  }) {
    final nextFullScreen = fullScreen ?? this.fullScreen;
    return AppWindowState(
      normalBounds: clearNormalBounds
          ? null
          : normalBounds ?? this.normalBounds,
      maximized: nextFullScreen ? false : maximized ?? this.maximized,
      fullScreen: nextFullScreen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppWindowState &&
          normalBounds == other.normalBounds &&
          maximized == other.maximized &&
          fullScreen == other.fullScreen;

  @override
  int get hashCode => Object.hash(normalBounds, maximized, fullScreen);
}

double? _doubleFrom(Object? value) {
  return switch (value) {
    int value => value.toDouble(),
    double value => value,
    _ => null,
  };
}

Rect? clampWindowBoundsToVisibleDisplays(
  Rect? bounds,
  List<Rect> visibleDisplays,
) {
  if (bounds == null ||
      !bounds.left.isFinite ||
      !bounds.top.isFinite ||
      !bounds.width.isFinite ||
      !bounds.height.isFinite ||
      bounds.width <= 0 ||
      bounds.height <= 0) {
    return null;
  }
  final displays = visibleDisplays
      .where(
        (display) =>
            display.left.isFinite &&
            display.top.isFinite &&
            display.width.isFinite &&
            display.height.isFinite &&
            display.width > 0 &&
            display.height > 0,
      )
      .toList(growable: false);
  if (displays.isEmpty) {
    return bounds;
  }

  final target = _bestDisplayFor(bounds, displays);
  final width = bounds.width.clamp(1.0, target.width).toDouble();
  final height = bounds.height.clamp(1.0, target.height).toDouble();
  final left = bounds.left.clamp(target.left, target.right - width).toDouble();
  final top = bounds.top.clamp(target.top, target.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

Rect _bestDisplayFor(Rect bounds, List<Rect> displays) {
  Rect? bestIntersectionDisplay;
  var bestIntersectionArea = -1.0;
  for (final display in displays) {
    final intersection = bounds.intersect(display);
    final area = intersection.isEmpty
        ? 0.0
        : intersection.width * intersection.height;
    if (area > bestIntersectionArea) {
      bestIntersectionArea = area;
      bestIntersectionDisplay = display;
    }
  }
  if (bestIntersectionArea > 0 && bestIntersectionDisplay != null) {
    return bestIntersectionDisplay;
  }

  final center = bounds.center;
  return displays.reduce((best, display) {
    final bestDistance = _squaredDistance(center, best.center);
    final nextDistance = _squaredDistance(center, display.center);
    return nextDistance < bestDistance ? display : best;
  });
}

double _squaredDistance(Offset left, Offset right) {
  final dx = left.dx - right.dx;
  final dy = left.dy - right.dy;
  return dx * dx + dy * dy;
}
