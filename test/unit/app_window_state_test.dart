import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/features/app_window/infra/platform_app_window_close_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppWindowState', () {
    test('round-trips JSON and ignores invalid bounds', () {
      const state = AppWindowState(
        normalBounds: AppWindowBounds(
          left: 10,
          top: 20,
          width: 1200,
          height: 800,
        ),
        maximized: true,
      );

      expect(AppWindowState.fromJson(state.toJson()), state);
      expect(
        AppWindowState.fromJson(<String, Object?>{
          'normalBounds': <String, Object?>{
            'left': 0,
            'top': 0,
            'width': -1,
            'height': 800,
          },
          'maximized': true,
        })?.normalBounds,
        isNull,
      );
    });

    test('covers value equality, copy variants, and invalid JSON', () {
      const bounds = AppWindowBounds(left: 1, top: 2, width: 3, height: 4);
      const sameBounds = AppWindowBounds(left: 1, top: 2, width: 3, height: 4);
      const state = AppWindowState(normalBounds: bounds, maximized: true);

      expect(bounds, sameBounds);
      expect(bounds.hashCode, sameBounds.hashCode);
      expect(AppWindowBounds.fromRect(bounds.toRect()), bounds);
      expect(AppWindowBounds.fromJson(null), isNull);
      expect(
        AppWindowBounds.fromJson(<String, Object?>{
          'left': double.nan,
          'top': 0,
          'width': 10,
          'height': 10,
        }),
        isNull,
      );
      expect(AppWindowState.fromJson(null), isNull);
      expect(
        AppWindowState.fromJson(<String, Object?>{
          'maximized': true,
          'fullScreen': true,
        }),
        const AppWindowState(fullScreen: true),
      );

      final copied = state.copyWith(
        normalBounds: const AppWindowBounds(
          left: 5,
          top: 6,
          width: 7,
          height: 8,
        ),
        maximized: false,
      );
      expect(copied.maximized, isFalse);
      expect(copied.normalBounds?.left, 5);
      expect(state.copyWith(clearNormalBounds: true).normalBounds, isNull);
      expect(state.copyWith(fullScreen: true).maximized, isFalse);
      expect(
        state,
        const AppWindowState(normalBounds: bounds, maximized: true),
      );
      expect(
        state.hashCode,
        const AppWindowState(normalBounds: bounds, maximized: true).hashCode,
      );
    });

    test('clamps restored bounds into the nearest visible display', () {
      final clamped = clampWindowBoundsToVisibleDisplays(
        const Rect.fromLTWH(2500, 100, 2000, 1200),
        const <Rect>[
          Rect.fromLTWH(0, 0, 1440, 900),
          Rect.fromLTWH(1440, 0, 1280, 800),
        ],
      );

      expect(clamped, const Rect.fromLTWH(1440, 0, 1280, 800));
    });

    test('clamps to the nearest display when there is no intersection', () {
      final clamped = clampWindowBoundsToVisibleDisplays(
        const Rect.fromLTWH(5000, 5000, 500, 400),
        const <Rect>[
          Rect.fromLTWH(0, 0, 1000, 800),
          Rect.fromLTWH(1200, 0, 1000, 800),
        ],
      );

      expect(clamped, const Rect.fromLTWH(1700, 400, 500, 400));
      expect(
        clampWindowBoundsToVisibleDisplays(
          const Rect.fromLTWH(1, 2, 3, 4),
          const <Rect>[Rect.fromLTWH(0, 0, -1, 10)],
        ),
        const Rect.fromLTWH(1, 2, 3, 4),
      );
      expect(clampWindowBoundsToVisibleDisplays(null, const <Rect>[]), isNull);
      expect(
        clampWindowBoundsToVisibleDisplays(
          const Rect.fromLTWH(0, 0, double.nan, 10),
          const <Rect>[],
        ),
        isNull,
      );
    });
  });

  group('AppWindowRestorer', () {
    test('applies clamped normal bounds before maximizing', () async {
      final repository = _FakeAppWindowStateRepository(
        const AppWindowState(
          normalBounds: AppWindowBounds(
            left: -200,
            top: 50,
            width: 1000,
            height: 700,
          ),
          maximized: true,
        ),
      );
      final window = _FakeAppWindowController();
      final displays = _FakeDisplayProvider(const <Rect>[
        Rect.fromLTWH(0, 0, 1440, 900),
      ]);

      await AppWindowRestorer(
        repository: repository,
        window: window,
        displays: displays,
      ).restore();

      expect(window.bounds, const Rect.fromLTWH(0, 50, 1000, 700));
      expect(window.maximizeCalls, 1);
      expect(window.fullScreen, isFalse);
    });

    test('restores fullscreen instead of maximizing', () async {
      final repository = _FakeAppWindowStateRepository(
        const AppWindowState(fullScreen: true, maximized: true),
      );
      final window = _FakeAppWindowController();

      await AppWindowRestorer(
        repository: repository,
        window: window,
        displays: _FakeDisplayProvider(const <Rect>[]),
      ).restore();

      expect(window.fullScreen, isTrue);
      expect(window.maximizeCalls, 0);
    });
  });

  group('AppWindowLifecycleCoordinator', () {
    test('preserves normal bounds when saving maximized state', () async {
      final repository = _FakeAppWindowStateRepository(
        const AppWindowState(
          normalBounds: AppWindowBounds(
            left: 40,
            top: 60,
            width: 900,
            height: 600,
          ),
        ),
      );
      final window = _FakeAppWindowController()
        ..bounds = const Rect.fromLTWH(0, 0, 1440, 900);
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
      );
      await coordinator.start();

      window.maximized = true;
      window.emit((listener) => listener.onWindowMaximize());
      await coordinator.flush();

      expect(
        repository.saved.last,
        const AppWindowState(
          normalBounds: AppWindowBounds(
            left: 40,
            top: 60,
            width: 900,
            height: 600,
          ),
          maximized: true,
        ),
      );
    });

    test('flushes current bounds before destroying on close', () async {
      final repository = _FakeAppWindowStateRepository(null);
      final window = _FakeAppWindowController()
        ..bounds = const Rect.fromLTWH(100, 120, 1100, 700);
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
      );
      await coordinator.start();

      window.bounds = const Rect.fromLTWH(160, 180, 1200, 760);
      window.emit((listener) => listener.onWindowClose());
      await _waitFor(() => window.destroyed);

      expect(window.preventCloseValues, <bool>[true, false]);
      expect(window.destroyed, isTrue);
      expect(
        repository.saved.last.normalBounds,
        const AppWindowBounds(left: 160, top: 180, width: 1200, height: 760),
      );
    });

    test('does not overwrite state while minimized', () async {
      final repository = _FakeAppWindowStateRepository(
        const AppWindowState(
          normalBounds: AppWindowBounds(
            left: 10,
            top: 20,
            width: 1000,
            height: 700,
          ),
        ),
      );
      final window = _FakeAppWindowController()
        ..minimized = true
        ..bounds = const Rect.fromLTWH(300, 400, 500, 300);
      final coordinator = AppWindowLifecycleCoordinator(
        repository: repository,
        window: window,
        saveDebounce: Duration.zero,
      );
      await coordinator.start();

      await coordinator.flush();

      expect(repository.saved, isEmpty);
    });

    test(
      'Linux close flushes and exits without destroying the GTK window',
      () async {
        final repository = _FakeAppWindowStateRepository(null);
        final window = _FakeAppWindowController()
          ..bounds = const Rect.fromLTWH(40, 60, 1000, 700);
        final exitCodes = <int>[];
        var detached = false;
        final coordinator = AppWindowLifecycleCoordinator(
          repository: repository,
          window: window,
          closeStrategy: PlatformAppWindowCloseStrategy(
            isLinux: true,
            beforeLinuxExit: () async {
              detached = true;
            },
            exitProcess: exitCodes.add,
          ),
          saveDebounce: Duration.zero,
        );
        await coordinator.start();

        window.emit((listener) => listener.onWindowClose());
        await _waitFor(() => exitCodes.isNotEmpty);

        expect(detached, isTrue);
        expect(exitCodes, <int>[0]);
        expect(window.destroyed, isFalse);
        expect(window.preventCloseValues, <bool>[true]);
        expect(repository.saved, hasLength(1));
      },
    );
  });
}

