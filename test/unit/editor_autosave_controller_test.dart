import 'dart:async';

import 'package:alera/src/features/workbench/application/editor_autosave_controller.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorAutosaveController', () {
    test('debounces text changes into one save', () async {
      final timers = _FakeTimers();
      var dirty = true;
      var saves = 0;
      final controller = _controller(
        timers: timers,
        dirty: () => dirty,
        save: () async {
          saves += 1;
          dirty = false;
        },
      );
      addTearDown(controller.dispose);

      controller.notifyTextChanged();
      controller.notifyTextChanged();
      expect(timers.scheduled, 2);

      await timers.fireLast();

      expect(saves, 1);
      expect(controller.isPaused, isFalse);
    });

    test('waits until loading or another save is complete', () async {
      final timers = _FakeTimers();
      var dirty = true;
      var ready = false;
      var saves = 0;
      final controller = _controller(
        timers: timers,
        dirty: () => dirty,
        ready: () => ready,
        save: () async {
          saves += 1;
          dirty = false;
        },
      );
      addTearDown(controller.dispose);

      controller.notifyTextChanged();
      expect(timers.scheduled, 0);

      ready = true;
      controller.notifyStateChanged();
      await timers.fireLast();

      expect(saves, 1);
    });

    test('cancels a pending save when autosave is disabled', () async {
      final timers = _FakeTimers();
      var saves = 0;
      final controller = _controller(
        timers: timers,
        save: () async => saves += 1,
      );
      addTearDown(controller.dispose);

      controller.notifyTextChanged();
      controller.updateSettings(
        enabled: false,
        debounce: const Duration(seconds: 2),
      );
      await timers.fireAll();

      expect(saves, 0);
    });

    test('does not save after disposal', () async {
      final timers = _FakeTimers();
      var saves = 0;
      final controller = _controller(
        timers: timers,
        save: () async => saves += 1,
      );

      controller.notifyTextChanged();
      controller.dispose();
      await timers.fireAll();

      expect(saves, 0);
    });

    test('does not start a duplicate save while one is in flight', () async {
      final timers = _FakeTimers();
      final saveGate = Completer<void>();
      var dirty = true;
      var saves = 0;
      final controller = _controller(
        timers: timers,
        dirty: () => dirty,
        save: () async {
          saves += 1;
          await saveGate.future;
          dirty = false;
        },
      );
      addTearDown(controller.dispose);

      controller.notifyTextChanged();
      await timers.fireLast();
      controller.notifyTextChanged();
      expect(timers.activeCount, 0);

      saveGate.complete();
      await Future.pause(.zero);

      expect(saves, 1);
    });

    test('pauses and reports a write error without retrying', () async {
      final timers = _FakeTimers();
      final error = StateError('file changed on disk');
      Object? reportedError;
      var saves = 0;
      final controller = _controller(
        timers: timers,
        save: () async {
          saves += 1;
          throw error;
        },
        onError: (value, _) => reportedError = value,
      );
      addTearDown(controller.dispose);

      controller.notifyTextChanged();
      await timers.fireLast();
      controller.notifyTextChanged();
      await timers.fireAll();

      expect(saves, 1);
      expect(reportedError, same(error));
      expect(controller.isPaused, isTrue);
    });

    test(
      'does not report an in-flight error after autosave is disabled',
      () async {
        final timers = _FakeTimers();
        final saveGate = Completer<void>();
        Object? reportedError;
        final controller = _controller(
          timers: timers,
          save: () async {
            await saveGate.future;
            throw StateError('save failed');
          },
          onError: (error, _) => reportedError = error,
        );
        addTearDown(controller.dispose);

        controller.notifyTextChanged();
        await timers.fireLast();
        controller.updateSettings(
          enabled: false,
          debounce: const Duration(seconds: 1),
        );
        saveGate.complete();
        await Future.pause(.zero);

        expect(reportedError, isNull);
        expect(controller.isPaused, isFalse);
      },
    );

    test('pauses after an external-file conflict', () async {
      final timers = _FakeTimers();
      const conflict = native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.conflict,
        context: 'note.txt',
      );
      Object? reportedError;
      final controller = _controller(
        timers: timers,
        save: () async => throw conflict,
        onError: (value, _) => reportedError = value,
      );
      addTearDown(controller.dispose);

      controller.notifyTextChanged();
      await timers.fireLast();

      expect(reportedError, same(conflict));
      expect(
        (reportedError! as native.WorkspaceFileError).kind,
        native.WorkspaceFileErrorKind.conflict,
      );
      expect(controller.isPaused, isTrue);
    });
  });
}

EditorAutosaveController _controller({
  required _FakeTimers timers,
  bool Function()? dirty,
  bool Function()? ready,
  Future<void> Function()? save,
  void Function(Object error, StackTrace stackTrace)? onError,
}) {
  return EditorAutosaveController(
    enabled: true,
    debounce: const Duration(seconds: 1),
    isDirty: dirty ?? () => true,
    isReady: ready ?? () => true,
    save: save ?? () async {},
    onError: onError ?? (_, _) {},
    scheduleTimer: timers.schedule,
  );
}

class _FakeTimers {
  final List<_FakeTimer> _timers = <_FakeTimer>[];

  int get scheduled => _timers.length;

  int get activeCount => _timers.where((timer) => timer.isActive).length;

  Timer schedule(Duration duration, void Function() callback) {
    final timer = _FakeTimer(callback);
    _timers.add(timer);
    return timer;
  }

  Future<void> fireLast() async {
    for (var index = _timers.length - 1; index >= 0; index -= 1) {
      final timer = _timers[index];
      if (timer.isActive) {
        timer.fire();
        break;
      }
    }
    await Future.pause(.zero);
  }

  Future<void> fireAll() async {
    for (final timer in List<_FakeTimer>.of(_timers)) {
      if (timer.isActive) {
        timer.fire();
      }
    }
    await Future.pause(.zero);
  }
}

class _FakeTimer(final void Function() _callback) implements Timer {
  var _active = true;

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