class _FakeAppWindowStateRepository implements AppWindowStateRepository {
  _FakeAppWindowStateRepository(this.state);

  AppWindowState? state;
  final List<AppWindowState> saved = <AppWindowState>[];

  @override
  Future<void> clear() async {
    state = null;
  }

  @override
  Future<AppWindowState?> load() async => state;

  @override
  Future<void> save(AppWindowState state) async {
    this.state = state;
    saved.add(state);
  }
}

class _FakeDisplayProvider implements AppWindowDisplayProvider {
  const _FakeDisplayProvider(this.bounds);

  final List<Rect> bounds;

  @override
  Future<List<Rect>> visibleDisplayBounds() async => bounds;
}

class _FakeAppWindowController implements AppWindowController {
  final List<AppWindowEventListener> listeners = <AppWindowEventListener>[];
  final List<bool> preventCloseValues = <bool>[];
  Rect bounds = const Rect.fromLTWH(0, 0, 1280, 720);
  bool maximized = false;
  bool fullScreen = false;
  bool minimized = false;
  bool destroyed = false;
  int maximizeCalls = 0;
  int hideCalls = 0;
  bool visible = true;

  void emit(void Function(AppWindowEventListener listener) notify) {
    for (final listener in List<AppWindowEventListener>.from(listeners)) {
      notify(listener);
    }
  }

  @override
  void addListener(AppWindowEventListener listener) {
    listeners.add(listener);
  }

  @override
  Future<void> destroy() async {
    destroyed = true;
  }

  @override
  Future<void> hide() async {
    hideCalls += 1;
    visible = false;
  }

  @override
  Future<void> show() async {
    visible = true;
  }

  @override
  Future<void> restore() async {
    minimized = false;
  }

  @override
  Future<void> focus() async {}

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<void> maximize() async {
    maximized = true;
    maximizeCalls += 1;
  }

  @override
  void removeListener(AppWindowEventListener listener) {
    listeners.remove(listener);
  }

  @override
  Future<void> setBounds(Rect bounds) async {
    this.bounds = bounds;
  }

  @override
  Future<void> setFullScreen(bool value) async {
    fullScreen = value;
  }

  @override
  Future<void> setPreventClose(bool value) async {
    preventCloseValues.add(value);
  }

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> close() async {
    emit((listener) => listener.onWindowClose());
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition was not met');
}
